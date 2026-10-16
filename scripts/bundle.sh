#!/bin/sh
# Builds vimouse.app into build/ and signs it.
#
# Signing identity (first match wins):
#   1. $SIGN_IDENTITY, if set (e.g. "Developer ID Application: Name (TEAMID)")
#   2. a certificate named "vimouse-dev" in the login keychain (self-signed; see README)
#   3. a valid "Developer ID Application" or "Apple Development" certificate
#   4. ad-hoc ("-"), with a warning: macOS ties the Accessibility grant to the
#      signature, and an ad-hoc signature changes with every build.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" >&2

APP="build/vimouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/vimouse" "$APP/Contents/MacOS/vimouse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Pick an identity: explicit, then vimouse-dev, then Developer ID, then Apple
# Development (valid ones only), else ad-hoc.
pick() {
  security find-identity -v -p codesigning 2>/dev/null | grep -v REVOKED | grep -o "\"$1[^\"]*\"" | head -1 | tr -d '"'
}
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(pick vimouse-dev)"
  [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="$(pick 'Developer ID Application')"
  [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="$(pick 'Apple Development')"
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
    echo "warning: no code-signing identity found; signing ad-hoc (Accessibility grant will not survive rebuilds)" >&2
  fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "$APP (signed as $SIGN_IDENTITY)"
