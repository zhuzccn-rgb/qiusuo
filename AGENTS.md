# Working on Qiusuo / 求索

Native Swift 5.9, macOS 15+. Preserve the existing single-process, five-library architecture.

- Never commit secrets, recordings, transcripts, databases, personal paths, editor state, or agent conversation history.
- No speaker output during testing. Never play user recordings. Live microphone tests must be explicitly opted into.
- Do not access the user's existing archive, Downloads, calendars, or model services during verification. Use isolated fixtures and a test data directory.
- Recording requires a fresh authorization confirmation before microphone permission or capture. Do not prime the microphone just by navigating.
- AI requests require clear disclosure of destination and payload. Keep model discovery manual; do not read another application's credentials or change its settings.
- Preserve original audio and transcripts. No automatic deletion or destructive compression.
- Use the current Xcode SDK and `scripts/make-app.sh` for the distributable app; `swift test` is for module tests.
- Keep one system `NavigationSplitView`; do not add window resizing hacks or toolbar polling.
- Preserve the raw microphone path: 48 kHz, 16-bit mono CAF. Do not add gain, voice processing, or unvalidated noise cleanup.
- For changes to Swift logic, run affected tests. For UI changes, build and walk through the app using an isolated data directory, including the status menu.
- Describe evidence and limitations honestly. Do not claim legal certification, university endorsement, tested platforms, or privacy guarantees that the implementation does not support.
