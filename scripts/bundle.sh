#!/bin/sh
# Builds vimouse.app into build/ and signs it.
#
# Signing identity (first match wins):
#   1. $SIGN_IDENTITY, if set (e.g. "Developer ID Application: Name (TEAMID)")
#   2. a certificate named "vimouse-dev" in the login keychain (self-signed; see README)
#   3. ad-hoc ("-"), with a warning: macOS ties the Accessibility grant to the
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

if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '"vimouse-dev"'; then
    SIGN_IDENTITY="vimouse-dev"
  else
    SIGN_IDENTITY="-"
    echo "warning: no 'vimouse-dev' certificate found; signing ad-hoc (Accessibility grant will not survive rebuilds)" >&2
  fi
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "$APP (signed as $SIGN_IDENTITY)"
