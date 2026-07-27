#!/usr/bin/env bash
set -euo pipefail

cd "${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "XcodeGen mangler. Installer det med: brew install xcodegen" >&2
    exit 1
  fi
  brew install xcodegen
fi

plutil -lint MealShuffler/Info.plist
plutil -lint MealShuffler/PrivacyInfo.xcprivacy
xcodegen generate --spec project.yml
xcodebuild -project MealShuffler.xcodeproj -scheme MealShuffler -list
