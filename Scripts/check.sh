#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/checks build/module-cache
xcrun swiftc -swift-version 5 -strict-concurrency=complete \
  -module-cache-path build/module-cache \
  LANBrowser/Address.swift LANBrowser/Bookmarks.swift LANBrowser/ServiceCatalog.swift LANBrowser/DiagnosticsLogic.swift \
  LANBrowser/DeviceNames.swift LANBrowser/TabStore.swift LANBrowser/DiscoveryCache.swift \
  LANBrowser/PortScan.swift LANBrowser/PasswordPolicy.swift Tests/CoreChecks.swift \
  -o build/checks/core-checks
build/checks/core-checks "$(plutil -extract NSBonjourServices json -o - LANBrowser/Info.plist)"
plutil -lint LANBrowser/Info.plist LANBrowser/PrivacyInfo.xcprivacy LANBrowser.xcodeproj/project.pbxproj
# Both build configurations ship for iPhone and iPad, which also runs on Apple silicon Macs.
[[ $(grep -c 'TARGETED_DEVICE_FAMILY = "1,2";' LANBrowser.xcodeproj/project.pbxproj) == 2 ]] \
  || { print -u2 "TARGETED_DEVICE_FAMILY must be \"1,2\" in both configurations"; exit 1; }
Scripts/policy_check.sh
