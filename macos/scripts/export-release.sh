#!/bin/bash
#
# Release export: builds Screenish (Release) with the build number derived from
# git history, verifies the code signature, optionally notarizes, and drops a
# zipped Screenish.app in ~/Downloads.
#
# Versioning (see CLAUDE.md):
#   MARKETING_VERSION       - app version (semver), bumped by hand in
#                             project.pbxproj and committed before each release
#   CURRENT_PROJECT_VERSION - build number = git commit count, injected here at
#                             build time (never edited by hand)
#
# Signing:
#   If a "Developer ID Application" identity is in the keychain the build is
#   signed with it and notarized (keychain profile $NOTARY_PROFILE, created with
#   `xcrun notarytool store-credentials <profile>`). That is the only way the app
#   opens cleanly on other Macs.
#   Otherwise the build falls back to the Xcode "Apple Development" identity.
#   Gatekeeper will then require "Open Anyway" on other Macs, and the export
#   is clearly marked as such.
#   In both cases the signing certificate is checked against Apple's revocation
#   service: a revoked certificate makes macOS report the app as malware.
#
# Env overrides:
#   NOTARY_PROFILE  notarytool keychain profile name (default: screenish-notary)
#   SKIP_NOTARIZE=1 build with Developer ID but do not notarize
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-screenish-notary}"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: uncommitted changes — build number reflects committed history only" >&2
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
DERIVED="build/release"

DEV_ID=$(security find-identity -v -p codesigning \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)

SIGN_ARGS=()
if [[ -n "$DEV_ID" ]]; then
    echo "Signing with: $DEV_ID"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$DEV_ID"
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
else
    echo "warning: no 'Developer ID Application' identity found — falling back to" >&2
    echo "         Apple Development signing. Other Macs will need 'Open Anyway'." >&2
fi

xcodebuild -project Screenish.xcodeproj -scheme Screenish -configuration Release \
    -derivedDataPath "$DERIVED" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
    build

APP="$PWD/$DERIVED/Build/Products/Release/Screenish.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)

# --- Verify the signature and that the signing certificate is not revoked ----
codesign --verify --deep --strict --verbose=2 "$APP"

CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT
codesign -d --extract-certificates="$CERT_DIR/cert" "$APP" 2>/dev/null
openssl x509 -inform DER -in "$CERT_DIR/cert0" -out "$CERT_DIR/leaf.pem"
if ! security verify-cert -c "$CERT_DIR/leaf.pem" -p codeSign -R ocsp >/dev/null 2>&1; then
    echo "error: signing certificate failed verification (revoked or invalid):" >&2
    openssl x509 -in "$CERT_DIR/leaf.pem" -noout -subject -dates >&2
    echo "       Shipping this build would make macOS report the app as malware." >&2
    echo "       Create a fresh certificate in Xcode > Settings > Accounts." >&2
    exit 1
fi
echo "Signing certificate OK: $(openssl x509 -in "$CERT_DIR/leaf.pem" -noout -subject | sed 's/.*CN=//; s/,.*//')"

# --- Notarize (Developer ID only) ------------------------------------------
SUFFIX=""
if [[ -n "$DEV_ID" && "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    NOTARY_ZIP=$(mktemp -d)/Screenish.zip
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -rf "$(dirname "$NOTARY_ZIP")"
elif [[ -z "$DEV_ID" ]]; then
    SUFFIX="-unnotarized"
fi

ZIP="$HOME/Downloads/Screenish-$VERSION-b$BUILD_NUMBER$SUFFIX.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Gatekeeper assessment:"
spctl -a -vv -t exec "$APP" 2>&1 | sed 's/^/  /' || true
echo
echo "Exported: $ZIP (version $VERSION, build $BUILD_NUMBER)"
