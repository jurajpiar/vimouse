#!/bin/sh
# Builds, signs with the hardened runtime, notarises and staples vimouse.app, then
# zips it for a GitHub release and prints the sha256 for the Homebrew cask.
#
# One-time setup (an App Store Connect app-specific password, team W9V89X3L73):
#   xcrun notarytool store-credentials vimouse-notary --apple-id <apple id> --team-id <team id>
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
# Requires a "Developer ID Application" certificate (SIGN_IDENTITY may name it).
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.1.0}"
PROFILE="${NOTARY_PROFILE:-vimouse-notary}"

# Stamp the version into the bundle and the manual.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist
sed -i '' "s/public static let version = \"[^\"]*\"/public static let version = \"$VERSION\"/" Sources/VimouseCore/Manual.swift

APP="$(CONFIG=release NOTARISE=1 scripts/bundle.sh | sed 's/ (signed as.*//')"
case "$(codesign -dv "$APP" 2>&1)" in
  *"Developer ID Application"*) ;;
  *) echo "error: $APP is not signed with a Developer ID Application certificate; notarisation needs one" >&2; exit 1 ;;
esac

ZIP="build/vimouse-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "submitting $ZIP for notarisation (profile $PROFILE)" >&2
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
# Re-zip with the ticket stapled; that is what the cask downloads.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vv -t exec "$APP" >&2
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "$ZIP"
echo "sha256 $SHA"
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/vimouse.rb
echo "Casks/vimouse.rb updated; commit it, tag v$VERSION, and attach $ZIP to the GitHub release."
