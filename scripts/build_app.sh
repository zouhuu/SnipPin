#!/bin/bash
# Build SnipPin.app from the SwiftPM package.
#
#   ./scripts/build_app.sh            # build + assemble build/SnipPin.app
#   ./scripts/build_app.sh --install  # ... and copy to ~/Applications + relaunch
#   ./scripts/build_app.sh --debug    # debug build (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --debug) CONFIG=debug ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/spm"
mkdir -p .cache/clang .cache/spm

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --disable-sandbox \
  --scratch-path .build --cache-path .cache/build

BIN=".build/$CONFIG/SnipPin"
APP="build/SnipPin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnipPin"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature with a stable identifier so TCC (screen recording) can remember the app.
codesign --force --sign - --identifier com.zouhuu.snippin --timestamp=none "$APP" >/dev/null
codesign --verify --deep --strict "$APP" && echo "==> signed (adhoc)"

echo "==> built $APP"

if [ "$INSTALL" = "1" ]; then
  DEST="$HOME/Applications/SnipPin.app"
  mkdir -p "$HOME/Applications"
  pkill -x SnipPin 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "==> installed $DEST"
  open "$DEST"
fi
