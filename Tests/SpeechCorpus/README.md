# Speech corpus (Apple recognizer transcripts of spoken chess moves)

Regression data for the spoken-move parser / resolver. Every transcript is real output of Apple's speech
recognizers (run `39548302921` of `.github/workflows/speech-lab.yml`, macOS 26.6.2, 2026-10-21); nothing is invented.
How it was made, and accuracy results: [`Tools/SpeechLab/README.md`](../../Tools/SpeechLab/README.md),
[`Tools/SpeechLab/REPORT.md`](../../Tools/SpeechLab/REPORT.md).

## Files

* `phrases.jsonl` — the 124 phrases: `phrase_id`, `text` (what was spoken), `expected_text`, `semantics`
  (the intended meaning, e.g. `{"kind":"move","piece":"N","from":null,"to":"f3","capture":false,"promo":null}`,
  `{"kind":"castle","side":"K"}`, `{"kind":"command","command":"new_game"}`, `{"kind":"square","square":"h8"}`,
  `{"kind":"answer","square":"b1"}`, `{"kind":"query","command":"where","piece":"Q"}`), `tags`.
* `transcripts.jsonl` — 4,304 clips, one JSON object per line:

```json
{"clip":"piper:vctk_p245:bishop_to_a3","phrase_id":"bishop_to_a3","expected_text":"bishop to a3",
 "speaker_source":"piper","speaker":"vctk:p245(M,Irish)","env":"clean",
 "results":{"ondevice":{"best":"They shipped her A3","nbest_alt":["..."],"ms":180}, "ondevice_ctx":{...}, ...}}
```

  `speaker_source`: `piper` (neural TTS of real-human-derived voices), `macos_say`, `human_an4` (real person,
  letter + digit from the same speaker), `human_mixed` (real letter + real digit from two people).
  `env`: `clean` or one of 18 acoustic environments (`cafe_10`, `babble_5`, `reverb_hall`, `phone`, `far`, ...).
  `results` keys = recognizer configs: `ondevice`, `ondevice_ctx`, `ondevice_lm`, `dict`, `dict_ctx`, `dict_lm` on
  every clip, `server`, `server_ctx` on about a third. Each has `best`, `nbest_alt` (the other top-5
  alternatives, best first) and `ms` latency, or `error`. Join with `phrases.jsonl` on `phrase_id` for semantics.

Suggested test: for each clip and config, feed `[best] + nbest_alt` to `SpokenMoveParser`/`MoveResolver` and
check the result against `semantics`; track the pass rate per config so parser changes can only move it up.
`ondevice_ctx` / `ondevice_lm` reflect the recommended app settings; `server` reflects the current app.

## Regenerate

1. Push a change under `Tools/SpeechLab/` (or run the workflow manually); wait for `publish`.
2. `Tools/SpeechLab/scripts/fetch_results.sh <run id> /tmp/sl --delete` (downloads the draft release asset).
3. `python3 Tools/SpeechLab/corpus/phrases.py > Tests/SpeechCorpus/phrases.jsonl`
4. `python3 Tools/SpeechLab/analyze.py /tmp/sl/results.jsonl --phrases Tests/SpeechCorpus/phrases.jsonl --corpus Tests/SpeechCorpus/transcripts.jsonl --summary /tmp/sl/summary.json`
