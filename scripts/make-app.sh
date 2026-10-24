#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 用 Xcode 当前 macOS SDK 编，系统才会走液态玻璃。SwiftPM 会把 sdk 标成部署版本 14。
DERIVED="$ROOT/.build/DerivedData"
xcodebuild -project Lexicon.xcodeproj \
  -scheme 求索 \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=YES \
  build

APP_SRC="$DERIVED/Build/Products/Release/求索.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "xcodebuild 没有产出 $APP_SRC" >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/求索.app"
rm -rf "$APP"
mkdir -p "$DIST"
ditto "$APP_SRC" "$APP"

# Include third-party and original license notices in the local app bundle.
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/Askfor-MIT.txt"
cp "$ROOT/third_party/MathJax/LICENSE" "$APP/Contents/Resources/Licenses/MathJax-Apache-2.0.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Licenses/"

BIN="$APP/Contents/MacOS/求索"
SDK_VER="$(xcrun --sdk macosx --show-sdk-version)"
STAMPED_SDK="$(xcrun vtool -show-build "$BIN" | awk '/^[[:space:]]*sdk / { print $2; exit }')"
if [[ "$STAMPED_SDK" == 14.* || "$STAMPED_SDK" == 15.* ]]; then
  echo "Xcode 仍把 SDK 标成 $STAMPED_SDK，补标为 $SDK_VER" >&2
  STAMPED="$(mktemp "${TMPDIR:-/tmp}/qiusuo-vtool.XXXXXX")"
  xcrun vtool -set-build-version macos 15.0 "$SDK_VER" -replace -output "$STAMPED" "$BIN"
  mv "$STAMPED" "$BIN"
  chmod +x "$BIN"
  codesign --force --sign - --entitlements "$ROOT/App/Lexicon.entitlements" "$BIN"
  codesign --force --sign - --entitlements "$ROOT/App/Lexicon.entitlements" "$APP"
  STAMPED_SDK="$(xcrun vtool -show-build "$BIN" | awk '/^[[:space:]]*sdk / { print $2; exit }')"
fi
codesign --force --sign - --entitlements "$ROOT/App/Lexicon.entitlements" "$APP"
echo "LC_BUILD_VERSION sdk=$STAMPED_SDK"

echo "已生成 $APP"
echo "打开：open \"$APP\""
