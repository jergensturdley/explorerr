#!/bin/bash
# Compile, bundle, launch, verify the process stays alive, then quit.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build 2>&1 | tail -5
./scripts/make-app.sh release
open build/Explorerr.app
sleep 4
if ! pgrep -x Explorerr >/dev/null; then
    echo "VERIFY FAILED: Explorerr is not running"
    exit 1
fi
echo "VERIFY OK: Explorerr launched and is running"
osascript -e 'tell application "Explorerr" to quit' >/dev/null 2>&1 || pkill -x Explorerr || true
