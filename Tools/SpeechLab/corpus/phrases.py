#!/usr/bin/env python3
"""The SpeechLab phrase set: spoken chess utterances + their intended meaning.

`python3 phrases.py > phrases.jsonl` prints one JSON object per phrase:
  {"phrase_id", "text" (what the TTS speaks), "expected_text" (canonical transcript), "semantics", "tags"}
Every square a1..h8 appears at least once; all pieces, captures, castling, promotion, commands,
disambiguation answers and the confusable squares (h8 a8 b3 c3 d3 e3 g3 ...) are covered.
"""
import json
import sys

P = {"knight": "N", "bishop": "B", "rook": "R", "queen": "Q", "king": "K", "pawn": "P"}


def mv(piece, to, frm=None, cap=False, promo=None):
    return {"kind": "move", "piece": piece, "from": frm, "to": to, "capture": cap, "promo": promo}


ROWS = []


def add(pid, text, sem, tags, expected=None):
    ROWS.append({"phrase_id": pid, "text": text, "expected_text": expected or text.replace("...", "").replace(",", ""),
                 "semantics": sem, "tags": tags})


# --- bare pawn moves / squares -------------------------------------------------------------
for sq in ["e4", "d4", "c4", "f4", "e5", "d5", "c5", "g6", "b6", "a6", "h6", "f5"]:
    add(f"pawn_{sq}", sq, mv("P", sq), ["pawn", "square"])
# confusable squares said on their own (as a destination / disambiguation answer)
for sq in ["h8", "a8", "b3", "c3", "d3", "e3", "g3", "b8", "e8", "d8", "a1", "h1", "g2", "b2"]:
    add(f"sq_{sq}", sq, {"kind": "square", "square": sq}, ["square", "confusable"])

# --- piece moves ---------------------------------------------------------------------------
pieces_moves = [
    ("knight", "f3", "to"), ("knight", "c3", ""), ("knight", "f6", "to"), ("knight", "c6", ""),
    ("knight", "e2", "to"), ("knight", "d7", "to"), ("knight", "g5", ""), ("knight", "h4", "to"),
    ("bishop", "c4", "to"), ("bishop", "b5", ""), ("bishop", "g7", "to"), ("bishop", "e7", "to"),
    ("bishop", "a3", "to"), ("bishop", "h3", ""), ("bishop", "f1", "to"),
    ("rook", "e1", "to"), ("rook", "d1", ""), ("rook", "c8", "to"), ("rook", "f8", "to"),
    ("rook", "a7", "to"), ("rook", "h7", ""), ("rook", "a2", "to"),
    ("queen", "h5", "to"), ("queen", "d2", ""), ("queen", "a4", "to"), ("queen", "b7", "to"),
    ("queen", "g4", "to"), ("queen", "e6", ""), ("queen", "c7", "to"),
    ("king", "g8", "to"), ("king", "f2", ""), ("king", "h2", "to"), ("king", "e7", "to"), ("king", "c1", "to"),
    ("pawn", "a5", "to"), ("pawn", "h5", "to"), ("pawn", "f7", "to"), ("pawn", "c2", "to"),
]
for piece, sq, prep in pieces_moves:
    text = f"{piece} {prep} {sq}".replace("  ", " ")
    add(f"{piece}_{prep or 'x'}_{sq}", text, mv(P[piece], sq), ["piece", piece, "to" if prep else "noprep"])

# --- captures ------------------------------------------------------------------------------
for text, sem in [
    ("knight takes e5", mv("N", "e5", cap=True)),
    ("bishop takes f7", mv("B", "f7", cap=True)),
    ("queen takes d8", mv("Q", "d8", cap=True)),
    ("rook takes a8", mv("R", "a8", cap=True)),
    ("king takes g1", mv("K", "g1", cap=True)),
    ("e takes d5", mv("P", "d5", frm="e", cap=True)),
    ("pawn takes b4", mv("P", "b4", cap=True)),
    ("bishop captures h6", mv("B", "h6", cap=True)),
    ("g takes h3", mv("P", "h3", frm="g", cap=True)),
    ("c takes d6", mv("P", "d6", frm="c", cap=True)),
]:
    add("cap_" + text.replace(" ", "_"), text, sem, ["capture"])

# --- castling ------------------------------------------------------------------------------
for text, side in [("castle kingside", "K"), ("castle queenside", "Q"), ("castles", "K"), ("short castle", "K"),
                   ("long castle", "Q"), ("castle short", "K"), ("castle long", "Q")]:
    add("castle_" + text.replace(" ", "_"), text, {"kind": "castle", "side": side}, ["castle"])

