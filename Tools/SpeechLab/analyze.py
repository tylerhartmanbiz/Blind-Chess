#!/usr/bin/env python3
"""Score SpeechLab recognizer output and build the committed regression corpus.

    analyze.py results.jsonl [more.jsonl ...] --phrases phrases.jsonl --corpus OUT.jsonl --summary OUT.json

Metrics per row (one clip x one recognizer config):
  exact     normalised best transcript == normalised expected text (case, punctuation, number words,
            "e4" vs "E four", "king side" vs "kingside", fillers like "um" are all normalised away)
  sem       a lenient reference parser (below) recovers the intended move/command from the BEST transcript
  sem_nbest the parser recovers it from ANY of the n-best transcripts (what an n-best-aware app could do)
The reference parser is deliberately simple and context-free (no board knowledge) so the numbers measure the
recognizer, not parser cleverness; homophones it accepts are listed in FILE_WORDS / RANK_WORDS / PIECES.
"""
import argparse
import collections
import difflib
import json
import re
import sys

NUM = {"zero": "0", "oh": "0", "one": "1", "won": "1", "two": "2", "three": "3", "four": "4", "five": "5",
       "six": "6", "seven": "7", "eight": "8", "nine": "9", "first": "1", "second": "2", "third": "3",
       "fourth": "4", "fifth": "5", "sixth": "6", "seventh": "7", "eighth": "8"}
FILLERS = {"um", "uh", "hmm", "er", "ah", "erm", "mm", "uhm", "umm"}
FILE_WORDS = {"a": "a", "ay": "a", "hey": "a", "alpha": "a", "b": "b", "be": "b", "bee": "b", "bravo": "b",
              "c": "c", "see": "c", "sea": "c", "charlie": "c", "d": "d", "dee": "d", "delta": "d", "e": "e",
              "echo": "e", "f": "f", "ef": "f", "eff": "f", "foxtrot": "f", "g": "g", "gee": "g", "golf": "g",
              "h": "h", "aitch": "h", "age": "h", "hotel": "h"}
RANK_WORDS = {str(i): str(i) for i in range(1, 9)}
PIECES = {"knight": "N", "knights": "N", "night": "N", "nights": "N", "nite": "N", "bishop": "B", "bishops": "B",
          "rook": "R", "rooks": "R", "rock": "R", "brook": "R", "queen": "Q", "queens": "Q", "king": "K",
          "kings": "K", "pawn": "P", "pawns": "P", "pond": "P", "porn": "P", "prawn": "P"}
COMMANDS = [("new game", "new_game"), ("resign", "resign"), ("repeat", "repeat"), ("undo", "undo"),
            ("take back", "undo"), ("takeback", "undo"), ("read the board", "read_board"),
            ("last move", "last_move"), ("draw", "draw"), ("cancel", "cancel")]


def tokens(text):
    t = text.lower().replace("-", " ").replace("’", "'")
    t = re.sub(r"[^\w\s']", " ", t)
    t = re.sub(r"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])", " ", t)
    out = []
    for w in t.split():
        w = w.strip("'")
        if w in FILLERS or not w:
            continue
        if w.isdigit():
            out.extend(list(w))  # "923" -> 9 2 3 (spoken digits)
            continue
        out.append(NUM.get(w, w))
    s = " ".join(out)
    s = re.sub(r"\bking side\b", "kingside", s)
    s = re.sub(r"\bqueen side\b", "queenside", s)
    s = re.sub(r"\bking's side\b", "kingside", s)
    s = re.sub(r"\bqueen's side\b", "queenside", s)
    return s.split()


def norm(text):
    return " ".join(tokens(text))


