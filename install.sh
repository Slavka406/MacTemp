#!/bin/zsh
# Builds MacTemp (menu bar app + widget + fan helper) and installs it into ~/Applications.
set -euo pipefail
cd "${0:A:h}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# A fresh build number makes macOS drop its cached icon and widget.
xcodebuild -project MacTemp.xcodeproj -target MacTemp -configuration Release \
  build SYMROOT="$PWD/build" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" -quiet

pkill -x MacTemp 2>/dev/null || true
pkill -x MacTempWidget 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/MacTemp.app
cp -R build/Release/MacTemp.app ~/Applications/

# Only the installed copy should provide the widget.
"$lsregister" -u build/Release/MacTemp.app 2>/dev/null || true
"$lsregister" -f ~/Applications/MacTemp.app

open ~/Applications/MacTemp.app
echo "MacTemp installed into ~/Applications and launched."
