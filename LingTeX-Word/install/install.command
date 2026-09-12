#!/bin/sh
# install.command -- LingTeX-Word for Mac: double-click to install.
# Runs install.sh beside it in a Terminal window; Word must be quit.
# If macOS refuses to open it ("unidentified developer"), right-click > Open.
cd "$(dirname "$0")" && sh ./install.sh "$@"
echo ""
echo "Press Return to close this window."
read _
