#!/bin/sh
# Publishes a release built by scripts/release.sh: commits the version stamp,
# tags, pushes, creates the GitHub release with the zip, and pushes the cask to
# the Homebrew tap (github.com/jurajpiar/homebrew-vimouse, created if missing).
#
# Usage: scripts/publish.sh <version>      after: scripts/release.sh <version>
# Requires: gh (logged in: gh auth status), a clean tree apart from the files
# release.sh touched, and the tag v<version> not yet existing.
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.1.0}"
TAG="v$VERSION"
ZIP="build/vimouse-$VERSION.zip"
OWNER="${TAP_OWNER:-jurajpiar}"
TAP_REPO="homebrew-vimouse"
TAP_DIR="${TAP_DIR:-$HOME/github.com/$OWNER/$TAP_REPO}"

command -v gh >/dev/null || { echo "error: gh not found (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not logged in (gh auth login)" >&2; exit 1; }
[ -f "$ZIP" ] || { echo "error: $ZIP missing; run scripts/release.sh $VERSION first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "error: tag $TAG already exists" >&2; exit 1; }

# The cask must point at this version and at this zip.
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
grep -q "version \"$VERSION\"" Casks/vimouse.rb || { echo "error: Casks/vimouse.rb is not at $VERSION" >&2; exit 1; }
grep -q "sha256 \"$SHA\"" Casks/vimouse.rb || { echo "error: Casks/vimouse.rb sha256 does not match $ZIP" >&2; exit 1; }

# Only the files release.sh stamps may be dirty.
DIRTY="$(git status --porcelain | grep -v -e 'Resources/Info.plist' -e 'Sources/VimouseCore/Manual.swift' -e 'Casks/vimouse.rb' || true)"
[ -z "$DIRTY" ] || { echo "error: uncommitted changes besides the release stamp:" >&2; echo "$DIRTY" >&2; exit 1; }

git add Resources/Info.plist Sources/VimouseCore/Manual.swift Casks/vimouse.rb
git diff --cached --quiet || git commit -m "Release $VERSION"
git tag -a "$TAG" -m "vimouse $VERSION"
git push origin HEAD "$TAG"

gh release create "$TAG" "$ZIP" --title "vimouse $VERSION" --generate-notes

# Tap: clone or update, drop the cask in, push.
if [ ! -d "$TAP_DIR/.git" ]; then
  if gh repo view "$OWNER/$TAP_REPO" >/dev/null 2>&1; then
    gh repo clone "$OWNER/$TAP_REPO" "$TAP_DIR"
  else
    gh repo create "$OWNER/$TAP_REPO" --public --clone \
      --description "Homebrew tap for vimouse" >/dev/null
    # gh clones into ./homebrew-vimouse; move it where we expect it.
    mkdir -p "$(dirname "$TAP_DIR")"
    mv "$TAP_REPO" "$TAP_DIR"
  fi
fi
cd "$TAP_DIR"
git pull --ff-only 2>/dev/null || true
mkdir -p Casks
cp "$OLDPWD/Casks/vimouse.rb" Casks/vimouse.rb
if [ ! -f README.md ]; then
  cat > README.md <<README
# homebrew-vimouse

Homebrew tap for [vimouse](https://github.com/$OWNER/vimouse).

    brew install --cask $OWNER/vimouse/vimouse
README
  git add README.md
fi
git add Casks/vimouse.rb
git commit -m "vimouse $VERSION"
git push -u origin HEAD

echo "published: https://github.com/$OWNER/vimouse/releases/tag/$TAG"
echo "install:   brew install --cask $OWNER/vimouse/vimouse"
echo "check:     brew audit --cask --online $OWNER/vimouse/vimouse && brew style $OWNER/vimouse/vimouse"
