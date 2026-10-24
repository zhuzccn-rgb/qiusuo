<p align="center">
  <img src="docs/assets/banner.svg" alt="求索 · Askfor — 让听过的课，成为真正学会的东西" width="100%" />
</p>
<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a> · <a href="docs/RESPONSIBLE_USE.md">使用边界</a> · <a href="docs/PRIVACY.md">隐私与数据流</a>
</p>
<p align="center">
  <img alt="平台：macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-303b54?style=flat-square" />
  <img alt="原生 Swift" src="https://img.shields.io/badge/Swift-native-786a9f?style=flat-square" />
  <a href="LICENSE"><img alt="MIT 许可证" src="https://img.shields.io/badge/license-MIT-6d8f83?style=flat-square" /></a>
  <img alt="早期源码版本" src="https://img.shields.io/badge/status-early%20source%20release-b19676?style=flat-square" />
</p>

## 课听完了，学习才刚开始

一节课结束，留下来的可能是零散的笔记、一段录音，还有几个“当时好像懂了”的瞬间。

**求索（Askfor）**是一个原生 Mac 学习档案，把你有权使用的录音、转写、作业和错题放到一起：录制或导入，用 Apple 的本机语音工具转写，按课程整理；需要时，再让你自己配置的模型帮你梳理文字。

它从个人学习工作流里长出来，现在以早期源码版本开源。应用界面目前以中文为主，项目文档提供中英双语。

> **先有许可，再按录音。** 系统麦克风授权只允许应用使用设备，不代表老师、学校或其他参与者允许你录课。录音、交给 AI 处理和对外分享的许可需要分别确认。本项目没有大学背书，也不提供合规认证。

## 它能帮你做什么

| 手里的材料 | 整理后的样子 |
| :--- | :--- |
| 你获准录制或使用的音频 | 本机保存的录音与可搜索转写 |
| 信息密密麻麻的转写稿 | 可选的 AI 学习笔记，发送前说明目的地 |
| 扫描件、PDF、零散笔记 | 文件夹收件箱与关联档案 |
| 一道做错的题 | 错题记录、OCR 文字与可选的思路分析 |
| 课程日历 | 可选的录音课时匹配 |
| 想长期留下的笔记 | Markdown 导出与数学公式显示 |

**原生、轻装。** SwiftUI 界面，单进程、五个 Swift 模块、SQLite 存储；应用不需要 Electron 或 Python 运行时。

**档案在本机，AI 由你配置。** 录音、存储、OCR 和受支持的语音转写在 Mac 上运行。AI 总结调用你填写的 OpenAI 兼容接口。本机网关也可能把请求转发到别处，需要检查网关自己的配置。

**关键动作明确确认。** 每次开录先确认授权，AI 分析与导出分别确认。进入录音页面不会提前启用麦克风，总结完成也不会自动删除录音或转写稿。

## 界面预览

![Askfor synthetic study-note preview](docs/assets/app-preview.png)

真实应用截图，使用合成笔记和生成的静音夹具，不含真实课堂音频或学生资料。

## 编译运行

需要：

- **Apple Silicon Mac，macOS 15 或更新版本**。
- **完整 Xcode**，并将它选为当前开发工具目录。需要包含 SpeechAnalyzer 与 FoundationModels 的较新 SDK；此版本使用 Xcode 27 验证，只有 Command Line Tools 不够。
- 对应语言的本机语音识别支持与模型资源。macOS 26+ 使用 `SpeechAnalyzer`；较旧系统在可用时使用本机 `SFSpeechRecognizer`。

```sh
git clone https://github.com/zhuzccn-rgb/qiusuo.git
cd qiusuo
./scripts/make-app.sh
open dist/求索.app
```

也可以用 Xcode 打开 `Lexicon.xcodeproj`，选择 **求索** scheme。

脚本使用当前 macOS SDK 编译，生成**本机临时签名（ad-hoc）**的应用。此版本没有提供经过 Apple 公证的安装包或 App Store 版本；尚未验证较旧的受支持系统或 Intel Mac。

