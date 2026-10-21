# SpeechLab report: Apple speech recognition on spoken chess moves

Run `39548302921` (2026-10-21), macOS 26.6.2 on GitHub `macos-26` (Apple M1 virtual), Xcode 26.6.
**4,304 clips × 8 recognizer configs = 28,716 real recognizer results** (3 of the 4 shards finished; each shard
processed a random sample within a 55 min budget). Every transcript comes from an actual Apple recognizer run;
they are committed in [`Tests/SpeechCorpus/transcripts.jsonl`](../../Tests/SpeechCorpus/transcripts.jsonl).

Corpus: 124 phrases (all 64 squares, all pieces, captures, castling, promotion, disambiguation, answers like
"the one on b1", commands, "where is my queen", hesitations, NATO squares) spoken by
* 39 Piper neural voices (VCTK UK/IE/Scottish/Welsh/Indian/AU/NZ/ZA/CA, CMU Arctic, L2-ARCTIC non-native
  speakers, LibriTTS-R) — 2,432 clips;
* 18 of the 24 non-novelty macOS `say` English voices (en_US/GB/AU/IE/IN/ZA, incl. Eloquence voices; the other 6 were
  in the cancelled shard), 150–230 wpm — 1,528;
* real humans: 24 CMU AN4 speakers (letter + digit from the same person, cut at pauses) — 188, and AN4 letters +
  digits from 12 FSDD / Google Speech Commands speakers — 156 (bare squares only).
Half the clips are clean, half carry one of 18 environments (café/street/living-room noise from DEMAND,
8-talker babble, TV, white/fan noise at 20/10/5 dB SNR, room/hall reverb, phone band, -15 dB quiet, far-field,
1.35× fast, 0.75× slow).

**Metrics.** *exact*: normalised transcript equals the expected text. *semantic*: a deliberately simple,
context-free reference parser (`analyze.py`) recovers the intended move/command. *n-best*: any of the top-5
alternatives parses correctly. No board knowledge is used, so these are lower bounds for an app that filters by
legal moves.

## Accuracy by recognizer config

| config | clips | exact | semantic (best) | semantic (any of n-best) | WER | p50 / p90 ms |
|---|---|---|---|---|---|---|
| `server` (app today) | 1436 | 22% | 31% | 39% | 0.56 | 483 / 801 |
| `server_ctx` | 1436 | 24% | 32% | 40% | 0.53 | 436 / 823 |
| `ondevice` | 4304 | 21% | 29% | 36% | 0.57 | 146 / 307 |
| `ondevice_ctx` | 4304 | 32% | 39% | 47% | 0.48 | 162 / 369 |
| **`ondevice_lm`** | 4304 | **38%** | **43%** | 50% | **0.43** | 176 / 425 |
| `dict` (DictationTranscriber) | 4304 | 21% | 29% | 36% | 0.57 | 224 / 398 |
| `dict_ctx` | 4304 | 32% | 39% | 47% | 0.47 | 467 / 691 |
| `dict_lm` | 4304 | 37% | 43% | **51%** | 0.43 | 502 / 783 |

Server rows: one third of clips; 5–6% of server requests failed (`kAFAssistantErrorDomain`, mostly on noisy
clips). Latency is per file (whole clip), not streaming. `SpeechTranscriber` (`st`) is unavailable on the runner
(`isAvailable=false`, "not subscribed to transcription.en", "Audio format is not supported") — needs Apple
Intelligence-class hardware; not measured. `DictationTranscriber` gives the same words as on-device
`SFSpeechRecognizer` (same engine) but is ~2× slower per file.

## By voice source (semantic, best transcript)

| config | piper | macos_say | human_mixed | human_an4 |
|---|---|---|---|---|
| `server` | 34% | 29% | 10% | 16% |
| `ondevice` | 32% | 27% | 21% | 19% |
| `ondevice_ctx` | 43% | 36% | 28% | 25% |
| `ondevice_lm` | 47% | 41% | 34% | 28% |
| `dict_lm` | 47% | 41% | 35% | 27% |

Human spliced squares are hardest (isolated "h", "eight" with a splice gap, 8 kHz/telephone-era recordings), but
the ranking of configs is the same for every source.

