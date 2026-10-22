#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DERIVED_DATA="${PROJECT_DIR}/.build/XcodeDerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/FocusPilot.app"
TEAM_ID="${FOCUSPILOT_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}"

if [[ -z "${TEAM_ID}" ]]; then
  print -u2 "Set FOCUSPILOT_DEVELOPMENT_TEAM to your Apple Developer Team ID."
  print -u2 "Sign in under Xcode > Settings > Accounts first so Xcode can manage the App Group profile."
  exit 1
fi

cd "${PROJECT_DIR}"
xcodegen generate
xcodebuild \
  -project FocusPilot.xcodeproj \
  -scheme FocusPilot \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  REGISTER_APP_GROUPS=YES \
  build

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
print "Built and signed ${APP_PATH}"