def parse(text):
    """-> semantics dict (same schema as phrases.py) or None."""
    tk = tokens(text)
    s = " ".join(tk)
    if not tk:
        return None
    if re.search(r"\b(castle|castles|castling|castled)\b", s):
        side = "Q" if re.search(r"\b(queenside|queen|long)\b", s) else "K"
        return {"kind": "castle", "side": side}
    m = re.search(r"\bwhere (is|are|s) my (\w+)", s)
    if m and m.group(2) in PIECES:
        return {"kind": "query", "command": "where", "piece": PIECES[m.group(2)]}
    if s in ("yes", "yeah", "yep"):
        return {"kind": "command", "command": "yes"}
    if s in ("no", "nope"):
        return {"kind": "command", "command": "no"}
    for phrase, cmd in COMMANDS:
        if re.search(r"\b" + phrase + r"\b", s):
            return {"kind": "command", "command": cmd}
    # squares: file token immediately followed by rank token
    squares, i, lone_files = [], 0, []
    while i < len(tk):
        f = FILE_WORDS.get(tk[i])
        if f and i + 1 < len(tk) and tk[i + 1] in RANK_WORDS:
            squares.append((i, f + tk[i + 1]))
            i += 2
            continue
        if f and tk[i] in "abcdefgh" and len(tk[i]) == 1:
            lone_files.append((i, f))
        i += 1
    if not squares:
        return None
    piece = None
    for w in tk:
        if w in PIECES:
            piece = PIECES[w]
            break
    dest_i, dest = squares[-1]
    promo = None
    after = tk[dest_i + 2:]
    for w in after:
        if w in PIECES and PIECES[w] in "QRBN":
            promo = PIECES[w]
    if promo and piece == promo and not any(w in PIECES for w in tk[:dest_i]):
        piece = None  # "e8 queen": the piece word is the promotion, not the mover
    frm = None
    if len(squares) >= 2:
        frm = squares[-2][1]
    else:
        lf = [f for j, f in lone_files if j < dest_i]
        if lf:
            frm = lf[-1]
    cap = bool(re.search(r"\b(takes|take|captures|capture|x)\b", s))
    is_answer = bool(re.search(r"\b(the )?(1|one|won) on\b", s))
    if is_answer:
        return {"kind": "answer", "square": dest}
    if piece is None and frm is None and promo is None and not cap and len(tk) == 2:
        return {"kind": "square", "square": dest}
    return {"kind": "move", "piece": piece or "P", "from": frm, "to": dest, "capture": cap, "promo": promo}


def sem_match(exp, got):
    if got is None:
        return False
    k = exp["kind"]
    if k in ("square", "answer"):
        sq = exp["square"]
        return got.get("square") == sq or (got.get("kind") == "move" and got.get("to") == sq and got.get("piece") == "P"
                                           and not got.get("from") and not got.get("promo"))
    if k == "move":
        if got.get("kind") == "square":
            got = {"kind": "move", "piece": "P", "from": None, "to": got["square"], "promo": None}
        if got.get("kind") != "move":
            return False
        if got["to"] != exp["to"] or (got.get("promo") or None) != (exp.get("promo") or None):
            return False
        if (got.get("piece") or "P") != exp["piece"]:
            return False
        if exp.get("from") and got.get("from") != exp["from"]:
            # a pawn capture "e takes d5" names the file; a full from-square also identifies it
            if not (got.get("from") and got["from"][0] == exp["from"][0] and len(exp["from"]) == 1):
                return False
        return True
    if k == "castle":
        return got.get("kind") == "castle" and got.get("side") == exp["side"]
    if k == "command":
        return got.get("kind") == "command" and got.get("command") == exp["command"]
    if k == "query":
        return got.get("kind") == "query" and got.get("piece") == exp["piece"]
    return False


def sub_patterns(exp_toks, hyp_toks):
    sm = difflib.SequenceMatcher(a=exp_toks, b=hyp_toks, autojunk=False)
    out = []
    for op, a0, a1, b0, b1 in sm.get_opcodes():
        if op != "equal":
            out.append((" ".join(exp_toks[a0:a1]) or "∅", " ".join(hyp_toks[b0:b1]) or "∅"))
    return out


