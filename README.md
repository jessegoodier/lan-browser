# LAN Browser

A small, single-page iPhone browser for home services. Built with SwiftUI and WebKit for iOS 27.0 or later; intended for iPhone 17 Pro on iOS 27.0.1. The project uses the installed Xcode 27.1 and has no dependencies to install.

## What is included

- Bookmarks home screen on fresh launch, seeded with **Omarchy — http://omarchy:8888/**.
- Bottom address bar; omitted schemes default to HTTP. Explicit HTTPS and server redirects work normally.
- Back, Forward, Reload/Stop, swipe navigation, loading state, and retryable errors.
- Add, edit, delete, and reorder bookmarks, stored on the device.
- Persistent website cookies and storage. No separate browsing-history database.
- Downloads through WebKit followed by **Save to Files**, with a destination choice for each file. Files are temporarily staged in the app and cleaned up after export or cancellation.
- System appearance, accessible control labels, and portrait/landscape layouts.

The book button opens bookmarks; from bookmarks, the globe button returns to the current page. Swipe right on a bookmark or long-press it to edit. Swipe left to delete, or tap **Edit** to delete/reorder.

## 1. Run it on your iPhone first

1. Open **LANBrowser.xcodeproj** in Xcode. Select the **LANBrowser** scheme if necessary.
2. Open **Xcode > Settings > Accounts** and add the Apple Account associated with your paid developer membership.
3. In the project navigator, select the blue project icon, select the **LANBrowser** target, and open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled. Select your paid developer **Team**.
5. The initial bundle identifier is **com.jesse.lanbrowser**. If it is unavailable, replace it with a unique identifier you control, for example **com.yourname.lanbrowser**. Keep the same identifier for the App Store Connect record and all later uploads.
6. Connect your unlocked iPhone to your Mac using a data-capable USB cable. Accept **Trust This Computer** on the phone and any pairing prompts in Xcode.
7. If requested, enable **Settings > Privacy & Security > Developer Mode** on the iPhone, restart, and confirm enabling it. This is for direct Xcode installation; TestFlight installation does not require it.
8. Select your iPhone in the run destination menu next to the scheme. If it is missing, open **Window > Devices and Simulators** and finish pairing/device preparation. Install an iOS platform component in Xcode Settings if Xcode requests it.
9. Press **⌘R**. Xcode will sign, install, and launch LAN Browser. Resolve any signing issue shown in Signing & Capabilities before continuing.
10. Connect the phone to your home Wi-Fi. Tap **Omarchy** and confirm the page loads.

You can subsequently launch the installed app from its Home Screen icon without the USB cable. On later fresh launches it opens bookmarks; returning to the app from the background keeps the page.

### If Omarchy does not load

- Try the exact address **http://omarchy:8888/** in Safari on the same iPhone. The app uses iOS’s normal DNS resolver; it does not discover machines or invent an IP address for `omarchy`.
- If Safari also fails, try **http://YOUR_SERVER_LAN_IP:8888/**. If the IP works, fix your home DNS or edit the bookmark to use the IP. A `.local` address is another option only if that machine actually advertises one.
- Ensure the service listens on the LAN interface rather than only `127.0.0.1`, its firewall permits port 8888, and the phone is not on an isolated guest Wi-Fi network.
- The ATS settings allow HTTP inside the browser. They do not repair DNS, bypass server authentication, or accept invalid HTTPS certificates.

## 2. Install through your personal TestFlight group

Do this after the direct device test succeeds. Your own account can be an internal tester; no public invitation or external beta review is needed for this route.

1. Open [App Store Connect](https://appstoreconnect.apple.com/), sign in, and choose **My Apps > + > New App**.
2. Select **iOS**, choose a primary language, and enter **LAN Browser** as the name. If that App Store Connect name is unavailable, choose another record name; the installed app can still display LAN Browser.
3. Choose the exact **Bundle ID** selected in Xcode. If it is not yet listed, register the explicit App ID in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) using your developer team, then return to the new-app form. Use a simple unique SKU such as **lan-browser-001** and create the record.
4. In Xcode, select an iOS device destination such as **Any iOS Device (arm64)**, then choose **Product > Archive**. Use your normal signed Release configuration; do not disable signing.
5. When Organizer opens, select the new archive and choose **Distribute App**. Choose the TestFlight internal-testing route if offered. Otherwise choose **App Store Connect > Upload** and restrict the build to internal testing if offered. Leave automatic signing enabled and complete validation/upload.
6. Wait for processing in **App Store Connect > My Apps > your app > TestFlight**. If Apple shows a missing agreement, compliance question, or other processing issue, resolve the specific item shown before adding the build.
7. Under **Internal Testing**, create a group such as **Personal**. Add your own App Store Connect account to the group. As the paid account holder, your account has an eligible role.
8. Add the processed build to the group. Optionally enable automatic distribution for subsequent builds. Suggested testing notes: “Home LAN browser. On home Wi-Fi, open the Omarchy bookmark at http://omarchy:8888/. Test bookmark editing and Save to Files downloads.”
9. Install Apple’s **TestFlight** app on your iPhone. Open the internal-testing invitation on that phone, accept it, and install LAN Browser.
10. Open LAN Browser from TestFlight and repeat the Omarchy/download checks below. Keep the same bundle identifier when moving from the development build to TestFlight.

