#!/bin/bash
# Build OnTouch, install it to /Applications and (re)start it. Run this after
# every change — with a stable signing identity the permission grants carry
# over, so there's nothing to re-grant.
set -euo pipefail
cd "$(dirname "$0")"

# /Applications needs an admin account; fall back to the per-user folder.
if [ -w /Applications ]; then APPS="/Applications"; else APPS="$HOME/Applications"; fi
DEST="${INSTALL_DIR:-$APPS}/OnTouch.app"
mkdir -p "$(dirname "$DEST")"

./build.sh

if pgrep -x OnTouch >/dev/null; then
    echo "==> quitting running OnTouch"
    pkill -x OnTouch
    while pgrep -x OnTouch >/dev/null; do sleep 0.2; done
fi

echo "==> installing to $DEST"
# ditto updates the bundle in place, so its path (and Login Item) stays put.
ditto OnTouch.app "$DEST"

echo "==> launching"
open "$DEST"