# --- promotion -----------------------------------------------------------------------------
for text, sem in [
    ("e8 queen", mv("P", "e8", promo="Q")),
    ("pawn to a8 promote to queen", mv("P", "a8", promo="Q")),
    ("b1 knight", mv("P", "b1", promo="N")),
    ("h8 promote to rook", mv("P", "h8", promo="R")),
    ("g1 equals queen", mv("P", "g1", promo="Q")),
    ("d takes c8 queen", mv("P", "c8", frm="d", cap=True, promo="Q")),
]:
    add("promo_" + text.replace(" ", "_"), text, sem, ["promotion"])

# --- disambiguation ------------------------------------------------------------------------
for text, sem in [
    ("knight b d2", mv("N", "d2", frm="b")),
    ("knight from b1 to d2", mv("N", "d2", frm="b1")),
    ("rook a d1", mv("R", "d1", frm="a")),
    ("rook f1 to e1", mv("R", "e1", frm="f1")),
    ("knight g to e4", mv("N", "e4", frm="g")),
]:
    add("dis_" + text.replace(" ", "_"), text, sem, ["disambiguation"])
for sq in ["b1", "f3", "h8", "a8", "d3", "g1"]:
    add(f"answer_{sq}", f"the one on {sq}", {"kind": "answer", "square": sq}, ["answer"])

# --- commands ------------------------------------------------------------------------------
for text, cmd in [("new game", "new_game"), ("resign", "resign"), ("repeat", "repeat"), ("undo", "undo"),
                  ("take back", "undo"), ("read the board", "read_board"), ("what was the last move", "last_move"),
                  ("offer a draw", "draw"), ("yes", "yes"), ("no", "no"), ("cancel", "cancel")]:
    add("cmd_" + cmd + ("_2" if text == "take back" else ""), text, {"kind": "command", "command": cmd}, ["command"])
for text, piece in [("where is my queen", "Q"), ("where is my king", "K"), ("where are my knights", "N"),
                    ("where are my rooks", "R")]:
    add("where_" + piece, text, {"kind": "query", "command": "where", "piece": piece}, ["command", "query"])

# --- hesitations / filler (TTS speaks the filler; expected transcript ignores it) ----------
for text, exp, sem in [
    ("um, knight to... f3", "knight to f3", mv("N", "f3")),
    ("uh, bishop to c4", "bishop to c4", mv("B", "c4")),
    ("hmm, let me see, queen takes h7", "queen takes h7", mv("Q", "h7", cap=True)),
    ("okay, e4", "e4", mv("P", "e4")),
    ("knight, uh, to g3", "knight to g3", mv("N", "g3")),
]:
    add("hes_" + exp.replace(" ", "_"), text, sem, ["hesitation"], expected=exp)

# --- NATO-alphabet squares (candidate fallback for confusable letters) -----------------------
for text, sq in [("hotel eight", "h8"), ("alpha eight", "a8"), ("bravo three", "b3"), ("delta three", "d3"),
                 ("knight to foxtrot three", "f3"), ("echo four", "e4")]:
    sem = mv("N", sq) if text.startswith("knight") else {"kind": "square", "square": sq}
    add("nato_" + sq + ("_n" if text.startswith("knight") else ""), text, sem, ["nato"])

# --- make sure every square is covered --------------------------------------------------------
covered = set()
for r in ROWS:
    s = r["semantics"]
    for k in ("to", "square"):
        if s.get(k):
            covered.add(s[k])
    if s.get("from") and len(s["from"]) == 2:
        covered.add(s["from"])
missing = [f + str(r) for f in "abcdefgh" for r in range(1, 9) if f + str(r) not in covered]
for i, sq in enumerate(missing):
    piece = ["rook", "queen", "bishop", "knight"][i % 4]
    add(f"cover_{piece}_{sq}", f"{piece} to {sq}", mv(P[piece], sq), ["piece", piece, "to", "coverage"])

if __name__ == "__main__":
    ids = [r["phrase_id"] for r in ROWS]
    assert len(ids) == len(set(ids)), "duplicate phrase ids"
    for r in ROWS:
        sys.stdout.write(json.dumps(r) + "\n")
    print(f"{len(ROWS)} phrases, filled {len(missing)} coverage squares: {missing}", file=sys.stderr)
