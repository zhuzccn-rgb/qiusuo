# Resource measurements / 资源实测

Measured on **2026-10-24**, Apple M4, 16 GiB RAM, macOS 27.0.1 (26A434), arm64 Release build compiled with Xcode 27.0. This is a measurement of this build on one Mac, not a comparison against Whisper or other applications.

测试日期 **2026-10-24**。设备为 Apple M4、16 GiB 内存，macOS 27.0.1（26A434），Xcode 27.0 编译的 arm64 Release 版本。数据描述这台 Mac 上的这一版应用，没有与 Whisper 或其他应用做对照测试。

## Results / 结果

Each value below is the median of three run averages. CPU uses the median of each run’s CPU time divided by wall time; **100% means one fully occupied CPU core**. MiB = 1,048,576 bytes. Physical footprint and resident memory are different metrics, not quantities to add together.

下表为三轮结果的中位数：内存每轮先取采样平均，CPU 每轮用累计 CPU 时间增量除以实际经过时间。**100% 对应占满一个 CPU 核心**。MiB 为 1,048,576 字节。物理占用和常驻内存是两种统计口径，不能相加。

| Scenario / 场景 | Physical footprint / 主进程物理占用 | Resident / 主进程常驻内存 | Idle CPU / 空闲 CPU |
| :--- | ---: | ---: | ---: |
| Empty archive / 空档案 | 17.8 MiB | 67.4 MiB | 0.01% |
| 1,000 synthetic lectures / 1,000 条合成记录 | 24.7 MiB | 71.1 MiB | 0.01% |

Built app bundle: **5.16 MiB** (5,413,080 logical bytes, summing regular files in the app bundle; excludes system frameworks, downloaded speech assets, Xcode and user data).

本机应用包为 **5.16 MiB**，按包内文件逻辑字节总和统计，不包含系统框架、下载的语音资源、Xcode 或用户数据。

## Conditions and scope / 条件与范围

- Three fresh process launches per scenario. Wait 5 seconds, then sample once per second for 20 seconds. The main Homework window is open with no interaction. Other desktop applications remained open; this is not an isolated laboratory machine.
- Each launch uses a new disposable archive and inbox. The larger archive has 1,000 synthetic lectures, each with a 400-word transcript, short summary and tags. No real classroom material is used.
- `proc_pid_rusage` supplies physical footprint, resident size and CPU counters. Mach absolute-time CPU counters are converted with `mach_timebase_info` (125/3 on this machine). The script was checked against a one-core busy-loop control before sampling.
- **Main application process only.** These idle figures do not measure active recording, speech recognition, OCR, formula rendering in WebKit helper processes, model inference or system speech-service memory. Do not interpret them as transcription memory or total system cost.
- No microphone capture, speaker playback, model endpoint request, calendar read or speech-model loading occurs in this benchmark.
- Native Swift compilation avoids shipping a Python interpreter or Electron application runtime. The app uses Apple system frameworks; formula rendering uses bundled JavaScript. Compilation alone does not establish a speed advantage over another implementation.

每个场景启动三次独立进程，预热 5 秒后，以每秒一次的频率采样 20 秒；作业主窗口保持打开，不进行操作。桌面其他应用仍在运行。大档案包含 1,000 条合成记录，每条约 400 词转写、短总结和标签。

**统计仅覆盖应用主进程。** 未测量实际录音、转写、OCR、WebKit 公式渲染辅助进程、AI 推理或系统语音服务的占用，不能将这些空闲数值当成转写占用或系统总开销。测试没有录音、外放、访问模型接口、读取日历或加载语音模型。

应用核心是编译后的原生 Swift，不随包分发 Python 解释器或 Electron 应用运行时；仍然使用系统框架，公式渲染使用内置 JavaScript。原生编译本身不等于已经证明比其他实现更快。

## Raw results and reproduction / 原始数据与复现

The [raw JSON](benchmarks/2026-10-24-m4.json) includes every memory sample, CPU counter deltas, hardware/OS details and the measured executable’s SHA-256. The app bundle size corresponds to that tested build; later documentation-only changes do not rebuild the bundle.

原始 JSON 保留每次内存采样、CPU 计数增量、设备与系统信息，以及被测可执行文件的 SHA-256；应用包大小对应被测构建。

```sh
./scripts/make-app.sh
python3 scripts/measure-idle.py --output /tmp/askfor-idle.json
```

Python is used only by the development measurement script, not by the app. It creates and removes its own temporary synthetic data. Do not interact with the app during sampling.

测量脚本使用 Python 标准库，应用本身不依赖 Python。脚本只创建和清理自己的临时合成数据；采样期间不要操作应用。

CPU counter semantics were checked against Apple’s [XNU task accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c) and [rusage implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c).
