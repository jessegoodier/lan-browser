import UIKit
import WebKit

@MainActor
final class PasswordAutofill: NSObject, WKScriptMessageHandlerWithReply {
    private static let handler = PasswordAutofill()
    private static let world = WKContentWorld.world(name: "LANBrowserPasswords")

    static func install(in controller: WKUserContentController) {
        controller.addScriptMessageHandler(handler, contentWorld: world, name: "passwordFill")
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard PasswordPolicy.autofillEnabled(), UIApplication.shared.applicationState == .active,
              message.frameInfo.isMainFrame,
              let webView = message.webView, let tab = webView.navigationDelegate as? BrowserTab,
              tab.session?.selectedID == tab.id,
              let frameURL = message.frameInfo.request.url, let origin = PasswordOrigin(frameURL),
              webView.url.flatMap(PasswordOrigin.init) == origin,
              let body = message.body as? [String: String], let username = body["username"],
              username.utf8.count <= 4096 else { replyHandler(nil, nil); return }
        do {
            guard let saved = PasswordPolicy.accountToFill(try PasswordStore.list(), origin: origin, username: username) else {
                replyHandler(nil, nil)
                return
            }
            let password = try PasswordStore.password(for: saved)
            PasswordDiagnostics.record("Saved login supplied to matching main-frame form.")
            replyHandler(["username": saved.username, "password": password], nil)
        } catch {
            PasswordDiagnostics.record("AutoFill Keychain read failed: \((error as NSError).code).")
            replyHandler(nil, nil)
        }
    }

    static let script = #"""
    (() => {
      const pending = new WeakSet();
      const filled = new WeakMap();
      const editedPasswords = new WeakSet();
      let timer;
      function setValue(input, value) {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
        input.dispatchEvent(new Event('input', {bubbles: true}));
        input.dispatchEvent(new Event('change', {bubbles: true}));
      }
      function loginFields(password) {
        if (password.type !== 'password' || password.disabled || password.readOnly ||
            password.autocomplete === 'new-password' || !password.getClientRects().length) return null;
        const root = password.form || document;
        const passwords = Array.from(root.querySelectorAll('input[type="password"]'))
          .filter(input => !input.disabled && input.getClientRects().length);
        if (passwords.length !== 1) return null;
        const inputs = Array.from(root.querySelectorAll('input'));
        const candidates = inputs.filter(input => !input.disabled && !input.readOnly &&
          ['text', 'email', 'tel'].includes(input.type) && input.getClientRects().length);
        const username = candidates.find(input => input.autocomplete === 'username') ||
          candidates.filter(input => inputs.indexOf(input) < inputs.indexOf(password)).pop();
        return {username, password};
      }
      async function fill(password) {
        const fields = loginFields(password);
        if (!fields || password.value || editedPasswords.has(password) || pending.has(password)) return;
        const username = fields.username;
        const name = username ? username.value : '';
        const origin = location.origin;
        pending.add(password);
        try {
          const saved = await window.webkit.messageHandlers.passwordFill.postMessage({username: name});
          // A reply must never overwrite typing or be applied to a replaced form or another page.
          const current = loginFields(password);
          if (!saved || location.origin !== origin || !password.isConnected || !current || current.username !== username ||
              password.value || editedPasswords.has(password) || (username && (!username.isConnected || username.value !== name)) ||
              (name && saved.username !== name)) return;
          if (username && !name) setValue(username, saved.username);
          // Username input handlers can replace the form or supply their own password.
          if (!password.isConnected || password.value || (username && username.value !== saved.username)) return;
          setValue(password, saved.password);
          filled.set(password, {username, value: saved.password});
        } catch (_) {
          // Missing or locked Keychain entries leave the page available for manual sign-in.
        } finally {
          pending.delete(password);
        }
      }
      function scan() {
        if (document.visibilityState !== 'visible') return;
        document.querySelectorAll('input[type="password"]').forEach(fill);
      }
      function schedule() {
        clearTimeout(timer);
        timer = setTimeout(scan, 100);
      }
      document.addEventListener('input', event => {
        if (!event.isTrusted) return;
        if (event.target instanceof HTMLInputElement && event.target.type === 'password') {
          editedPasswords.add(event.target);
        } else {
          for (const password of document.querySelectorAll('input[type="password"]')) {
            const previous = filled.get(password);
            if (previous && previous.username === event.target) {
              if (password.value === previous.value) setValue(password, '');
              filled.delete(password);
            }
          }
          schedule();
        }
      }, true);
      new MutationObserver(schedule).observe(document, {
        subtree: true, childList: true, attributes: true,
        attributeFilter: ['type', 'autocomplete', 'hidden', 'style', 'class', 'disabled', 'readonly']
      });
      document.addEventListener('DOMContentLoaded', schedule);
      document.addEventListener('visibilitychange', schedule);
      document.addEventListener('focusin', schedule);
      window.addEventListener('pageshow', schedule);
      schedule();
    })();
    """#
}
