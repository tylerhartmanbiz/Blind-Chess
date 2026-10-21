#!/bin/bash
# Download the results tarball a speech-lab run attached to its DRAFT release, then (optionally) delete the draft.
# usage: fetch_results.sh RUN_ID OUTDIR [--delete]
# Needs an authenticated GitHub API (GH_TOKEN, or a proxy that injects credentials).
set -euo pipefail
RUN=$1; OUT=$2; REPO=${REPO:-tylerhartmanbiz/Blind-Chess}
API=https://api.github.com/repos/$REPO
AUTH=(); [ -n "${GH_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")
mkdir -p "$OUT"
REL=$(curl -sf "${AUTH[@]+"${AUTH[@]}"}" "$API/releases?per_page=50" | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    if r['name']=='SpeechLab results $RUN' or r['tag_name']=='speechlab-$RUN':
        print(r['id'], r['assets'][0]['id']); break")
read -r RID AID <<<"$REL"
curl -sfL "${AUTH[@]+"${AUTH[@]}"}" -H "Accept: application/octet-stream" "$API/releases/assets/$AID" -o "$OUT/speechlab-results-$RUN.tgz"
tar xzf "$OUT/speechlab-results-$RUN.tgz" -C "$OUT"
ls -la "$OUT"
if [ "${3:-}" = "--delete" ]; then curl -sf -X DELETE "${AUTH[@]+"${AUTH[@]}"}" "$API/releases/$RID" && echo "deleted draft release $RID"; fi
