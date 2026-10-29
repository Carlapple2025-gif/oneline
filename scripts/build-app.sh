#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="一行.app"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/$APP_BUNDLE"

export TMPDIR="$ROOT/.tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.clang-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

echo "==> Building release binary"
swift build \
  -c release \
  --disable-sandbox \
  --cache-path "$ROOT/.swiftpm-cache" \
  --config-path "$ROOT/.swiftpm-config" \
  --security-path "$ROOT/.swiftpm-security" \
  --scratch-path "$ROOT/.build"

BINARY="$ROOT/.build/release/OneLine"
if [[ ! -f "$BINARY" ]]; then
  echo "Build did not produce $BINARY" >&2
  exit 1
fi

echo "==> Assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY" "$APP_PATH/Contents/MacOS/OneLine"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_PATH" 2>/dev/null || true
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

echo "==> Code signing (ad-hoc)"
codesign \
  --force \
  --sign - \
  --entitlements Resources/OneLine.entitlements \
  "$APP_PATH"

codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> Self-check"
"$APP_PATH/Contents/MacOS/OneLine" --self-check

echo
echo "Built: $APP_PATH"
echo "Open:  open \"$APP_PATH\""