## By environment (semantic)

| env | n | ondevice | ondevice_ctx | ondevice_lm | dict_lm |
|---|---|---|---|---|---|
| clean | 2153 | 36% | 46% | 51% | 51% |
| quiet -15 dB | 119 | 38% | 48% | 53% | 53% |
| slow 0.75× | 107 | 34% | 41% | 47% | 46% |
| fan 10 dB | 116 | 29% | 46% | 47% | 49% |
| white 20 dB | 121 | 33% | 45% | 48% | 49% |
| street 10 / 5 dB | 126 / 112 | 29% / 29% | 40% / 37% | 40% / 47% | 38% / 48% |
| living room 10 dB | 113 | 29% | 41% | 43% | 45% |
| phone band | 117 | 21% | 37% | 41% | 42% |
| TV 10 dB | 120 | 20% | 32% | 37% | 37% |
| café 10 / 5 dB | 108 / 127 | 21% / 17% | 29% / 27% | 33% / 31% | 36% / 31% |
| babble 10 dB | 124 | 20% | 31% | 33% | 35% |
| fast 1.35× | 132 | 23% | 33% | 35% | 36% |
| room reverb | 127 | 19% | 27% | 34% | 33% |
| far field | 121 | 19% | 26% | 32% | 31% |
| white 10 dB | 122 | 16% | 20% | 25% | 25% |
| babble 5 dB | 114 | 1% | 6% | 10% | 11% |
| hall reverb (RT60 1.1 s) | 125 | 4% | 8% | 12% | 14% |

Quiet speech is fine (gain is normalised); competing speech (babble/TV/café) and reverberation are what break it.

## By phrase type (semantic; last column = any of n-best with the custom LM)

| type | n | ondevice | ondevice_ctx | ondevice_lm | lm + n-best |
|---|---|---|---|---|---|
| bare pawn move ("e4") | 687 | 36% | 49% | 51% | 59% |
| confusable squares (h8 a8 b3 c3 d3 e3 g3 …) | 670 | 26% | 39% | 44% | 53% |
| knight / bishop / queen / king moves | 246/240/220/172 | 18/26/20/12% | 34/42/33/27% | 35/46/48/30% | 41/50/57/33% |
| rook moves | 200 | 2% | 4% | 4% | 6% |
| captures | 344 | 10% | 14% | 16% | 21% |
| castling | 218 | 46% | 52% | 65% | 68% |
| promotion | 175 | 8% | 21% | 27% | 37% |
| disambiguation ("knight b d2") | 136 | 7% | 24% | 10% | 15% |
| answers ("the one on b1") | 152 | 34% | 41% | 53% | 61% |
| commands / queries | 478 / 102 | 64% / 52% | 65% / 54% | 73% / 67% | 76% / 69% |
| NATO squares ("hotel eight") | 184 | 46% | 47% | 45% | 59% |

## Top confusions (on-device, counts over all voices/envs)

* **Rook is almost never heard as "rook"**: "Route to F8", "Route one", "RT one", "Rookie one", "work",
  "What do you want", "Look at D1", "Rugby one", "Rotate seven".
* **Letters dropped or turned into words**: "e4" → "Before"/"Default"/"OK"/"Eat"; "b2" → "Me too"; "b4" →
  "before"; "e3" → "Hey Siri"/"History"; "e8" → "He ate"; "a8" → "Hey"/"AA"/"Eight"/""; "h1" → "Each one";
  "d4" → "Default"; "f5" → "at 5"; "b6" → "V6"; "c" → "see"/"she"; "e" → "he"; "d" → "the".
* **h8 / a8** (the reported bug): "h8" → "Eight", "Hey", "HA", "88", "HE", "Itchy" (clean clips: 2/24 correct on-device
  without hints, 7/24 with contextual strings); "a" ↔ "e" ↔ "8" swaps are the most common substitution with
  the custom LM ("a6" → "e6", "h1" → "a1"/"e1").
* **knight + file letter merges into a number**: "knight c6" → "96", "knight g5" → "95", "knight to f3" → "923"
  (without hints; with contextual strings → "Knight to f3").
