# SpeechLab

Measures how well Apple's speech recognizers understand spoken chess moves, across many voices and acoustic
environments, so the app's parser and recognizer settings can be hardened. Results: [`REPORT.md`](REPORT.md);
regression corpus: [`Tests/SpeechCorpus/`](../../Tests/SpeechCorpus/).

## Pipeline (`.github/workflows/speech-lab.yml`)

Triggered by pushes that touch `Tools/SpeechLab/**` (not `*.md` / `analyze.py`) or by `workflow_dispatch`.

| job | runner | what it does |
|---|---|---|
| `corpus-linux` | ubuntu | `corpus/phrases.py` (124 phrases), Piper neural TTS (`make_piper.py`: 39 speakers from VCTK, CMU Arctic, L2-ARCTIC, LibriTTS-R and 3 single-speaker voices), real human square names (`make_human.py`: CMU AN4 letters and digits from the same speaker, plus AN4 letters with digits from FSDD / Google Speech Commands speakers), the noise bank (`make_noise.py`), and one augmented copy of every clip (`augment.py`) |
| `recognize` ×4 | macos-26 | renders every phrase with every English `say` voice (`make_say.py`, rates 150-230 wpm), augments those too, then runs `recognizer/` (Swift CLI) over a shuffled shard with every recognizer config, with a 55 min time budget per shard |
| `publish` | ubuntu | merges the shard results and attaches them to a **draft** release `speechlab-<run id>` (drafts create no tag); `scripts/fetch_results.sh <run id> <dir> --delete` downloads it and removes the draft |
| `probe-mac` | macos-26 | cheap diagnostics: TCC / Siri / Dictation state, recognizer probe on two clips, and the iOS Simulator attempt |

Audio is never committed; everything is downloaded or synthesised inside the workflow.

### Recognizer configs (`recognizer/main.swift`)

| config | API | settings |
|---|---|---|
| `server` | `SFSpeechRecognizer(en-US)` + `SFSpeechURLRecognitionRequest` | defaults (server allowed), what the app does today |
| `server_ctx` | same | + `contextualStrings` (pieces, verbs, commands, all 64 squares) |
| `ondevice` | same | `requiresOnDeviceRecognition = true` |
| `ondevice_ctx` | same | on-device + `contextualStrings` |
| `ondevice_lm` | same | on-device + custom language model (`SFCustomLanguageModelData`, ~2,000 weighted chess phrases, `recognizer/LM.swift`) |
| `dict` | `SpeechAnalyzer` + `DictationTranscriber` (macOS/iOS 26) | `contentHints: [.shortForm]`, alternatives on |
| `dict_ctx` | same | + `AnalysisContext.contextualStrings[.general]` |
| `dict_lm` | same | + contextual strings + `.customizedLanguage(modelConfiguration:)` with the custom LM |
| `st` | `SpeechAnalyzer` + `SpeechTranscriber` | not available on the runner (see REPORT.md) |

Each result row records `best`, the top-5 `nbest` (`SFSpeechRecognitionResult.transcriptions`, or the
transcriber's `alternatives`), segment alternatives, mean segment confidence and wall-clock latency.

### Speech-recognition authorization on a headless runner

* `SFSpeechRecognizer.requestAuthorization` from a CLI never returns (no UI to show the prompt) and the status stays
  `notDetermined`. The CLI embeds an `Info.plist` (`-sectcreate __TEXT __info_plist`) with
  `NSSpeechRecognitionUsageDescription`, otherwise TCC kills it.
* Fix: `scripts/tcc_grant.py` inserts `kTCCServiceSpeechRecognition` rows (auth_value 2) into the **user**
  `~/Library/Application Support/com.apple.TCC/TCC.db`, which is writable on GitHub's macOS images, for the binary
  path, its bundle id and the "responsible" process (`/opt/hca/hosted-compute-agent`). The system TCC.db is
  read-only (SIP). After that the status is `authorized`.
* Authorization alone is not enough: Siri/Dictation are off on the runner, so on-device requests fail with
  `kLSRErrorDomain 201 "Siri and Dictation are disabled"` and server requests time out.
  `scripts/enable_dictation.sh` sets `com.apple.assistant.support "Dictation Enabled"/"Assistant Enabled"` and
  restarts the speech daemons; then both server and on-device recognition work.
* `DictationTranscriber` (SpeechAnalyzer) works without any of this.
* iOS Simulator (`xcrun simctl spawn` of the same CLI built for `iphonesimulator`): `DictationTranscriber` works;
  `SFSpeechRecognizer` reports `denied` even with a row in the simulator's TCC.db, and has no on-device assets
  ("No Assistant asset for language en-US"), so the macOS host is used for the SFSpeechRecognizer configs.

## Running locally (a Mac)

```sh
Tools/SpeechLab/recognizer/build.sh /tmp/sl macos
python3 Tools/SpeechLab/corpus/phrases.py > /tmp/sl/phrases.jsonl
python3 Tools/SpeechLab/corpus/make_say.py --phrases /tmp/sl/phrases.jsonl --out /tmp/sl/audio --manifest /tmp/sl/m.jsonl
/tmp/sl/speechlab run --manifest /tmp/sl/m.jsonl --root /tmp/sl/audio --out /tmp/sl/results.jsonl --configs dict_ctx,ondevice_ctx
python3 Tools/SpeechLab/analyze.py /tmp/sl/results.jsonl --phrases /tmp/sl/phrases.jsonl
```

On a normal Mac the first run shows the speech-recognition permission prompt for `speechlab`.

## Licenses of downloaded data

CMU AN4 (CMU, free for any use with attribution), Free Spoken Digit Dataset (CC BY-SA 4.0), Google Speech Commands
v0.02 (CC BY 4.0), DEMAND noise corpus (CC BY-SA 3.0), Piper voices (per-voice dataset licenses: VCTK CC BY 4.0,
CMU Arctic free use, L2-ARCTIC CC BY-NC 4.0, LibriTTS-R CC BY 4.0; used only to synthesise test audio). Only Apple's transcripts (text) are committed.
