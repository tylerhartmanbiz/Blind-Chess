#!/usr/bin/env python3
"""Render every phrase with Piper neural TTS speakers (multi-speaker models trained on real human voices).

    make_piper.py --phrases phrases.jsonl --models MODELDIR --out OUTDIR --manifest clean.jsonl

Models (from huggingface.co/rhasspy/piper-voices, MIT code, voices under their dataset licenses):
  libritts_r (904 LibriTTS-R speakers, US), vctk (109 UK/IE/IN/AU/ZA/NZ/CA speakers), arctic (18 CMU speakers),
  l2arctic (24 non-native speakers: Arabic, Mandarin, Hindi, Korean, Spanish, Vietnamese L1).
Speed (length_scale) and expressiveness vary per speaker/phrase deterministically.
"""
import argparse
import hashlib
import json
import os
import wave

import numpy as np
import soundfile as sf
from scipy import signal

# (model, speaker key, label). Speaker keys must exist in the model's speaker_id_map (unknown keys are skipped).
VCTK = [("p248", "F,Indian"), ("p251", "M,Indian"), ("p376", "M,Indian"), ("p234", "F,Scottish"),
        ("p237", "M,Scottish"), ("p245", "M,Irish"), ("p253", "F,Welsh"), ("p314", "F,SouthAfrican"),
        ("p326", "M,Australian"), ("p335", "F,NewZealand"), ("p294", "F,American"), ("p302", "M,Canadian"),
        ("p226", "M,English")]
ARCTIC = [("awb", "M,Scottish"), ("ksp", "M,Indian"), ("slt", "F,US"), ("jmk", "M,Canadian"), ("clb", "F,US")]
L2 = ["ska", "lxc", "txhc", "hkk", "njs", "hqtv", "asi", "ebvs"]  # L2-ARCTIC speaker codes (lowercase match)
LIBRITTS = ["3922", "8699", "922", "1638", "6544", "318", "5400", "176", "28", "6104"]

SR = 16000


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def speakers(models):
    out = []
    for key, label in VCTK:
        out.append(("en_GB-vctk-medium", key, f"vctk:{key}({label})"))
    for key, label in ARCTIC:
        out.append(("en_US-arctic-medium", key, f"arctic:{key}({label})"))
    l2map = json.load(open(os.path.join(models, "en_US-l2arctic-medium.onnx.json"))).get("speaker_id_map", {}) \
        if os.path.exists(os.path.join(models, "en_US-l2arctic-medium.onnx.json")) else {}
    for code in L2:
        match = [k for k in l2map if k.lower() == code or k.lower().startswith(code + "_") or k.lower().endswith("_" + code)]
        if match:
            out.append(("en_US-l2arctic-medium", match[0], f"l2arctic:{match[0]}"))
    for key in LIBRITTS:
        out.append(("en_US-libritts_r-medium", key, f"libritts_r:{key}"))
    for single in ["en_GB-alba-medium", "en_GB-northern_english_male-medium", "en_US-ryan-high"]:
        if os.path.exists(os.path.join(models, single + ".onnx")):
            out.append((single, None, f"single:{single}"))
    return out


def main():
    from piper import PiperVoice, SynthesisConfig
    ap = argparse.ArgumentParser()
    ap.add_argument("--phrases", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--max-speakers", type=int, default=999)
    a = ap.parse_args()
    phrases = [json.loads(l) for l in open(a.phrases) if l.strip()]
    os.makedirs(a.out, exist_ok=True)
    man = open(a.manifest, "w")
    voices = {}
    spk = speakers(a.models)[: a.max_speakers]
    print("piper speakers:", [s[2] for s in spk], flush=True)
    for model, key, label in spk:
        if model not in voices:
            voices[model] = PiperVoice.load(os.path.join(a.models, model + ".onnx"))
        v = voices[model]
        sid = v.config.speaker_id_map.get(key) if key is not None else None
        if key is not None and sid is None:
            print("skip missing speaker", label)
            continue
        safe = label.split("(")[0].replace(":", "_")
        for p in phrases:
            seed = h(label + p["phrase_id"])
            ls = [0.85, 1.0, 1.0, 1.15, 1.3][seed % 5]  # speaking rate variation
            cfg = SynthesisConfig(speaker_id=sid, length_scale=ls, noise_scale=0.667, noise_w_scale=0.8)
            chunks = list(v.synthesize(p["text"], syn_config=cfg))
            x = np.concatenate([c.audio_float_array for c in chunks]).astype(np.float64)
            sr = chunks[0].sample_rate
            if sr != SR:
                g = np.gcd(sr, SR)
                x = signal.resample_poly(x, SR // g, sr // g)
            x = np.concatenate([np.zeros(int(0.3 * SR)), x, np.zeros(int(0.5 * SR))])
            rel = f"piper/{safe}/{p['phrase_id']}.wav"
            os.makedirs(os.path.join(a.out, os.path.dirname(rel)), exist_ok=True)
            sf.write(os.path.join(a.out, rel), (0.9 * x / (np.abs(x).max() + 1e-9)).astype(np.float32), SR, subtype="PCM_16")
            man.write(json.dumps({"clip_id": f"piper:{safe}:{p['phrase_id']}", "path": rel, "phrase_id": p["phrase_id"],
                                  "spoken_text": p["text"], "expected_text": p["expected_text"],
                                  "semantics": p["semantics"], "tags": p["tags"], "speaker_source": "piper",
                                  "speaker": label, "rate": ls, "env": "clean"}) + "\n")
        print("done", label, flush=True)


if __name__ == "__main__":
    main()
