#!/usr/bin/env python3
"""Build the 16 kHz mono noise bank used by augment.py.

    make_noise.py --demand DEMANDDIR --models PIPERMODELS --out NOISEDIR

cafe/street/living: real recordings from the DEMAND corpus (CC BY-SA 3.0; PCAFETER, STRAFFIC, DLIVING, channel 1).
babble: 8 overlapping Piper talkers (different speakers) reading unrelated sentences.
tv: one talker + synthetic music bed + living-room noise.
"""
import argparse
import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 16000
SENTENCES = [
    "The weather this weekend looks mostly sunny with a chance of showers on Sunday afternoon.",
    "Could you pass me the sugar, and maybe one of those little spoons as well?",
    "We drove for hours before we finally found a place that was still serving dinner.",
    "Local officials say the new bridge should open to traffic sometime next spring.",
    "I told him the meeting was moved to Thursday, but he still showed up today.",
    "Our team scored twice in the second half and held on for a narrow win.",
    "She has been learning to play the violin since she was about seven years old.",
    "Remember to bring your library books back before the end of the month.",
    "The coffee here is fine, but the pastries are really the reason people come.",
    "After the storm, the whole street was covered in leaves and broken branches.",
    "Tickets for the concert sold out within an hour of going on sale.",
    "He said the train would be late again because of work on the line.",
]


def piper_speech(models, model, sid, sentences, seed):
    from piper import PiperVoice, SynthesisConfig
    v = PiperVoice.load(os.path.join(models, model + ".onnx"))
    rng = np.random.default_rng(seed)
    parts = []
    for s in rng.permutation(sentences):
        chunks = list(v.synthesize(str(s), syn_config=SynthesisConfig(speaker_id=sid)))
        x = np.concatenate([c.audio_float_array for c in chunks]).astype(np.float64)
        sr = chunks[0].sample_rate
        if sr != SR:
            g = np.gcd(sr, SR)
            x = signal.resample_poly(x, SR // g, sr // g)
        parts += [x, np.zeros(int(rng.uniform(0.1, 0.6) * SR))]
    return np.concatenate(parts)


def fit(x, n):
    return np.resize(x, n) if len(x) < n else x[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demand", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    n = 90 * SR
    for name, d in [("cafe", "PCAFETER"), ("street", "STRAFFIC"), ("living", "DLIVING")]:
        x, sr = sf.read(os.path.join(a.demand, d, "ch01.wav"), dtype="float64")
        assert sr == SR
        sf.write(os.path.join(a.out, name + ".wav"), fit(x, n).astype(np.float32), SR)
    talkers = [("en_US-libritts_r-medium", 1), ("en_US-libritts_r-medium", 40), ("en_US-libritts_r-medium", 300),
               ("en_US-libritts_r-medium", 600), ("en_GB-vctk-medium", 3), ("en_GB-vctk-medium", 50),
               ("en_US-arctic-medium", 2), ("en_US-arctic-medium", 7)]
    babble = np.zeros(n)
    for i, (m, sid) in enumerate(talkers):
        s = piper_speech(a.models, m, sid, SENTENCES, i)
        s = np.roll(fit(s, n), int(i * 1.7 * SR))
        babble += s / (np.sqrt(np.mean(s ** 2)) + 1e-9)
    sf.write(os.path.join(a.out, "babble.wav"), (0.05 * babble).astype(np.float32), SR)
    talk = fit(piper_speech(a.models, "en_US-libritts_r-medium", 100, SENTENCES, 99), n)
    t = np.arange(n) / SR
    music = np.zeros(n)
    chords = [[220, 277, 330], [196, 247, 294], [175, 220, 262], [196, 247, 294]]
    for k in range(n // (2 * SR) + 1):
        seg = slice(k * 2 * SR, min(n, (k + 1) * 2 * SR))
        for f in chords[k % 4]:
            music[seg] += np.sin(2 * np.pi * f * t[seg]) * np.exp(-((t[seg] - k * 2) % 0.5) * 3)
    living, _ = sf.read(os.path.join(a.out, "living.wav"), dtype="float64")
    norm = lambda x: x / (np.sqrt(np.mean(x ** 2)) + 1e-9)
    tv = norm(talk) + 0.5 * norm(music) + 0.3 * norm(living)
    sf.write(os.path.join(a.out, "tv.wav"), (0.05 * tv).astype(np.float32), SR)
    print("noise bank:", sorted(os.listdir(a.out)))


if __name__ == "__main__":
    main()
