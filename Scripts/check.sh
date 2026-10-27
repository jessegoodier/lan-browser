#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/checks build/module-cache
xcrun swiftc -swift-version 5 -strict-concurrency=complete \
  -module-cache-path build/module-cache \
  LANBrowser/Address.swift LANBrowser/Bookmarks.swift Tests/CoreChecks.swift \
  -o build/checks/core-checks
build/checks/core-checks
plutil -lint LANBrowser/Info.plist LANBrowser/PrivacyInfo.xcprivacy LANBrowser.xcodeproj/project.pbxproj
