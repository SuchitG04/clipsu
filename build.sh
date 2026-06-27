#!/bin/bash
#
# Builds Succlippy and assembles a runnable Succlippy.app bundle (ad-hoc signed).
#
# Usage:
#   ./build.sh            # release build → ./build/Succlippy.app
#   ./build.sh debug      # debug build
#   ./build.sh run        # build (release) then launch the app
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
LAUNCH="no"
case "${1:-}" in
    debug) CONFIG="debug" ;;
    run)   LAUNCH="yes" ;;
    "")    ;;
    *)     echo "Unknown argument: $1"; exit 1 ;;
esac

APP_NAME="Succlippy"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "▸ Compiling (${CONFIG})…"
swift build -c "${CONFIG}" --product "${APP_NAME}"

BIN_PATH="$(swift build -c "${CONFIG}" --product "${APP_NAME}" --show-bin-path)/${APP_NAME}"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS}/Info.plist" 2>/dev/null || true
fi

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "${APP_DIR}"

echo "✓ Built ${APP_DIR}"

if [ "${LAUNCH}" = "yes" ]; then
    echo "▸ Launching…"
    # Kill any previous instance first.
    pkill -x "${APP_NAME}" 2>/dev/null || true
    open "${APP_DIR}"
fi
