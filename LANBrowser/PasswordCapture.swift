import WebKit

@MainActor
final class PasswordCapture: NSObject, WKScriptMessageHandler {
    private static let handler = PasswordCapture()
    private static let world = WKContentWorld.world(name: "LANBrowserPasswords")

    static func install(in controller: WKUserContentController) {
        controller.add(handler, contentWorld: world, name: "passwordSubmitted")
        #if DEBUG
        let source = "const __lanPasswordDebug = true;\n" + script
        #else
        let source = script
        #endif
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if let body = message.body as? [String: String], let event = body["diagnostic"] {
            // Only fixed event names are logged, never page-provided text or credential values.
            if ["installed", "submission", "skip-fields", "skip-empty", "skip-new-password"].contains(event) {
                PasswordDiagnostics.record("Form capture: \(event).")
            }
            return
        }
        PasswordDiagnostics.record("Credential submission received.")
        guard PasswordPolicy.isEnabled() else {
            PasswordDiagnostics.record("Submission ignored: password offers are disabled.")
            return
        }
        guard
              let tab = message.webView?.navigationDelegate as? BrowserTab,
              let session = tab.session, session.selectedID == tab.id,
              let url = message.frameInfo.request.url, let origin = PasswordOrigin(url),
              let body = message.body as? [String: String],
              let username = body["username"], let password = body["password"], !password.isEmpty,
              username.utf8.count <= 4096, password.utf8.count <= 65536 else {
            PasswordDiagnostics.record("Submission ignored: inactive tab or invalid message.")
            return
        }
        session.offerPassword(PasswordOffer(tabID: tab.id, origin: origin, username: username, password: password))
    }

    // An isolated world keeps the credential bridge out of reach of page scripts.
    static let script = #"""
    (() => {
      let lastTime = -Infinity;
      let lastRoot = null;
      function report(event) {
        if (typeof __lanPasswordDebug !== 'undefined' && __lanPasswordDebug) {
          window.webkit.messageHandlers.passwordSubmitted.postMessage({diagnostic: event});
        }
      }
      report('installed');
      function capture(root) {
        report('submission');
        const passwords = Array.from(root.querySelectorAll('input[type="password"]'))
          .filter(input => !input.disabled && input.getClientRects().length);
        if (passwords.length !== 1) { report('skip-fields'); return; }
        if (!passwords[0].value) { report('skip-empty'); return; }
        if (passwords[0].autocomplete === 'new-password') { report('skip-new-password'); return; }
        const password = passwords[0];
        const fields = Array.from(root.querySelectorAll('input'));
        const candidates = fields.filter(input => !input.disabled && input.type !== 'password' &&
          ['text', 'email', 'tel'].includes(input.type) && input.getClientRects().length);
        const username = candidates.find(input => input.autocomplete === 'username') ||
          candidates.filter(input => fields.indexOf(input) < fields.indexOf(password)).pop();
        const name = username ? username.value : '';
        const now = performance.now();
        // A click followed by its native submit event is one attempt, not two prompts.
        if (now - lastTime < 500 && lastRoot === root) return;
        lastTime = now; lastRoot = root;
        window.webkit.messageHandlers.passwordSubmitted.postMessage({username: name, password: password.value});
      }
      document.addEventListener('submit', event => {
        if (event.isTrusted) capture(event.target);
      }, true);
      document.addEventListener('keydown', event => {
        if (event.isTrusted && event.key === 'Enter' && event.target instanceof HTMLInputElement) {
          const form = event.target.form;
          if (!form || form.noValidate || form.checkValidity()) capture(form || document);
        }
      }, true);
      document.addEventListener('click', event => {
        if (!event.isTrusted || !(event.target instanceof Element)) return;
        const button = event.target.closest('button, input[type="submit"], [role="button"]');
        if (!button) return;
        // Formless login panels and type=button handlers are common in home web apps.
        if (button.form && button.type === 'submit') {
          if (button.form.noValidate || button.formNoValidate || button.form.checkValidity()) capture(button.form);
          return;
        }
        const label = [button.textContent, button.value, button.getAttribute('aria-label')].join(' ');
        if (/log.?in|sign.?in|submit|continue|connect|unlock/i.test(label)) capture(button.form || document);
      }, true);
    })();
    """#
}
