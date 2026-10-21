#!/usr/bin/env python3
"""shard.py --shard K --shards N linux_manifest.jsonl say_manifest.jsonl > shard.jsonl

Linux clips are split by (clean clip index) % N, keeping each clean clip with its augmented copy; the say
manifest is already per-shard. Output is shuffled deterministically so a time-budgeted run is a random sample.
"""
import argparse, json, random

ap = argparse.ArgumentParser()
ap.add_argument("--shard", type=int, required=True)
ap.add_argument("--shards", type=int, required=True)
ap.add_argument("linux")
ap.add_argument("say")
a = ap.parse_args()
groups = {}
for f in (a.linux, a.say):
    for line in open(f):
        if line.strip():
            r = json.loads(line)
            groups.setdefault((f, r["clip_id"].split("__")[0]), []).append(line.strip())
keys = sorted(groups)
mine = [k for i, k in enumerate(keys) if k[0] == a.say or i % a.shards == a.shard]
random.Random(1000 + a.shard).shuffle(mine)
for k in mine:
    for line in groups[k]:
        print(line)
