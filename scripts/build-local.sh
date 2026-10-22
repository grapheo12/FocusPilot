#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DERIVED_DATA="${PROJECT_DIR}/.build/XcodeDerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/FocusPilot.app"
WIDGET_PATH="${APP_PATH}/Contents/PlugIns/FocusPilotWidget.appex"

cd "${PROJECT_DIR}"
xcodegen generate
xcodebuild \
  -project FocusPilot.xcodeproj \
  -scheme FocusPilot \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements Configuration/FocusPilotWidget.entitlements \
  "${WIDGET_PATH}"

/usr/bin/codesign \
  --force \
  --sign - \
  --options runtime \
  --entitlements Configuration/FocusPilot.entitlements \
  "${APP_PATH}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
print "Built and signed ${APP_PATH}"
