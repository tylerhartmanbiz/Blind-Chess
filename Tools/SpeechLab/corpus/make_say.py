#!/usr/bin/env python3
"""Render phrases with every English macOS `say` voice (macOS only).

    make_say.py --phrases phrases.jsonl --out OUTDIR --manifest clean.jsonl [--shard K --shards N]

Voices: all en_* voices from `say -v '?'` except novelty voices. Rate varies per (voice, phrase):
150 / 175 / 200 / 230 words per minute. Output: 16 kHz mono 16-bit WAV with 0.3 s lead-in / 0.5 s tail.
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess

NOVELTY = {"Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Good News", "Jester", "Organ",
           "Superstar", "Trinoids", "Whisper", "Wobble", "Zarvox", "Fred", "Junior", "Ralph", "Kathy"}


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def voices():
    out = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    vs = []
    for line in out.splitlines():
        m = re.match(r"^(.*?)\s+(en_[A-Z]{2,3})\s+#", line)
        if m and m.group(1).split(" (")[0] not in NOVELTY:
            vs.append((m.group(1).strip(), m.group(2)))
    return vs


def render(job):
    voice, locale, p, out, rel, rate = job
    text = p["text"].replace("...", ", ")
    tmp = os.path.join(out, rel + ".raw.wav")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    cmd = ["say", "-v", voice, "-r", str(rate), "-o", tmp, "--data-format=LEI16@16000", f"[[slnc 300]] {text} [[slnc 500]]"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(tmp):
        return None
    os.replace(tmp, os.path.join(out, rel))
    return rel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phrases", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--shard", type=int, default=0)
    ap.add_argument("--shards", type=int, default=1)
    a = ap.parse_args()
    phrases = [json.loads(l) for l in open(a.phrases) if l.strip()]
    vs = voices()
    print(f"{len(vs)} English voices:", [v for v, _ in vs], flush=True)
    mine = [v for i, v in enumerate(vs) if i % a.shards == a.shard]
    jobs = []
    for voice, locale in mine:
        safe = re.sub(r"[^A-Za-z0-9]+", "_", voice).strip("_")
        for p in phrases:
            rate = [150, 175, 200, 230][h(voice + p["phrase_id"]) % 4]
            jobs.append((voice, locale, p, a.out, f"say/{safe}/{p['phrase_id']}.wav", rate))
    man = open(a.manifest, "w")
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 3) as ex:
        for job, rel in zip(jobs, ex.map(render, jobs)):
            voice, locale, p, _, _, rate = job
            if not rel:
                print("say failed", voice, p["phrase_id"])
                continue
            safe = rel.split("/")[1]
            man.write(json.dumps({"clip_id": f"say:{safe}:{p['phrase_id']}", "path": rel, "phrase_id": p["phrase_id"],
                                  "spoken_text": p["text"], "expected_text": p["expected_text"],
                                  "semantics": p["semantics"], "tags": p["tags"], "speaker_source": "macos_say",
                                  "speaker": f"{voice} [{locale}]", "rate": rate, "env": "clean"}) + "\n")
    print(f"shard {a.shard}: {len(mine)} voices, {len(jobs)} clips", flush=True)


if __name__ == "__main__":
    main()