* **"to" vs "two"**: "Knight two f3" appears as the 2nd alternative; "queen to" → "quinta".
* Castling: "castle long" → "Cancel alarm" (assistant-command bias), "king side" vs "kingside".
* Captures: "e takes d5" → "He takes d5"; "c takes d6" → "She takes d6".
* Server and `ondevice` make the same kinds of errors; the server adds no accuracy.

## Recommendations for the app

1. **Use on-device recognition with contextual strings, plus the custom language model**
   (`requiresOnDeviceRecognition = true`, `contextualStrings`, `customizedLanguageModel`). It is the most accurate
   config: semantic accuracy 29% → 43% (+48% relative), exact transcripts 21% → 38%, at p50 176 ms per utterance. It
   is also offline, has no server quota, and avoids the ~5% server failures. If the custom LM is not used,
   `contextualStrings` alone gets 39%. On iOS 26 `DictationTranscriber` with the same `AnalysisContext` strings
   and `.customizedLanguage` gives the same accuracy but is ~2.5× slower per file; keep `SFSpeechRecognizer` unless
   SpeechAnalyzer streaming is needed.
2. **Contextual strings** (≤100; the list measured here, `recognizer/main.swift`): `knight, bishop, rook, queen,
   king, pawn, takes, captures, castle, castles, kingside, queenside, promote, check, checkmate, resign,
   new game, repeat, undo, where is my, the one on` and all 64 squares written `a1`…`h8`.
3. **Custom LM** (`recognizer/LM.swift`): weighted phrases `<square>`, `<piece> <square>`, `<piece> to <square>`,
   `<piece> takes <square>`, `pawn to <square>`, `<file> takes <square>`, `<square> <promo>`,
   `<square> promote to <promo>`, `the one on <square>`, castling and command phrases. Build it once at first
   launch (`SFCustomLanguageModelData.export` + `prepareCustomLanguageModel`) and cache it.
4. **Always use the n-best list** (`result.transcriptions`, top 5): it adds 7–10 points everywhere (43% → 50%).
   Resolve each alternative against the legal moves of the current position and take the first that is legal and
   unique; ask only when several alternatives are legal and different.
5. **Parser hardening** (all seen in the corpus): accept "route/root/rude/rookie/RT/work/look" as rook only when
   followed by a square; map "he/hey/eh" → e, "she/see/sea" → c, "the/dee" → d, "bee/me" → b (before a digit),
   "each/age/itch/aitch" → h, "at/ef" → f, "V" → b; split fused tokens ("HA", "AA", "88", "E4", "96" after
   knight, "923" = "knight to f3"); never treat "to/too/for" as ranks when a square follows; recognise
   "before" = b4/e4 and "default" = d4 only via the legal-move filter.
6. **Never act on partial results**; act on `isFinal` (or ~1.2–1.5 s of silence after the last change; not
   measured here). Whole-utterance on-device recognition took p50 176 ms / p90 425 ms per clip, so the end-of-speech
   timeout, not the recognizer, dominates response time.
7. **Rook is unrecognisable for most voices** (2–6% even with hints). Offer and announce alternatives: "castle"
   is ambiguous with castling, so accept **"tower"** or the letter **"R"** as synonyms, and teach the NATO
   alphabet for files ("hotel eight"), which is as accurate as letters without hints and robust to h/a/e swaps.
8. Warn users that reverberant rooms and other people talking (TV, café) roughly halve accuracy; a short "Say
   that again" with the n-best candidates read out is better than a wrong move.

## What did not work / limits

* `SpeechTranscriber` (macOS 26) unavailable on the virtual runner; not measured.
* iOS Simulator: `DictationTranscriber` works there, but `SFSpeechRecognizer` reports `denied` even with a TCC row
  in the simulator's TCC.db and has no on-device assets, so all numbers come from macOS (same Speech framework
  version family as iOS 26; real-device acoustics/microphone are not modelled).
* Shard 0 of 4 was cancelled at its time limit (its results are missing: 6 `say` voices). No real-human
  recordings of full chess moves were found; human audio covers bare squares only.
