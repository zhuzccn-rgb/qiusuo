# Contributing / 参与开发

Small, focused fixes are welcome. Open an issue for substantial changes to the workflow or architecture before building them.

欢迎范围清晰的修复；较大的交互或架构变更，请先开 issue 讨论。

1. Use full Xcode and build with `./scripts/make-app.sh`.
2. Run `swift test` for Swift changes and `python3 scripts/check-release.py` before submitting.
3. Test UI changes with `QIUSUO_DATA_DIRECTORY=/tmp/qiusuo-demo`; do not use someone's real archive as a fixture.
4. Keep microphone tests opt-in and never play sound through speakers in automated checks.
5. Preserve recording confirmations, AI disclosures, original media, and endpoint validation.
6. Include the observed behavior, expected behavior, OS/Xcode version, and relevant test results. Use synthetic data, redacted logs, and original or clearly licensed artwork.

请勿提交密钥、音视频、数据库、课堂材料或开发聊天。不要通过偷偷录音来“验证”录音功能。提交的贡献默认沿用本项目 MIT 许可证；第三方文件需保留自己的许可证和来源。

See [AGENTS.md](AGENTS.md) for implementation constraints. Avoid unrelated refactors and do not claim tests or supported platforms you have not actually verified.
