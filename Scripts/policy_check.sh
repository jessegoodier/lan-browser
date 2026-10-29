#!/bin/zsh
# Fails if a change loosens the app's security or privacy posture. These are the
# guarantees README.md, SECURITY.md and the privacy policy make to users.
set -euo pipefail
cd "${0:A:h:h}"

failures=0
fail() { print -u2 "policy: $1"; failures=$((failures + 1)); }

# App Transport Security stays on for app networking: only local hosts and WebKit
# content are exempt, never a global or per-domain exception.
ats=$(plutil -extract NSAppTransportSecurity json -o - LANBrowser/Info.plist | tr -d '{}' | tr ',' '\n' | sort | paste -sd, -)
[[ $ats == '"NSAllowsArbitraryLoadsInWebContent":true,"NSAllowsLocalNetworking":true' ]] \
  || fail "NSAppTransportSecurity must contain exactly NSAllowsArbitraryLoadsInWebContent and NSAllowsLocalNetworking, got $ats"

manifest=LANBrowser/PrivacyInfo.xcprivacy
[[ $(plutil -extract NSPrivacyTracking raw -o - $manifest) == false ]] || fail "NSPrivacyTracking must be false"
[[ $(plutil -extract NSPrivacyTrackingDomains json -o - $manifest) == '[]' ]] || fail "NSPrivacyTrackingDomains must be empty"
[[ $(plutil -extract NSPrivacyCollectedDataTypes json -o - $manifest) == '[]' ]] || fail "NSPrivacyCollectedDataTypes must be empty"

# No third-party code: no Swift packages, CocoaPods or Carthage.
if grep -q 'SwiftPackageReference' LANBrowser.xcodeproj/project.pbxproj; then
  fail "Swift package dependencies are not allowed"
fi
for manifest_file in Package.swift Package.resolved Podfile Cartfile; do
  [[ ! -e $manifest_file ]] || fail "$manifest_file found; the app has no dependencies"
done

# Certificate overrides happen only in BrowserTab's server-trust handler, which
# limits them to local hosts and records each one.
overrides=$(grep -l 'URLCredential(trust:' LANBrowser/*.swift || true)
[[ $overrides == LANBrowser/BrowserTab.swift ]] || fail "URLCredential(trust:) may only appear in BrowserTab.swift, found in: ${overrides:-nothing}"
grep -q 'ServiceCatalog.isLocalHost' LANBrowser/BrowserTab.swift || fail "BrowserTab's trust override must check ServiceCatalog.isLocalHost"

# Probes use raw NWConnection; URLSession would hit ATS for public plain-HTTP hosts.
if grep -n 'URLSession\.\(shared\|init\)\|URLSession(' LANBrowser/*.swift; then
  fail "use NWConnection, not URLSession, for native requests"
fi

(( failures == 0 )) || exit 1
print "Policy checks passed (ATS, privacy manifest, dependencies, certificate overrides)."