## 第一次使用

1. 进入 **课堂录音**。新录音先取得所需许可，再在应用中确认；也可以导入你有权使用的音频。
2. 停止并保存，然后转写。首次使用可能需要下载语音模型。
3. 编辑课程与标题；需要自动匹配课时，再主动允许读取日历。
4. 想生成学习笔记时，配置模型接口，检查发送内容与目的地，再确认发送。
5. 对照原始材料检查结果；只有材料权限允许时，才导出或分享。

iPad 材料可以先 AirDrop 到 Mac，再把希望导入的文件放进 `~/Downloads/LexiconInbox/`，或在应用里手动选取。请勿把第三方课件、课堂录音或作业答案放进公开仓库。

## 可选：连接模型

求索不附带模型权重，也不强制使用付费 AI 服务。客户端使用 OpenAI 兼容的 `/v1/models` 和 `/v1/chat/completions` 协议，提供 llama.cpp、LM Studio、Ollama 和 Agent 网关等预设。

| 设置 | 示例 |
| :--- | :--- |
| Base URL | `http://127.0.0.1:8080/v1` |
| 模型 | 你的服务端实际提供的模型标识 |
| API Key | 服务端要求时填写；只在本次应用会话中保留 |

非回环地址必须使用 **HTTPS**。连接另一台电脑时，使用带认证的 HTTPS 服务，或在 Mac 回环地址上暴露加密隧道。普通 HTTP 只接受 `localhost`、`127.0.0.1`、`::1`。

刷新模型与测试连接均由用户手动触发。课堂总结发送转写正文和少量课程信息；错题分析发送填写的题目与答案字段。外部 Agent 的工具权限、存储限制等详见[隐私与数据流](docs/PRIVACY.md)。

## 项目结构

```text
App / SwiftUI
 ├─ LexiconCore      SQLite 档案、搜索、Markdown/LaTeX 显示辅助
 ├─ LexiconSpeech    麦克风录制、本机语音识别、音频工具
 ├─ LexiconInbox     收件箱监视、PDF/图片 OCR、文件导入
 ├─ LexiconCalendar  可选的 EventKit 课程匹配
 └─ LexiconLLM       OpenAI 兼容 HTTP 客户端、学习提示词
```

默认数据位置：

```text
~/Library/Application Support/Lexicon/archive.sqlite
~/Library/Application Support/Lexicon/recordings/
~/Downloads/LexiconInbox/
```

档案**没有应用层加密**。导入文档通常只关联文件路径，音频导入可能复制到录音目录；移动原始文档可能导致引用失效。请使用可信设备，并自行安排备份。

## 参与开发

```sh
swift test
python3 scripts/check-release.py
```

测试使用合成夹具。只有显式设置 `QIUSUO_LIVE_MIC_TESTS=1` 才启用；它会录下真实环境声音，请在获得许可且适当的环境中使用。

用独立目录体验，避免打开已有档案或“下载”文件夹：

```sh
QIUSUO_DATA_DIRECTORY=/tmp/qiusuo-demo dist/求索.app/Contents/MacOS/求索
```

开发约定见 [CONTRIBUTING.md](CONTRIBUTING.md)、[AGENTS.md](AGENTS.md)，验证范围见[发布说明](docs/RELEASE_NOTES.md)。提交 issue 或 PR 时，请使用合成材料或明确获准公开的示例。

## 许可证与致谢

求索的原创代码与文档采用 [MIT 许可证](LICENSE)。内置的 MathJax 3.2.2 保留其 [Apache 2.0 许可证](third_party/MathJax/LICENSE)，详见[第三方声明](THIRD_PARTY_NOTICES.md)。

**软件的开源许可只覆盖软件本身。** 它不授予对录音、人声、课件、转写或其他导入内容的使用权。[使用边界 →](docs/RESPONSIBLE_USE.md)
