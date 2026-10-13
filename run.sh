#!/bin/bash
# Build (if needed) and run the bundled app in the foreground so its NSLog
# output is visible in the terminal. Ctrl-C to quit.
set -euo pipefail
cd "$(dirname "$0")"

[ -d ".build/app.noindex/OnTouch.app" ] || ./build.sh
exec ./.build/app.noindex/OnTouch.app/Contents/MacOS/OnTouch
