# Manual testing

Automated checks run with `Scripts/check.sh`; see the [README](../README.md#testing). The checks below are on-device checks. They need WebKit, a real network, and the iOS Local Network permission, so they can’t run in the automated checks.

## Settings and first launch

- From the bookmark screen, open **Settings** (gear). Verify the privacy policy is readable offline and that **Ask for Help or Report a Problem** opens GitHub Issues.
- Run **Browser Check** offline, save the sample file, and open it in Files.
- Sign in to a test website, then use **Clear Cookies & Website Data** in Settings. Confirm the website session is signed out, all tabs close except one blank tab, and bookmarks and exported files remain.
- First launch shows **HTTP Forever Captive Portal** in bookmarks. Open it and confirm [http://httpforever.com/](http://httpforever.com/) loads over HTTP. On a captive network, confirm the sign-in page appears instead.
- First launch shows the “For Trusted Home Networks” notice once. Tap **I Understand**, force-quit, relaunch, and confirm it doesn’t return.
- Test with the keyboard visible, in landscape, in dark mode, and with larger system text.

## Browsing and tabs

- Navigate between pages, and check Back, Forward, Reload, Stop, and swipe navigation. A new-window link should open in a new tab.
- Enter an HTTPS page and test a server’s HTTP-to-HTTPS redirect. The address bar should reflect the resulting address.
- Tabs: tap a bookmark and confirm it opens in a new tab, and that opening one from a blank tab fills that tab. Create and close tabs from the Tabs switcher and from the Tabs button’s long-press menu. Set **Open Bookmarks In** to Current Tab and confirm a bookmark replaces the current page.
- Open a few tabs with some history, force-quit, and relaunch. The tabs should return, and a restored tab should load only when you switch to it. Turn **Restore Tabs on Launch** off, relaunch, and confirm tabs are not restored.

## Bookmarks

- Add a home-service bookmark such as `192.168.1.20:8080`, open it, and verify the service loads over HTTP.
- Add, edit, reorder, and delete bookmarks. Force-quit and relaunch: the edited list should survive, and the app should open bookmarks. Deleting every bookmark should leave an empty list after relaunch.

## Errors and certificates

- Visit an unreachable address, then use **Edit Address** or **Retry** to recover. Tap **Diagnose** and confirm the failing step and advice make sense. Try a closed port, a misspelled `.local` name, and a self-signed HTTPS device.
- Open a self-signed HTTPS device on your network, such as a router or NAS at `https://YOUR_DEVICE_LAN_IP/`. Confirm the page opens with the red “!” strip, and that the certificate sheet shows its SHA-256 fingerprint.
- Open [https://self-signed.badssl.com/](https://self-signed.badssl.com/) and confirm it is still rejected with the system’s normal error.
- Tap **Diagnose** on an `http://` address that redirects to `https://`, such as `http://YOUR_DEVICE_LAN_IP/`. Confirm the Web Server step lists both hops.

## Local network features

- Turn on **Local Network Features** from the bookmark-list card. Confirm the iOS Local Network prompt appears once, **On This Network** lists devices that advertise a web page, **+** saves one as a bookmark, and status dots turn green or red.
- Relaunch the app. The saved scan should appear with its scan time, and no new scan should start. **Scan Again** or a pull down on the bookmark list should start one.
- Deny the permission in the iOS Settings app and confirm the list and diagnostics explain how to turn it back on. Turn the switch off and confirm the list and dots disappear.
- On a clean install, turn on **Local Network Features** for the first time. The automatic first scan never port-scans, so its scan line should show Bonjour only.
- Pick **Common Web Apps** in **Settings › Local Network › Port Scan**. Confirm the sheet shows the right address range, the 22 ports, and the connection count, and that **Cancel** reverts the picker. Choose it again and tap **Confirm**.
- After confirming, tap **Scan Again**. Progress should appear with a **Cancel** button, and web apps that don’t advertise over Bonjour should be listed with a “port scan” tag. Relaunch the app: the saved results should appear with their scan time, and no new scan should start. Start another scan and tap **Cancel** partway through. The previous list should remain.
- Rename a device from Page Info (ⓘ), then rename one from a bookmark’s long-press menu with **Rename Device…**. Confirm every bookmark on that host updates. Tap **+** on a discovered device and confirm the new bookmark uses a `.local` URL.
- To test discovery without a home server, use the test fixture described below.

## Downloads

- Download a file, choose an **On My iPhone** or **iCloud Drive** destination, and open it in Files. Download the same name twice to check the system’s conflict handling. Cancel a Save to Files picker and verify browsing still works.
- Test a failed download, a file from a logged-in service if available, and multiple downloads. Each successful download should get its own destination picker.

## Test fixture

`Tests/serve_fixture.py` is a small local server for redirects, download links, attachment responses, blob downloads, new-window links, and JavaScript dialogs. It serves only generated test pages and files.

```sh
python3 Tests/serve_fixture.py
```

Keep Terminal running and, from the phone on the same Wi-Fi, open `http://YOUR_MAC_LAN_IP:8889/`. Allow incoming connections if macOS asks. Stop the server with Control-C.

To test discovery without a home server, advertise the fixture from the Mac over Bonjour:

```sh
dns-sd -R "LAN Fixture" _http._tcp local 8889
```

After a scan with **Local Network Features** on, the fixture should appear in **On This Network**.
