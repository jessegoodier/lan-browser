# Manual testing

Automated checks run with `Scripts/check.sh`; see the [README](../README.md#testing). The checks below are on-device checks. They need WebKit, a real network, and the Local Network permission, so they can’t run in the automated checks.

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

- Turn on **Local Network Features** from the bookmark-list card. Confirm the Local Network prompt appears once, **On This Network** lists devices that advertise a web page, **+** saves one as a bookmark, and status dots turn green or red.
- Relaunch the app. The saved scan should appear with its scan time, and no new scan should start. **Scan Again** or a pull down on the bookmark list should start one. On a Mac, use Scan Again, since there is no pull down.
- Deny the permission in the Settings app (System Settings on a Mac) and confirm the list and diagnostics explain how to turn it back on. Turn the switch off and confirm the list and dots disappear.
- On a clean install, turn on **Local Network Features** for the first time. The automatic first scan never port-scans, so its scan line should show Bonjour only.
- Pick **Common Web Apps** in **Settings › Local Network › Port Scan**. Confirm the sheet shows the right address range, the 22 ports, and the connection count, and that **Cancel** reverts the picker. Choose it again and tap **Confirm**.
- After confirming, tap **Scan Again**. Progress should appear with a **Cancel** button, and web apps that don’t advertise over Bonjour should be listed with a “port scan” tag. Relaunch the app: the saved results should appear with their scan time, and no new scan should start. Start another scan and tap **Cancel** partway through. The previous list should remain.
- Rename a device from Page Info (ⓘ), then rename one from a bookmark’s long-press menu with **Rename Device…**. Confirm every bookmark on that host updates. Tap **+** on a discovered device and confirm the new bookmark uses a `.local` URL.
- To test discovery without a home server, use the test fixture described below.

## Downloads

- Download a file, choose an **On My iPhone/iPad** or **iCloud Drive** destination, and open it in Files. Download the same name twice to check the system’s conflict handling. Cancel a Save to Files picker and verify browsing still works.
- Test a failed download, a file from a logged-in service if available, and multiple downloads. Each successful download should get its own destination picker.

## Test fixture

`Tests/serve_fixture.py` is a small local server for redirects, download links, attachment responses, blob downloads, new-window links, and JavaScript dialogs. It serves only generated test pages and files.

```sh
python3 Tests/serve_fixture.py
```

Keep Terminal running and, from another device on the same Wi-Fi such as an iPhone or iPad, open `http://YOUR_MAC_LAN_IP:8889/`. Allow incoming connections if macOS asks. Stop the server with Control-C.

To test discovery without a home server, advertise the fixture from the Mac over Bonjour:

```sh
dns-sd -R "LAN Fixture" _http._tcp local 8889
```

After a scan with **Local Network Features** on, the fixture should appear in **On This Network**.

## iPad

- At full width, such as landscape or the full iPad window, check the top bar: Back and Forward on the left, the address field in the middle, and Reload, Page Info, Bookmarks and Tabs on the right. The bottom toolbar should not appear. On the bookmark list, **Edit** sits next to Back and Forward, and **+** and **Settings** are on the right.
- Open Split View or Slide Over with another app. Confirm the bottom toolbar returns and the address text you entered is still there. Return to full width and confirm the top bar comes back.
- Rotate through all four orientations, including upside down, with a page loaded and with the bookmark list showing. Check that the layout fits and the top bar or bottom toolbar stays usable.
- With a hardware keyboard, try each shortcut: ⌘L, ⌘T, ⌘W, ⌘R, ⌘., ⌘[, ⌘], ⌘D, ⌘⇧\, and ⌘,. Confirm each does what its name says.
- Open the tab overview with several tabs. It should show more columns than on iPhone.
- Open Page Info, Settings, the bookmark editor and the rename alert. Check that the sheets and alerts fit the iPad width and look right in light and dark mode.

## Mac (Designed for iPad, Apple silicon)

Run the app on a Mac with Apple silicon. Intel Macs are not supported. In Xcode, choose **My Mac (Designed for iPad)** as the run destination and press **⌘R**.

- Launch the app and confirm the top bar shows at full width.
- Turn on **Local Network Features**. Confirm the Local Network prompt appears once. Then deny access in **System Settings › Privacy & Security › Local Network**, open a local address with **Why can’t I connect?**, and confirm the advice points to that System Settings path. The advice should have no **Open Settings** button. Turn access back on in System Settings.
- With the fixture server and `dns-sd` running as described above, use **Scan Again** from the On This Network ••• menu. Confirm **LAN Fixture** appears in **On This Network**. There is no pull down on a Mac.
- With both Ethernet and Wi-Fi connected, choose **Common Web Apps** in **Settings › Local Network › Port Scan** and open the confirmation sheet. Confirm the address range is the home network you expect. Compare it with the addresses shown for Ethernet and Wi-Fi in **System Settings › Network**.
- Open a self-signed HTTPS device on your network. Confirm the page opens with the red “!” strip, and that the certificate sheet shows its SHA-256 fingerprint.
- Download a file and confirm the Save to Files panel appears. Choose a folder, then check that the file saved there.
- With two or more tabs, press ⌘W and confirm it closes the current tab, not the window. With one tab, confirm the window behavior is what you expect. Check the other shortcuts from the iPad list above.
- Resize the window narrow, such as beside another window, and confirm the bottom toolbar appears. Widen it again and confirm the top bar returns.
- After adding a bookmark and opening a few tabs, check the app data in `~/Library/Containers/com.jesse.lanbrowser/Data/Library/Application Support/LANBrowser/`. The files there include `bookmarks.json` and `tabs.json`.

## Saved passwords

- Focus website username and other text fields on iPhone and iPad: the first character must not be capitalized automatically. Repeat in a dynamically inserted form, an embedded frame, a JavaScript prompt and the native bookmark-title and rename fields. Manually using Shift must still allow capitals, and existing field values must remain unchanged.
Run `node Tests/password_capture_checks.js` and `node Tests/password_autofill_checks.js` for the form-detection and AutoFill checks (no packages required). The fixture’s **Password saving** link opens a POST login form that discards submitted values and redirects back to itself; use made-up credentials.

- On a fresh install, confirm **Settings > Offer to Save Passwords** is on. Submit a standard username/password login over HTTP, HTTPS and self-signed local HTTPS. Confirm **Save Password?** identifies the original scheme, host, port and username, including when the login redirects immediately.
- Choose **Not Now** and check **Saved Passwords** stays empty. Submit again and choose **Save**. Relaunch; reveal the saved entry and verify both values. Change the password and save again; confirm the entry is updated. Submit unchanged credentials again; the offer must appear again.
- With an existing saved login, submit a different password for the same username and address, then choose **Not Now**. Relaunch and reveal the saved entry: the old password must remain. Repeat and choose **Save**: the new password must replace it. A different username at the same address saves as a separate account and leaves the old account intact.
- Submit using the keyboard, a normal submit button and a form-less JavaScript login button. A click and its submit event must produce one prompt. Test dynamically inserted forms and a new-window tab. Embedded frames, HTTP authentication dialogs and some custom forms are unsupported.
- Test password-only forms, email usernames, Unicode credentials, IPv6 hosts and two accounts on the same service. HTTP/HTTPS and different ports must keep distinct entries. Empty passwords and new-password or multi-password registration forms must not offer to save.
- Toggle **Offer to Save Passwords** off, return to an already loaded page and submit: no offer. Relaunch and confirm it stays off. Turn it on again and retry. Previously saved entries must remain.
- Reveal a password, background the app and return: it must be hidden. Delete an entry using its swipe action and relaunch: it must be gone. Clear website data and confirm saved passwords remain. Confirm credentials do not appear in the app’s JSON files or preferences.
- Verify a background tab cannot trigger an offer, changing tabs or backgrounding dismisses a pending offer, and site scripts cannot call the isolated password bridge. Confirm that filling only occurs in the selected foreground tab, for the exact saved scheme, host and port.
- Check the save alert and Saved Passwords on iPhone and iPad with larger text and on Mac (Designed for iPad). Check failed Keychain operations show an error rather than claiming a save succeeded.

- With **AutoFill Saved Passwords** on (the default), save made-up credentials, leave the login page and return. Confirm both fields fill automatically on HTTP, HTTPS and a self-signed local HTTPS page; the form must not submit itself. Repeat after relaunch and with a dynamically inserted form.
- Save two usernames for one origin. A blank form should fill the most recently saved account. Enter the other saved username; its password should fill. An unknown username must not receive another account’s password. Changing an automatically filled username must clear its old automatic password. A password you type or clear manually must not be overwritten.
- Turn **AutoFill Saved Passwords** off and reload: fields must stay empty, while offers to save remain on. Turn save offers off independently: saved entries can still fill while AutoFill is on. Confirm embedded frames, hidden forms and registration forms do not receive credentials. Test a slow page load while typing and while navigating to a different host; a late reply must not overwrite input or cross origins.
- Debug builds emit fixed event names and Keychain status codes under subsystem `com.jesse.lanbrowser`, category `passwords`. No usernames, passwords, hosts or page text are included in these password diagnostics. `Tests/PasswordSaveChecks.swift` is a standalone simulator app that checks real Keychain writes, dismissal before Save, Not Now, replacements, native WebKit AutoFill, origin separation, the AutoFill setting and dynamically inserted forms. It uses a loopback fixture on port 8893.
