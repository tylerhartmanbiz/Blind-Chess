#!/usr/bin/env python3
"""Acoustic environments for SpeechLab clips (portable: numpy + scipy + soundfile + audiotsm).

    augment.py --in clean_manifest.jsonl --root DIR --noise NOISEDIR --out manifest.jsonl [--per-clip 1]

Reads clean 16 kHz mono clips (manifest rows with env == "clean"), keeps them, and adds `--per-clip`
augmented copies per clip, choosing environments in a balanced rotation (deterministic by clip id).
Noise bank (NOISEDIR/*.wav, 16 kHz mono): cafe.wav street.wav living.wav babble.wav tv.wav; white and
fan noise are synthesised.
"""
import argparse
import hashlib
import json
import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 16000

ENVS = ["cafe_10", "cafe_5", "street_10", "street_5", "living_10", "babble_10", "babble_5", "tv_10",
        "white_20", "white_10", "fan_10", "reverb_room", "reverb_hall", "phone", "quiet_-15", "far",
        "fast", "slow"]


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def rms(x):
    return float(np.sqrt(np.mean(x ** 2) + 1e-12))


def speech_rms(x):
    """RMS over the louder half of 20 ms frames (ignores the silence padding)."""
    n = 320
    frames = x[: len(x) // n * n].reshape(-1, n)
    e = np.sqrt((frames ** 2).mean(axis=1) + 1e-12)
    e = np.sort(e)[len(e) // 2:]
    return float(np.sqrt((e ** 2).mean()))


_noise_cache = {}


def noise_segment(name, n, rng, noisedir):
    if name == "white":
        return rng.standard_normal(n)
    if name == "fan":  # brown-ish broadband hum like a desk fan / AC
        w = rng.standard_normal(n + 2000)
        b, a = signal.butter(2, 600 / (SR / 2), "low")
        y = signal.lfilter(b, a, w)[2000:]
        hum = 0.3 * np.sin(2 * np.pi * 120 * np.arange(n) / SR) * np.std(y)
        return y + hum
    if name not in _noise_cache:
        x, sr = sf.read(os.path.join(noisedir, name + ".wav"), dtype="float32", always_2d=True)
        x = x[:, 0]
        assert sr == SR, (name, sr)
        _noise_cache[name] = x
    x = _noise_cache[name]
    start = rng.integers(0, max(1, len(x) - n))
    seg = x[start:start + n]
    if len(seg) < n:
        seg = np.pad(seg, (0, n - len(seg)), mode="wrap")
    return seg.astype(np.float64)


def add_noise(x, name, snr, rng, noisedir):
    nz = noise_segment(name, len(x), rng, noisedir)
    target = speech_rms(x) / (10 ** (snr / 20))
    return x + nz * (target / (rms(nz) + 1e-12))


def synth_rir(rt60, rng):
    n = int(SR * rt60 * 1.2)
    t = np.arange(n) / SR
    decay = np.exp(-6.9 * t / rt60)
    rir = rng.standard_normal(n) * decay
    rir[0] = 0
    direct = np.zeros(n)
    direct[0] = 1.0
    # early reflections + diffuse tail; direct-to-reverberant ratio falls with rt60
    early = np.zeros(n)
    for _ in range(8):
        k = int(rng.uniform(0.002, 0.03) * SR)
        early[k] += rng.uniform(-0.5, 0.5)
    return direct + early + rir * (0.25 + 0.2 * rt60)


def reverb(x, rt60, rng):
    y = signal.fftconvolve(x, synth_rir(rt60, rng))[: len(x)]
    return y * (rms(x) / (rms(y) + 1e-12))


def phone(x):
    y = signal.resample_poly(x, 1, 2)  # 8 kHz
    b, a = signal.butter(4, [300 / 4000, 3400 / 4000], "band")
    y = signal.lfilter(b, a, y)
    peak = np.max(np.abs(y)) + 1e-9
    y = np.tanh(2.0 * y / peak) * peak / 2.0  # mild codec-ish compression
    mu = 255.0  # mu-law 8-bit quantisation
    m = np.sign(y / peak) * np.log1p(mu * np.abs(y / peak)) / np.log1p(mu)
    m = np.round(m * 127) / 127
    y = np.sign(m) * (np.expm1(np.abs(m) * np.log1p(mu)) / mu) * peak
    return signal.resample_poly(y, 2, 1)[: len(x)]


def tempo(x, speed):
    from audiotsm import wsola
    from audiotsm.io.array import ArrayReader, ArrayWriter
    reader = ArrayReader(x[np.newaxis, :].astype(np.float32))
    writer = ArrayWriter(1)
    wsola(1, speed=speed).run(reader, writer)
    return writer.data[0].astype(np.float64)


def apply_env(x, env, rng, noisedir):
    if env == "clean":
        return x
    if env.startswith(("cafe_", "street_", "living_", "babble_", "tv_", "white_", "fan_")):
        name, snr = env.split("_")
        return add_noise(x, name, float(snr), rng, noisedir)
    if env == "reverb_room":
        return reverb(x, 0.45, rng)
    if env == "reverb_hall":
        return reverb(x, 1.1, rng)
    if env == "phone":
        return phone(x)
    if env == "quiet_-15":
        return x * 10 ** (-15 / 20)
    if env == "far":  # far from the mic: quieter, reverberant, a little room noise
        y = reverb(x, 0.6, rng) * 10 ** (-15 / 20)
        return add_noise(y, "fan", 25, rng, noisedir)
    if env == "fast":
        return tempo(x, 1.35)
    if env == "slow":
        return tempo(x, 0.75)
    raise ValueError(env)


def load16k(path):
    x, sr = sf.read(path, dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        from math import gcd
        g = gcd(sr, SR)
        x = signal.resample_poly(x, SR // g, sr // g)
    return x


def finish(x):
    peak = np.max(np.abs(x)) + 1e-12
    if peak > 0.99:
        x = x * (0.99 / peak)
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--noise", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-clip", type=int, default=1)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.inp) if l.strip()]
    out = open(a.out, "w")
    counts = {}
    for i, r in enumerate(rows):
        out.write(json.dumps(r) + "\n")
        x = load16k(os.path.join(a.root, r["path"]))
        base = h(r["clip_id"])
        for k in range(a.per_clip):
            env = ENVS[(i * a.per_clip + k) % len(ENVS)]  # exact balance over the manifest
            rng = np.random.default_rng(base + k)
            y = finish(apply_env(x, env, rng, a.noise))
            rel = r["path"].rsplit(".", 1)[0] + f"__{env}.wav"
            sf.write(os.path.join(a.root, rel), y.astype(np.float32), SR, subtype="PCM_16")
            r2 = dict(r, clip_id=r["clip_id"] + "__" + env, path=rel, env=env)
            out.write(json.dumps(r2) + "\n")
            counts[env] = counts.get(env, 0) + 1
        if i % 500 == 0:
            print(f"augment {i}/{len(rows)}", flush=True)
    print("env counts:", counts)


if __name__ == "__main__":
    main()
