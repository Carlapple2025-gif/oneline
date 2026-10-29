#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export TMPDIR="$ROOT/.tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.clang-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

swift test \
  --disable-sandbox \
  --cache-path "$ROOT/.swiftpm-cache" \
  --config-path "$ROOT/.swiftpm-config" \
  --security-path "$ROOT/.swiftpm-security" \
  --scratch-path "$ROOT/.build" \
  "$@"
