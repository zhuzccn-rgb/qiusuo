#!/bin/bash
# Double-click in Finder to build Askfor with the installed Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then CHECK_ONLY=true; fi
LANGUAGE=en
if [[ "$(/usr/bin/defaults read -g AppleLanguages 2>/dev/null | /usr/bin/sed -n '2p' || true)" == *zh* ]]; then LANGUAGE=zh; fi
choose_text() { if [[ "$LANGUAGE" == zh ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
notify() {
    [[ "$CHECK_ONLY" == true ]] && return 0
    /usr/bin/osascript - "$1" "$2" <<'APPLESCRIPT' || true
on run argv
    display alert (item 1 of argv) message (item 2 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}
fail() {
    printf '\n%s\n' "$1" >&2
    notify "Askfor" "$1"
    exit 1
}
[[ "$(/usr/bin/uname -m)" == arm64 ]] || fail "$(choose_text 'This build requires an Apple Silicon Mac.' '此版本需要 Apple Silicon Mac。')"
OS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
[[ "$OS_MAJOR" -ge 15 ]] || fail "$(choose_text 'Askfor requires macOS 15 or later.' '求索需要 macOS 15 或更新版本。')"
# Use an installed full Xcode without changing the system-wide selection.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    SELECTED="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    if [[ "$SELECTED" == *.app/Contents/Developer ]]; then
        export DEVELOPER_DIR="$SELECTED"
    elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        fail "$(choose_text 'Install full Xcode from the Mac App Store, open it once to finish setup, then run this file again. Command Line Tools alone are insufficient. No separate Python, Whisper or Homebrew installation is needed.' '请从 Mac App Store 安装完整 Xcode，打开一次完成初始化后，再双击此文件。仅安装命令行工具不够；无需另外安装 Python、Whisper 或 Homebrew。')"
    fi
fi
if ! /usr/bin/xcodebuild -version; then
    fail "$(choose_text 'Open Xcode and complete its first-launch setup and license agreement, then try again.' '请先打开 Xcode，完成首次初始化和许可确认，再重试。')"
fi
SDK_VERSION="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
SDK_MAJOR="${SDK_VERSION%%.*}"
[[ "$SDK_MAJOR" =~ ^[0-9]+$ ]] || fail "$(choose_text 'The macOS SDK is unavailable. Complete Xcode setup and try again.' '未找到 macOS SDK，请完成 Xcode 初始化后重试。')"
[[ "$SDK_MAJOR" -ge 26 ]] || fail "$(choose_text 'Update Xcode to a version with the macOS 26 SDK or newer (SpeechAnalyzer and FoundationModels are required to build).' '请更新到包含 macOS 26 或更新 SDK 的 Xcode，编译需要 SpeechAnalyzer 和 FoundationModels。')"
[[ -f "$ROOT/Lexicon.xcodeproj/project.pbxproj" && -f "$ROOT/scripts/make-app.sh" ]] || fail "$(choose_text 'Keep this file inside the complete Askfor source folder.' '请将此文件保留在完整的求索源码文件夹中。')"
printf '\n%s\n' "$(choose_text 'Environment ready.' '编译环境已就绪。')"
[[ "$CHECK_ONLY" == true ]] && exit 0
mkdir -p "$ROOT/.build"
LOG="$ROOT/.build/manual-build.log"
printf '%s\n' "$(choose_text 'Building Askfor… This may take a few minutes.' '正在编译求索……首次编译可能需要几分钟。')"
if ! /bin/zsh "$ROOT/scripts/make-app.sh" > "$LOG" 2>&1; then
    /usr/bin/tail -n 25 "$LOG" >&2
    fail "$(choose_text "Build failed. The last errors are shown in Terminal. Full log: $LOG" "编译失败，终端已显示末尾错误。完整日志：$LOG")"
fi
notify "Askfor" "$(choose_text 'Build complete. Finder will show the app. Move it to Applications to install.' '编译完成，即将在 Finder 中显示应用。将它移到「应用程序」即可安装。')"
/usr/bin/open -R "$ROOT/dist/求索.app"
