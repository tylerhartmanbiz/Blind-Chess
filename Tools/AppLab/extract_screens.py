#!/usr/bin/env python3
"""Decode screenshots printed by print_screens.sh from a GitHub Actions job log.
Usage: python3 -I Tools/AppLab/extract_screens.py job.log outdir"""
import base64, os, re, sys

log, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
text = open(log, encoding="utf-8", errors="replace").read().replace("\\n", "\n")
ts = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")
name, buf = None, []
for raw in text.splitlines():
    line = ts.sub("", raw).strip()
    if line.startswith("=====APPLAB_JPEG_BEGIN"):
        name, buf = line.split()[1].rstrip("="), []
    elif line.startswith("=====APPLAB_JPEG_END") and name:
        path = os.path.join(outdir, os.path.basename(name) + ".jpg")
        with open(path, "wb") as f:
            f.write(base64.b64decode("".join(buf)))
        print(path)
        name = None
    elif name:
        buf.append(line)
