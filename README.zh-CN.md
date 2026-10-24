<p align="center">
  <img src="docs/assets/banner.svg" alt="求索 · Askfor — 让听过的课，成为真正学会的东西" width="100%" />
</p>
<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>
<p align="center">
  <img alt="平台：macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-303b54?style=flat-square" />
  <img alt="原生 Swift" src="https://img.shields.io/badge/Swift-native-786a9f?style=flat-square" />
  <a href="LICENSE"><img alt="MIT 许可证" src="https://img.shields.io/badge/license-MIT-6d8f83?style=flat-square" /></a>
  <img alt="早期源码版本" src="https://img.shields.io/badge/status-early%20source%20release-b19676?style=flat-square" />
</p>

## 课听完了，学习才刚开始

一节课结束，留下来的可能是零散的笔记、一段录音，还有几个“当时好像懂了”的瞬间。

<strong>求索（Askfor）</strong> 是一款轻量的原生 Mac 学习档案，把录音、转写、作业和错题放到一起，按课程整理，变成可以反复回看的学习笔记。

界面跟随 macOS 的语言偏好：中文显示“求索”，英文显示 **Askfor**。

## 轻量，是它的首要特点

**原生 Swift 编译核心，不用常驻一套转写服务。** 求索使用 SwiftUI 和 Apple 的本机语音框架，不需要另外运行 Whisper 服务，也不依赖 Electron 外壳或 Python 运行时。所需语音资源由系统按需下载。

录音、转写、OCR 和档案存储在本机完成。AI 学习笔记是可选功能，连接你配置的 OpenAI 兼容接口；Markdown 笔记通过内置 MathJax 显示数学公式。

| 空闲场景 | 主进程物理占用 | 主进程常驻内存 | CPU |
| :--- | ---: | ---: | ---: |
| 空档案 | 17.8 MiB | 67.4 MiB | 0.01% |
| 1,000 条合成记录 | 24.7 MiB | 71.1 MiB | 0.01% |

M4 / 16 GiB Mac，macOS 27.0.1，Release 构建，2026-10-24。每个场景三轮，预热 5 秒后空闲采样 20 秒，表中为中位数。应用包 **5.16 MiB**，系统框架和语音资源另计。[测量详情与原始数据](docs/PERFORMANCE.md)。

## 它能帮你做什么

| 学习材料 | 使用方式 |
| :--- | :--- |
| 音频 | 录制或导入、本机转写，按课程和标签搜索 |
| 转写稿 | 通过可选的 AI 功能整理学习笔记 |
| PDF、扫描件、零散笔记 | 文件夹收件箱归集与文字识别 |
| 做错的题 | 记录题目、正确答案和思路分析 |
| 课程日历 | 通过 macOS 日历匹配录音课时 |
| 学习笔记 | 显示数学公式，导出 Markdown |

## 界面预览

![Askfor 学习笔记](docs/assets/app-preview.png)

## 编译运行

- **Apple Silicon Mac，macOS 15 或更新版本**。
- **完整 Xcode**，SDK 需提供 SpeechAnalyzer 与 FoundationModels（Xcode 27 或兼容版本）。
- 对应转写语言的系统语音资源。

```sh
git clone https://github.com/zhuzccn-rgb/qiusuo.git
cd qiusuo
./scripts/make-app.sh
open dist/求索.app
```

也可以用 Xcode 打开 `Lexicon.xcodeproj`，选择 **求索** scheme。

## 第一次使用

1. 进入 **课堂录音**，录制或导入音频。
2. 停止并保存，然后转写。
3. 编辑课程与标题，或启用日历课时匹配。
4. 配置模型接口，生成学习笔记。
5. 检查笔记，按需导出 Markdown。

iPad 材料可以先 AirDrop 到 Mac，再放入 `~/Downloads/LexiconInbox/`，或在应用中手动选取。

## 可选：连接模型

求索支持 OpenAI 兼容的 `/v1/models` 和 `/v1/chat/completions` 接口，提供 llama.cpp、LM Studio、Ollama 和 Agent 网关等预设。

| 设置 | 示例 |
| :--- | :--- |
| Base URL | `http://127.0.0.1:8080/v1` |
| 模型 | 服务端实际提供的模型标识 |
| API Key | 服务端要求时填写，在本次运行期间保留 |

本机回环地址支持 HTTP，远程地址需使用 HTTPS。点击 **刷新模型** 获取模型列表，点击 **测试连接** 检查接口。

## 项目结构

```text
App / SwiftUI
 ├─ LexiconCore      SQLite 档案、搜索、Markdown/LaTeX 辅助
 ├─ LexiconSpeech    麦克风录制、本机语音识别、音频工具
 ├─ LexiconInbox     文件夹监视、PDF/图片 OCR、文件导入
 ├─ LexiconCalendar  EventKit 课程匹配
 └─ LexiconLLM       OpenAI 兼容客户端、学习提示词
```

默认数据位置：

```text
~/Library/Application Support/Lexicon/archive.sqlite
~/Library/Application Support/Lexicon/recordings/
~/Downloads/LexiconInbox/
```

开发检查：

```sh
swift test
python3 scripts/check-release.py
```

参与贡献请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 合规声明

请仅录制和处理已获授权的材料，遵守适用法律、学校与课程规定及相关同意要求；向 AI 服务发送材料或对外分享前，应取得相应许可。软件的开源许可证不授予录音及其他导入材料的使用权。

## 许可证

[MIT](LICENSE)。内置 MathJax 3.2.2 采用 [Apache 2.0](third_party/MathJax/LICENSE)，详见[第三方声明](THIRD_PARTY_NOTICES.md)。
