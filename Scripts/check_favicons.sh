#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/checks build/module-cache
xcrun swiftc -swift-version 5 -strict-concurrency=complete \
  -module-cache-path build/module-cache \
  LANBrowser/Address.swift LANBrowser/Bookmarks.swift LANBrowser/ServiceCatalog.swift \
  LANBrowser/DiagnosticsLogic.swift LANBrowser/DeviceNames.swift LANBrowser/DiscoveryCache.swift \
  LANBrowser/PortScan.swift LANBrowser/Certificates.swift LANBrowser/NetworkProbe.swift \
  LANBrowser/FaviconPolicy.swift LANBrowser/FaviconLoader.swift LANBrowser/LocalNetwork.swift \
  Tests/FaviconChecks.swift -o build/checks/favicon-checks
build/checks/favicon-checks "$@"
