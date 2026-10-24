# Privacy & data flow / 隐私与数据流

This describes the source release, not a promise about every fork, operating system, backup service, or AI provider. Read alongside [Responsible use](RESPONSIBLE_USE.md).

本文说明此源码版本的行为，不代表所有分支、操作系统、备份工具或 AI 服务的行为。请结合[使用边界](RESPONSIBLE_USE.md)阅读。

| Action / 动作 | Data and destination / 内容与去向 |
| :--- | :--- |
| Record / 录音 | Microphone → local CAF file, after per-session confirmation / 每次确认后，麦克风写入本机 CAF 文件 |
| Transcribe / 转写 | Audio → Apple's on-device speech APIs; language assets may need downloading / 音频交给 Apple 本机语音 API；首次可能下载语言资源 |
| OCR / 文字识别 | Selected PDF/image → local Apple Vision/PDFKit processing / 选定 PDF、图片在本机识别 |
| Match schedule / 匹配课表 | Optional EventKit access; event metadata used in the local archive / 可选的日历权限，事件信息用于本机归类 |
| Refresh models / 刷新模型 | Explicit GET to the configured `/models` endpoint; no lecture body / 手动请求配置的模型列表接口，不包含课堂正文 |
| Test AI / 测试连接 | A manual model-list request; no study content / 手动请求模型列表，不发送学习材料 |
| Summarize / 总结 | Transcript, title, subject, time, duration → confirmed AI endpoint / 转写、标题、科目、时间、时长发送至确认的 AI 接口 |
| Analyze mistake / 错题分析 | Subject, question, wrong and correct answers → confirmed AI endpoint / 科目、题目、错误和正确答案发送至确认的接口 |
| Export / 导出 | Markdown written to the location you choose after confirmation / 确认后，将 Markdown 写入选定位置 |

## Local storage / 本机存储

- The default archive is `~/Library/Application Support/Lexicon/archive.sqlite`; recordings live in its `recordings/` sibling.
- The app does not add its own encryption to SQLite or media. Device security, backups, synced folders, and other software can affect access.
- API tokens are session-only. Saving settings does not persist a token and removes the legacy token row. Existing database backups or free pages may still contain previously saved tokens; rotate historical credentials when relevant.
- Imported documents are generally referenced by path. Audio import can copy files into the recording archive.
- Summarization preserves the source recording and transcript. Automatic destructive compression is disabled. Explicit deletion is a separate user action; this is not a secure-erasure feature.
- `QIUSUO_DATA_DIRECTORY` accepts an absolute directory for isolated demo/test storage and a separate simulated Downloads folder.

默认目录如上。SQLite 和录音没有额外应用层加密，备份或同步工具可能改变可访问范围。API Key 只在本次运行中保留，旧数据库备份或空闲页仍可能留有历史密钥。生成总结不会自动删除原始音频或转写，显式删除也不等于安全擦除。

## Network boundary / 网络边界

AI is optional. The app uses the endpoint entered in Settings, accepts HTTPS, and permits plain HTTP only on the explicit loopback hosts. Endpoint validation rejects embedded credentials, query strings, fragments, and malformed URLs. HTTP redirects are not followed. Requests do not include raw audio or local file paths in study prompts. The app does not read Hermes credential files or change another tool's model configuration.

The receiving server sees your connection and request contents. It may log, retain, forward, or process them using tools; Askfor cannot control that server. A loopback gateway is not proof of offline operation. Configure authentication and provider retention yourself, and ensure you have permission for the chosen processing.

AI 为可选功能。客户端只使用设置里的目的地，学习提示词不附带原始音频或本机路径，也不会读取 Hermes 密钥文件或更改其他工具配置。接收服务可以记录、留存、转发或调用工具；求索无法控制服务端。本机网关不等于离线。

## Repository and reports / 仓库与反馈

The source distribution excludes recordings, transcripts, databases, local credentials, editor state, and prior development conversations. The release scanner checks common accidental inclusions; it cannot prove that a repository contains no sensitive data. Review changes before publication.

Use synthetic examples when reporting bugs. For suspected security issues, follow [SECURITY.md](../SECURITY.md); do not post real secrets or course material publicly.

源码发布排除录音、转写、数据库、本机密钥、编辑器状态与开发聊天。扫描只能检查常见误带文件，不能证明绝无敏感内容。反馈问题请用合成示例，安全问题见 [SECURITY.md](../SECURITY.md)。
