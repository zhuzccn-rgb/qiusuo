# Source release — 2026-10-23 / 源码发布说明

## Update — 2026-10-24 / 更新

- English product name: **Askfor**; Chinese name: **求索**. Repository URL and stored archive identifiers remain stable.
- The interface follows macOS language preferences, with English and Simplified Chinese catalogs covering 294 strings. This includes the window title, navigation, controls, settings, AppKit confirmations, status-menu strings, permission descriptions and library errors. Unsupported languages fall back through the supported preferences, then English. User-authored content is not translated; the transcription language remains a separate setting. Relaunch after changing the app’s language in macOS.
- Removed screen-control and pointer overlays from the synthetic preview image using image editing; the README identifies this cleanup.
- Added reproducible [resource measurements](PERFORMANCE.md), every memory sample and CPU deltas, with a development-only standard-library measurement script. No Whisper comparison or active-transcription performance claim is made.
- Verification: **128 discovered tests, 127 passed, 1 live microphone test skipped, 0 failures**. Release build and both string catalogs passed checks; localization format placeholders match.
- UI checks used a separately identified, ad-hoc signed test copy and disposable synthetic archives. English: all five navigation areas, four settings sections, recording authorization/cancel and AI disclosure/cancel. Chinese: window title, navigation, recording labels/tabs and recording authorization/cancel. No real microphone capture or model request occurred. The status-menu strings were reviewed in source; their native menu was not separately exercised.

英文名已改为 **Askfor**，中文名保留“求索”。应用会按 macOS 的语言偏好显示英文或简体中文，课程名称、文件名、笔记和已有档案标识不会被翻译。语音转写语言仍独立设置；修改系统中的应用语言后重新启动即可。

截图已清除屏幕控制叠层与光标，说明中注明了清理；README 新增轻量架构说明和带原始数据的实测表。新版本完整测试 127 项通过、1 项真实麦克风测试跳过，无失败。独立测试副本完成了上述中英界面及取消路径检查，没有录音或发送模型请求。

## Scope / 范围

A clean source snapshot of the personal Askfor/Lexicon app, prepared without the original Git history, editor state, agent conversations, archives, tokens, or real course media. The original working directory and its uncommitted changes were preserved.

这是个人求索/Lexicon 项目的独立源码快照，不包含旧 Git 历史、编辑器状态、开发聊天、档案库、密钥或真实课堂材料。原工作目录及其中未提交的修改保持原样。

## Changes / 本次整理

- Per-session recording authorization before microphone access; no navigation/startup microphone priming.
- Separate AI disclosure and export confirmation, with cancellation as the default.
- Manual endpoint/model discovery, loopback defaults, HTTPS for remote endpoints, rejection of URL credentials/query strings/fragments, and no automatic HTTP redirects.
- Self-contained transcript prompts; no private filesystem instructions, private skills, automatic slide browsing, or Hermes credential/configuration access.
- Session-only API keys; archive settings do not persist new tokens.
- Preserve recordings and transcripts after summarization; disable automatic compression and make the compression utility preserve originals.
- Watch only the configured inbox; no automatic AirDrop file moves or watching all Downloads.
- Isolated demo storage and no calendar access in isolated demo mode.
- Local formula rendering with a content security policy and blocked automatic external navigation.
- English/Chinese README, original visual banner, synthetic app preview, privacy/use documentation, MIT license, and verified MathJax 3.2.2 license/provenance.

## Verified / 已验证

Environment: Apple Silicon, Xcode 27.0 (27A266a), macOS 27 SDK.

- Full module test run: **124 discovered; 123 passed; 1 live microphone test skipped; 0 failures**.
- Calendar tests rerun after adding isolated-demo protection: **10 passed**.
- Release app built successfully through `scripts/make-app.sh`.
- Ad-hoc app signature verified; binary reports minimum macOS 15.0 and SDK 27.0.
- Original and MathJax license files included in the built app.
- UI walkthrough with an isolated archive: all five navigation areas, recording confirmation/cancel, AI destination/content disclosure/cancel, Markdown export, and actual mathematical rendering.
- Exported a synthetic note and checked the output. No real microphone capture, class material, or model-provider request was used.
- Source-file scanner passed for configured secret patterns and private-file categories. Full source inventory reviewed before publication.

完整模块测试 123 项通过、1 项真实麦克风测试跳过、无失败；隔离日历修改后额外通过 10 项课表测试。应用成功编译，签名和 SDK 标记通过检查。主要界面、取消路径、公式显示及合成笔记导出已走查。

## Limits / 尚未验证

This is an early source release, not a notarized binary distribution or a legal compliance certification. Live recording, full speech recognition with downloaded language assets, external model servers/gateways, older supported macOS versions, and Intel Macs were not exercised in this release. The menu-bar start/stop routing was reviewed in source; a computer-use timeout prevented the menu-bar UI check, and live recording-state transitions were not tested. Existing Swift concurrency warnings in audio utilities remain; the project uses Swift 5 language mode.

这是早期源码版本，没有 Apple 公证安装包或法律合规认证。尚未实测真实录音、完整语音识别、外部模型、较旧系统与 Intel Mac。菜单栏入口已核对代码，但界面检查工具超时，未测试真实录音状态切换。音频工具仍有现存的 Swift 并发警告，项目使用 Swift 5 语言模式。
