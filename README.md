<p align="center">
  <img src="docs/assets/banner.svg" alt="求索 · Askfor — a place for what you learn" width="100%" />
</p>
<p align="center">
  <a href="README.zh-CN.md">简体中文</a> · <strong>English</strong>
</p>
<p align="center">
  <img alt="Platform: macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-303b54?style=flat-square" />
  <img alt="Language: Swift" src="https://img.shields.io/badge/Swift-native-786a9f?style=flat-square" />
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-6d8f83?style=flat-square" /></a>
  <a href="https://github.com/zhuzccn-rgb/qiusuo/releases/tag/v0.1.0-alpha.1"><img alt="Status: Alpha" src="https://img.shields.io/badge/status-alpha-b19676?style=flat-square" /></a>
</p>

## Make room for the next aha moment

A lecture ends. The hard part is turning what you heard into something you can return to.

**Askfor (求索)** is a lightweight, native Mac study archive. Bring recordings, transcripts, homework and mistakes into one place, organize them by course, and turn them into study notes you can revisit.

The interface follows your macOS language preferences: English (**Askfor**) or Simplified Chinese (**求索**).

## Built to stay light

**A compiled Swift core, without an always-on transcription server.** Askfor uses SwiftUI and Apple's on-device Speech frameworks. It does not require a separate Whisper service, an Electron shell or a Python runtime. Speech assets download through the system when needed.

Recordings, transcripts, OCR and archives stay on your Mac. Optional AI summaries connect to an OpenAI-compatible endpoint you configure. Markdown notes support mathematical notation through bundled MathJax.

| Idle scenario | Main-process physical footprint | Main-process resident memory | CPU |
| :--- | ---: | ---: | ---: |
| Empty archive | 17.8 MiB | 67.4 MiB | 0.01% |
| 1,000 synthetic lectures | 24.7 MiB | 71.1 MiB | 0.01% |

M4 / 16 GiB Mac, macOS 27.0.1, Release build, 2026-10-24. Medians of three runs per scenario, each with a 5-second warm-up and 20-second idle sample. App bundle: **5.16 MiB** (system frameworks and speech assets are separate). [Measurement details and raw data](docs/PERFORMANCE.md).

## What it does

| Material | Workflow |
| :--- | :--- |
| Audio | Record or import, transcribe on device, search by course and tags |
| Transcripts | Generate optional AI study notes |
| PDFs, scans and loose notes | Collect through a folder inbox and recognize text |
| Incorrect answers | Keep questions, corrections and explanations in a mistake archive |
| Course schedules | Match recordings to classes through macOS Calendar |
| Study notes | Render formulas and export Markdown |

## Preview

![Askfor study notes](docs/assets/app-preview.png)

## Download

[Download the Alpha for Apple Silicon](https://github.com/zhuzccn-rgb/qiusuo/releases/tag/v0.1.0-alpha.1). Unzip and move **Askfor.app** to Applications. Requires **macOS 15 or later**.

This preview is ad-hoc signed, without an Apple Developer ID signature or notarization. If macOS blocks the first launch, follow [Apple's instructions](https://support.apple.com/102445) under **System Settings → Privacy & Security → Open Anyway**.

## Build and run

- Apple Silicon Mac with **macOS 15 or later**.
- **Full Xcode** with an SDK providing SpeechAnalyzer and FoundationModels (Xcode 27 or a compatible version).
- System speech assets for your transcription language.

```sh
git clone https://github.com/zhuzccn-rgb/qiusuo.git
cd qiusuo
./scripts/make-app.sh
open dist/求索.app
```

For a double-click build, open **Build Askfor.command** in the source folder. It checks Xcode and the SDK, builds the app, and reports failures in a dialog. Install full Xcode and complete its first-launch setup beforehand.

You can also open `Lexicon.xcodeproj` in Xcode and select the **求索** scheme.

## Your first study session

1. Open **Recordings** to record or import audio.
2. Stop and save, then transcribe.
3. Edit the course and title, or enable calendar matching.
4. Configure a model endpoint to generate study notes.
5. Review your notes and export them as Markdown.

For iPad materials, AirDrop them to your Mac, then place them in `~/Downloads/LexiconInbox/` or choose them in the app.

## Optional model connection

Askfor supports the OpenAI-compatible `/v1/models` and `/v1/chat/completions` APIs, with presets for llama.cpp, LM Studio, Ollama and agent gateways.

| Setting | Example |
| :--- | :--- |
| Base URL | `http://127.0.0.1:8080/v1` |
| Model | The identifier exposed by your server |
| API key | Your service's key, if required; kept for the current session |

Local loopback endpoints support HTTP; remote endpoints require HTTPS. Use **Refresh models** to load the model list and **Test connection** to check the endpoint.

## Inside the app

```text
App / SwiftUI
 ├─ LexiconCore      SQLite archive · search · Markdown/LaTeX helpers
 ├─ LexiconSpeech    microphone capture · on-device speech · audio utilities
 ├─ LexiconInbox     folder watching · PDF/image OCR · file imports
 ├─ LexiconCalendar  EventKit course matching
 └─ LexiconLLM       OpenAI-compatible client · study prompts
```

Default data locations:

```text
~/Library/Application Support/Lexicon/archive.sqlite
~/Library/Application Support/Lexicon/recordings/
~/Downloads/LexiconInbox/
```

For development:

```sh
swift test
python3 scripts/check-release.py
```

See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.

## Responsible use

Record and process only materials you are authorized to use. Follow applicable law, school and course policies, and consent requirements; obtain the appropriate permission for AI processing and sharing. The software license does not grant rights to recordings or other imported materials.

## License

[MIT](LICENSE). MathJax 3.2.2 is distributed under [Apache 2.0](third_party/MathJax/LICENSE); see [third-party notices](THIRD_PARTY_NOTICES.md).
