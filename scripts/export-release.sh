#!/bin/bash
#
# Release export: builds Screenish (Release) with the build number derived from
# git history and drops a zipped Screenish.app in ~/Downloads.
#
# Versioning (see CLAUDE.md):
#   MARKETING_VERSION       - app version (semver), bumped by hand in
#                             project.pbxproj and committed before each release
#   CURRENT_PROJECT_VERSION - build number = git commit count, injected here at
#                             build time (never edited by hand)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: uncommitted changes — build number reflects committed history only" >&2
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
DERIVED="build/release"

xcodebuild -project Screenish.xcodeproj -scheme Screenish -configuration Release \
    -derivedDataPath "$DERIVED" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

APP="$PWD/$DERIVED/Build/Products/Release/Screenish.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
ZIP="$HOME/Downloads/Screenish-$VERSION-b$BUILD_NUMBER.zip"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Exported: $ZIP (version $VERSION, build $BUILD_NUMBER)"
