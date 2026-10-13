#!/bin/bash
# Build OnTouch and assemble a .app bundle, then code-sign it.
#
# macOS ties Accessibility / Input Monitoring grants to the app's signature.
# Signing with a stable certificate (SIGN_IDENTITY, default "OnTouch Local
# Signing") keeps those grants across rebuilds. Without it the app is ad-hoc
# signed, which macOS identifies by binary hash — so every rebuild looks like a
# new app and needs re-granting. See README → "Signing".
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP="OnTouch.app"
BUNDLE_ID="dev.colemei.ontouch"
SIGN_IDENTITY="${SIGN_IDENTITY:-OnTouch Local Signing}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/OnTouch"

echo "==> assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OnTouch"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "==> signing with \"$SIGN_IDENTITY\""
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "==> WARNING: signing identity \"$SIGN_IDENTITY\" not found — ad-hoc signing."
    echo "    Permissions will need re-granting after every rebuild."
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "==> done: $(pwd)/$APP"
echo "    Install with ./install.sh, or run in place with ./run.sh to see logs"
