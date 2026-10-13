#!/bin/bash
# Build OnTouch, install it to /Applications and (re)start it. Run this after
# every change — with a stable signing identity the permission grants carry
# over, so there's nothing to re-grant.
set -euo pipefail
cd "$(dirname "$0")"

# Creating an app in /Applications needs admin rights, but updating one you
# already own doesn't — so prefer an existing copy, then /Applications, then the
# per-user folder.
if [ -n "${INSTALL_DIR:-}" ]; then
    DEST="$INSTALL_DIR/OnTouch.app"
elif [ -w /Applications/OnTouch.app ] || [ -w /Applications ]; then
    DEST="/Applications/OnTouch.app"
else
    DEST="$HOME/Applications/OnTouch.app"
fi
mkdir -p "$(dirname "$DEST")"

./build.sh

if pgrep -x OnTouch >/dev/null; then
    echo "==> quitting running OnTouch"
    pkill -x OnTouch
    while pgrep -x OnTouch >/dev/null; do sleep 0.2; done
fi

echo "==> installing to $DEST"
# ditto updates the bundle in place, so its path (and Login Item) stays put.
ditto .build/app.noindex/OnTouch.app "$DEST"

echo "==> launching"
open "$DEST"
