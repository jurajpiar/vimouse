#!/bin/sh
# Builds the bundle and installs it into ~/Applications (or $1), replacing any
# previous copy, then launches it.
set -eu
cd "$(dirname "$0")/.."
DEST="${1:-$HOME/Applications}"
./scripts/bundle.sh
mkdir -p "$DEST"
pkill -x vimouse 2>/dev/null || true
rm -rf "$DEST/vimouse.app"
cp -R build/vimouse.app "$DEST/vimouse.app"
open "$DEST/vimouse.app"
echo "installed $DEST/vimouse.app"
