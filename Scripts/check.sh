#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/checks build/module-cache
xcrun swiftc -swift-version 5 -strict-concurrency=complete \
  -module-cache-path build/module-cache \
  LANBrowser/Address.swift LANBrowser/Bookmarks.swift LANBrowser/ServiceCatalog.swift LANBrowser/DiagnosticsLogic.swift \
  LANBrowser/DeviceNames.swift LANBrowser/TabStore.swift LANBrowser/DiscoveryCache.swift \
  LANBrowser/PortScan.swift Tests/CoreChecks.swift \
  -o build/checks/core-checks
build/checks/core-checks "$(plutil -extract NSBonjourServices json -o - LANBrowser/Info.plist)"
plutil -lint LANBrowser/Info.plist LANBrowser/PrivacyInfo.xcprivacy LANBrowser.xcodeproj/project.pbxproj
Scripts/policy_check.sh
