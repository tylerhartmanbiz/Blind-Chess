#!/usr/bin/env python3
"""Real-human square names ("h" + "eight") spliced from openly licensed recordings.

    make_human.py --phrases phrases.jsonl --an4 AN4DIR [--fsdd FSDDDIR] [--sc SCDIR] --out OUTDIR --manifest clean.jsonl

Sources (downloaded by the workflow, never committed):
  * CMU AN4 alphanumeric database (CMU, free for use): ~74 speakers spelling words letter-by-letter and reading
    digit strings. Utterances are split at pauses into single letters / digits (kept only when the number of
    speech islands equals the number of transcript tokens), so letter and digit come from the SAME speaker.
  * Free Spoken Digit Dataset (CC BY-SA 4.0) and Google Speech Commands v0.02 (CC BY 4.0): extra digit voices
    combined with AN4 letters ("human_mixed": letter and number from two different people).
Only phrases that are bare squares (e.g. "h8", "e4") can be built this way.
"""
import argparse
import glob
import hashlib
import json
import os
import random
import re

import numpy as np
import soundfile as sf
from scipy import signal

SR = 16000
DIGITS = {"ONE": "1", "TWO": "2", "THREE": "3", "FOUR": "4", "FIVE": "5", "SIX": "6", "SEVEN": "7", "EIGHT": "8"}
DIGIT_WORDS_ALL = set(DIGITS) | {"NINE", "ZERO", "OH"}
WORD = {v: k.lower() for k, v in DIGITS.items()}


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def islands(x, merge_ms, rel_db=32.0):
    n = 160  # 10 ms frames
    f = x[: len(x) // n * n].reshape(-1, n)
    e = 10 * np.log10((f ** 2).mean(axis=1) + 1e-10)
    floor = np.percentile(e, 10)
    thr = max(floor + 9.0, e.max() - rel_db)
    on = e > thr
    regs = []
    i = 0
    while i < len(on):
        if on[i]:
            j = i
            while j < len(on) and on[j]:
                j += 1
            regs.append([i, j])
            i = j
        else:
            i += 1
    merged = []
    for r in regs:
        if merged and r[0] - merged[-1][1] < merge_ms // 10:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    merged = [r for r in merged if r[1] - r[0] >= 6]  # >= 60 ms
    return [(max(0, a * n - 480), min(len(x), b * n + 480)) for a, b in merged]


def frame_db(x, n=160):
    f = x[: len(x) // n * n].reshape(-1, n)
    e = 10 * np.log10((f ** 2).mean(axis=1) + 1e-10)
    return np.convolve(e, np.ones(3) / 3, mode="same")


def split_utterance(x, ntok, min_depth=8.0):
    """Cut an utterance of ntok spelled letters / digits into ntok pieces.

    Start from pause-separated islands; if there are too many, merge across the shortest pauses; if there are
    too few, split inside islands at energy valleys at least `min_depth` dB below both neighbouring peaks.
    Returns None unless every cut is backed by a clear pause or valley (so labels stay trustworthy)."""
    for merge in (120, 90, 160):
        segs = islands(x, merge)
        if len(segs) == ntok:
            return segs
    segs = [list(s) for s in islands(x, 60)]
    if not segs:
        return None
    while len(segs) > ntok:
        gaps = [(segs[i + 1][0] - segs[i][1], i) for i in range(len(segs) - 1)]
        g, i = min(gaps)
        if g > 0.3 * SR:
            return None
        segs[i][1] = segs[i + 1][1]
        del segs[i + 1]
    e = frame_db(x)
    cands = []  # (depth, sample index)
    for a, b in segs:
        fa, fb = a // 160, b // 160
        for k in range(fa + 8, fb - 8):
            if e[k] <= e[k - 1] and e[k] <= e[k + 1]:
                left, right = e[max(fa, k - 40):k].max(), e[k + 1:min(fb, k + 41)].max()
                depth = min(left, right) - e[k]
                if depth >= min_depth:
                    cands.append((depth, k * 160 + 80))
    need = ntok - len(segs)
    if len(cands) < need:
        return None
    cuts = sorted(c for _, c in sorted(cands, reverse=True)[:need])
    out = []
    for a, b in segs:
        inner = [c for c in cuts if a < c < b]
        pts = [a] + inner + [b]
        out += [(pts[j], pts[j + 1]) for j in range(len(pts) - 1)]
    if any(b - a < 0.1 * SR or b - a > 1.2 * SR for a, b in out):
        return None
    return out


def load(path, raw=False):
    if raw:
        x = np.fromfile(path, dtype=">i2").astype(np.float64) / 32768.0
        return x
    x, sr = sf.read(path, dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        x = signal.resample_poly(x, SR // g, sr // g)
    return x


def load_an4(path):
    if path.endswith(".raw"):
        return load(path, raw=True)
    with open(path, "rb") as fh:  # NIST SPHERE: ASCII header (size on line 2), then PCM
        head = fh.read(1024).decode("latin-1")
        size = int(head.split("\n")[1].strip())
        fh.seek(0)
        hdr = fh.read(size).decode("latin-1")
        data = fh.read()
    big = "sample_byte_format -s2 10" in hdr
    return np.frombuffer(data, dtype=">i2" if big else "<i2").astype(np.float64) / 32768.0


def norm(x, peak=0.8):
    return x * (peak / (np.abs(x).max() + 1e-9))


def an4_units(an4):
    """-> {speaker: {"letters": {L: [audio]}, "digits": {D: [audio]}}}"""
    units = {}
    stats = {"utts": 0, "used": 0}
    files = glob.glob(os.path.join(an4, "wav", "*", "*", "*.raw")) + glob.glob(os.path.join(an4, "wav", "*", "*", "*.sph"))
    index = {frozenset(os.path.basename(f)[:-4].split("-")): f for f in files}
    print("AN4 raw files:", len(index), flush=True)
    for tf, sub in [("etc/an4_train.transcription", "an4_clstk"), ("etc/an4_test.transcription", "an4test_clstk")]:
        p = os.path.join(an4, tf)
        if not os.path.exists(p):
            continue
        for line in open(p):
            m = re.match(r"<s>(.*)</s>\s*\((\S+)\)", line.strip())
            if not m:
                continue
            toks, uid = m.group(1).split(), m.group(2)
            if not toks or not all(len(t) == 1 and t.isalpha() or t in DIGIT_WORDS_ALL for t in toks):
                continue
            f = index.get(frozenset(uid.split("-")))
            if not f:
                continue
            spk_dir = os.path.basename(os.path.dirname(f))
            stats["utts"] += 1
            x = load_an4(f)
            segs = split_utterance(x, len(toks))
            if not segs:
                continue
            stats["used"] += 1
            u = units.setdefault(spk_dir, {"letters": {}, "digits": {}})
            for t, (a, b) in zip(toks, segs):
                seg = x[a:b]
                if t in DIGITS:
                    u["digits"].setdefault(DIGITS[t], []).append(seg)
                elif len(t) == 1 and t.lower() in "abcdefgh":
                    u["letters"].setdefault(t.lower(), []).append(seg)
    print("AN4:", stats, "speakers:", len(units), flush=True)
    return units


def other_digits(fsdd, sc):
    """-> list of (speaker, {D: [audio]})"""
    out = {}
    if fsdd:
        for f in glob.glob(os.path.join(fsdd, "recordings", "*.wav")):
            d, spk, _ = os.path.basename(f)[:-4].split("_")
            if d in WORD:
                out.setdefault("fsdd:" + spk, {}).setdefault(d, []).append(f)
    if sc:
        for d, w in WORD.items():
            for f in sorted(glob.glob(os.path.join(sc, w, "*.wav")))[:4000]:
                spk = os.path.basename(f).split("_")[0]
                out.setdefault("sc:" + spk, {}).setdefault(d, []).append(f)
    # keep speakers who said all eight digits
    full = {k: v for k, v in out.items() if len(v) == 8}
    print("other digit speakers with all 8 digits:", len(full), flush=True)
    return full


def trim(x):
    segs = islands(x, 250)
    if not segs:
        return x
    return x[segs[0][0]: segs[-1][1]]


def splice(letter, digit, gap_s):
    a, b = norm(trim(letter)), norm(trim(digit), 0.8 * random.uniform(0.8, 1.1))
    return np.concatenate([np.zeros(int(0.3 * SR)), a, np.zeros(int(gap_s * SR)), b, np.zeros(int(0.5 * SR))])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phrases", required=True)
    ap.add_argument("--an4", required=True)
    ap.add_argument("--fsdd")
    ap.add_argument("--sc")
    ap.add_argument("--out", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--max-same", type=int, default=24, help="max AN4 same-speaker voices")
    ap.add_argument("--max-mixed", type=int, default=12, help="max mixed letter/digit voices")
    a = ap.parse_args()
    random.seed(7)
    phrases = [json.loads(l) for l in open(a.phrases) if l.strip()]
    sq_phrases = [p for p in phrases if re.fullmatch(r"[a-h][1-8]", p["text"])]
    units = an4_units(a.an4)
    man = open(a.manifest, "w")
    n = 0
    # same-speaker squares: rank speakers by how many of the square phrases they can build
    def can(u, sq):
        return sq[0] in u["letters"] and sq[1] in u["digits"]
    ranked = sorted(units.items(), key=lambda kv: -sum(can(kv[1], p["text"]) for p in sq_phrases))
    same = [(s, u) for s, u in ranked if sum(can(u, p["text"]) for p in sq_phrases) >= 4][: a.max_same]
    for spk, u in same:
        for p in sq_phrases:
            sq = p["text"]
            if not can(u, sq):
                continue
            rnd = random.Random(h(spk + sq))
            x = splice(rnd.choice(u["letters"][sq[0]]), rnd.choice(u["digits"][sq[1]]), rnd.uniform(0.04, 0.2))
            rel = f"human/an4_{spk}/{p['phrase_id']}.wav"
            os.makedirs(os.path.join(a.out, os.path.dirname(rel)), exist_ok=True)
            sf.write(os.path.join(a.out, rel), x.astype(np.float32), SR, subtype="PCM_16")
            man.write(json.dumps({"clip_id": f"human:an4_{spk}:{p['phrase_id']}", "path": rel, "phrase_id": p["phrase_id"],
                                  "spoken_text": p["text"], "expected_text": p["expected_text"], "semantics": p["semantics"],
                                  "tags": p["tags"], "speaker_source": "human_an4", "speaker": f"an4:{spk}",
                                  "env": "clean"}) + "\n")
            n += 1
    print("same-speaker clips:", n, "speakers:", len(same), flush=True)
    # mixed: AN4 letters (pooled over all speakers) + FSDD / Speech Commands digit speakers
    pool = {}
    for u in units.values():
        for L, segs in u["letters"].items():
            pool.setdefault(L, []).extend(segs)
    others = other_digits(a.fsdd, a.sc)
    keys = sorted(k for k in others if k.startswith("fsdd:")) + \
        sorted((k for k in others if k.startswith("sc:")), key=h)
    m = 0
    for spk in keys[: a.max_mixed]:
        for p in sq_phrases:
            sq = p["text"]
            if sq[0] not in pool:
                continue
            rnd = random.Random(h(spk + sq))
            x = splice(rnd.choice(pool[sq[0]]), load(rnd.choice(others[spk][sq[1]])), rnd.uniform(0.04, 0.2))
            safe = spk.replace(":", "_")
            rel = f"human/mixed_{safe}/{p['phrase_id']}.wav"
            os.makedirs(os.path.join(a.out, os.path.dirname(rel)), exist_ok=True)
            sf.write(os.path.join(a.out, rel), x.astype(np.float32), SR, subtype="PCM_16")
            man.write(json.dumps({"clip_id": f"human:mixed_{safe}:{p['phrase_id']}", "path": rel, "phrase_id": p["phrase_id"],
                                  "spoken_text": p["text"], "expected_text": p["expected_text"], "semantics": p["semantics"],
                                  "tags": p["tags"], "speaker_source": "human_mixed", "speaker": f"an4-letters+{spk}",
                                  "env": "clean"}) + "\n")
            m += 1
    print("mixed clips:", m, flush=True)


if __name__ == "__main__":
    main()