**Each TestFlight build expires after 90 days.** Before expiration, increase the target’s **General > Identity > Build** number (for example, 1 → 2), archive, upload, and add the replacement to your internal group. You can leave Version at 1.0 while increasing Build. Keep backups of important bookmarks before uninstalling: deleting the app removes its local data.

Apple references: [distribution from Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), [TestFlight lifecycle and expiration](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Validation

Run the core checks from Terminal in this directory:

```sh
Scripts/check.sh
```

These compile the actual address parser and bookmark store for macOS and check hostname/port parsing, HTTP/HTTPS, malformed inputs, persistence, edits, ordering, deletion, corrupt files, and write failures. They also validate the property lists and Xcode project syntax. They do not launch WebKit or replace the physical-device checks.

Unsigned device build, useful without selecting a signing team:

```sh
xcodebuild -project LANBrowser.xcodeproj -scheme LANBrowser \
  -configuration Debug -sdk iphoneos -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

An unsigned build cannot be installed on your iPhone or uploaded to TestFlight. Normal Xcode installation/archive must use your developer team.

### Physical-device acceptance checks

- First launch shows Omarchy in bookmarks. Launch it, type `omarchy:8888` manually, and verify the correct service loads over HTTP.
- Navigate between pages; check Back, Forward, Reload, Stop, and swipe navigation. A new-window link should reuse the single browser page.
- Enter an HTTPS page and test a server’s HTTP-to-HTTPS redirect; the bar should reflect the resulting address.
- Add/edit a bookmark; reorder and delete bookmarks. Force-quit and relaunch: the edited list survives and the app opens bookmarks. Deleting every bookmark should leave an empty list after relaunch.
- Test with the keyboard visible, in landscape, in dark mode, and with larger system text.
- Visit an unreachable address, then use Edit Address or Retry to recover.
- Download a file, choose an On My iPhone or iCloud Drive destination, and open it in Files. Download the same name twice to check the system’s conflict handling. Cancel a Save to Files picker and verify browsing still works.
- Test a failed download, a file from a logged-in service if available, and multiple downloads. Each successful download should get its own destination picker.
- Repeat the key checks using the TestFlight build.

Optional local fixture for redirects, download links, attachment responses, blob downloads, new-window links, and JavaScript dialogs:

```sh
python3 Tests/serve_fixture.py
```

Keep the Terminal running and, from the phone on the same Wi-Fi, open `http://YOUR_MAC_LAN_IP:8889/`. Allow incoming connections if macOS requests them. This fixture serves only generated test pages/files. Stop it with Control-C.

## Implementation notes

The app has no analytics, advertising, cloud backend, or app-account system. Browsed websites make their own normal network requests. Bookmarks live in Application Support; website data is managed by WebKit. Download staging files live in the temporary directory and are removed after saving/cancellation or the next launch after an interrupted session.

`NSAllowsLocalNetworking` supports local hostnames/IPs. `NSAllowsArbitraryLoadsInWebContent` permits HTTP navigation and resources within WebKit, including redirects to other hostnames, without globally disabling ATS for unrelated app networking. Apple documents [local networking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [web-content HTTP exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent), and the [WebKit exception to local-network permission](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). There is no network scanning or native LAN probe in this app.

The encryption declaration reflects use of Apple’s built-in HTTPS support with no custom encryption. Revisit it if custom cryptography is added. The privacy manifest declares no tracking, app-collected data, or required-reason API use in the app’s code.

Foreground downloads only: keep the app open while downloading. Resuming downloads after termination, background transfers, tabs, bookmark sync, network discovery, and custom certificate handling are outside this version.