def wer(exp_toks, hyp_toks):
    sm = difflib.SequenceMatcher(a=exp_toks, b=hyp_toks, autojunk=False)
    errs = sum(max(a1 - a0, b1 - b0) for op, a0, a1, b0, b1 in sm.get_opcodes() if op != "equal")
    return errs, len(exp_toks)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+")
    ap.add_argument("--phrases", required=True)
    ap.add_argument("--corpus")
    ap.add_argument("--summary")
    a = ap.parse_args()
    phrases = {p["phrase_id"]: p for p in map(json.loads, open(a.phrases))}
    rows = []
    for f in a.results:
        for line in open(f):
            if line.strip():
                rows.append(json.loads(line))
    groups = collections.defaultdict(lambda: collections.Counter())
    subs = collections.defaultdict(collections.Counter)
    phrase_conf = collections.defaultdict(collections.Counter)
    lat = collections.defaultdict(list)
    for r in rows:
        p = phrases[r["phrase_id"]]
        exp = p["semantics"]
        cfg = r["config"]
        src = r.get("speaker_source", "?")
        env = r.get("env", "?")
        envc = "clean" if env == "clean" else "augmented"
        keys = [("config", cfg), ("config×source", f"{cfg} | {src}"), ("config×env", f"{cfg} | {env}"),
                ("config×cleanliness", f"{cfg} | {envc}"), ("config×tag", None)]
        if "error" in r:
            for kind, key in keys[:4]:
                groups[(kind, key)]["n"] += 1
                groups[(kind, key)]["error"] += 1
            continue
        best = r.get("best", "")
        nb = r.get("nbest") or [best]
        et, ht = tokens(p["expected_text"]), tokens(best)
        exact = et == ht
        sem = sem_match(exp, parse(best))
        sem_n = sem or any(sem_match(exp, parse(x)) for x in nb)
        e, n = wer(et, ht)
        r["_m"] = (exact, sem, sem_n)
        lat[cfg].append(r.get("latency_ms", 0))
        tagkeys = [("config×tag", f"{cfg} | {t}") for t in p["tags"]]
        for kind, key in keys[:4] + tagkeys:
            g = groups[(kind, key)]
            g["n"] += 1
            g["ok"] += 1
            g["exact"] += exact
            g["sem"] += sem
            g["sem_nbest"] += sem_n
            g["werr"] += e
            g["wn"] += n
        if not sem:
            for pat in sub_patterns(et, ht):
                subs[cfg][pat] += 1
            phrase_conf[cfg][(norm(p["expected_text"]), norm(best))] += 1
    summary = {"rows": len(rows), "groups": {}, "latency": {}, "top_subs": {}, "top_phrase_confusions": {}}
    for (kind, key), g in sorted(groups.items()):
        ok = max(g["ok"], 1)
        summary["groups"].setdefault(kind, {})[key] = {
            "n": g["n"], "errors": g["error"], "exact": round(g["exact"] / ok, 4), "sem": round(g["sem"] / ok, 4),
            "sem_nbest": round(g["sem_nbest"] / ok, 4), "wer": round(g["werr"] / max(g["wn"], 1), 4)}
    for cfg, l in lat.items():
        l = sorted(l)
        summary["latency"][cfg] = {"p50": l[len(l) // 2], "p90": l[int(len(l) * 0.9)], "mean": int(sum(l) / len(l))}
    for cfg, c in subs.items():
        summary["top_subs"][cfg] = [[f"{a_} -> {b_}", n] for (a_, b_), n in c.most_common(40)]
    for cfg, c in phrase_conf.items():
        summary["top_phrase_confusions"][cfg] = [[f"{a_} -> {b_}", n] for (a_, b_), n in c.most_common(40)]
    if a.summary:
        json.dump(summary, open(a.summary, "w"), indent=1)
    if a.corpus:
        with open(a.corpus, "w") as out:
            for r in rows:
                p = phrases[r["phrase_id"]]
                o = {"clip": r["clip_id"], "phrase_id": r["phrase_id"], "expected_text": p["expected_text"],
                     "speaker_source": r.get("speaker_source"), "speaker": r.get("speaker"), "env": r.get("env"),
                     "config": r["config"]}
                if "error" in r:
                    o["error"] = r["error"]
                else:
                    o["best"] = r.get("best", "")
                    nb = [x for x in (r.get("nbest") or []) if x != o["best"]]
                    if nb:
                        o["nbest_alt"] = nb[:4]
                    o["ms"] = r.get("latency_ms")
                    o["sem_ok"] = r["_m"][1]
                out.write(json.dumps(o, ensure_ascii=False, separators=(",", ":")) + "\n")
    # console table
    for kind in ("config", "config×cleanliness"):
        print(f"\n== {kind}")
        for key, v in summary["groups"].get(kind, {}).items():
            print(f"{key:40s} n={v['n']:6d} err={v['errors']:5d} exact={v['exact']:.3f} sem={v['sem']:.3f} "
                  f"sem_nbest={v['sem_nbest']:.3f} wer={v['wer']:.3f}")


if __name__ == "__main__":
    main()
