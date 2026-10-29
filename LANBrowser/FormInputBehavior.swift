import WebKit

@MainActor
enum FormInputBehavior {
    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: .defaultClient))
    }

    private static let script = #"""
    (() => {
      const selector = 'input, textarea, form, [contenteditable]';
      function configure(element) {
        if (element.getAttribute('autocapitalize') !== 'none') {
          element.setAttribute('autocapitalize', 'none');
        }
      }
      function scan(root) {
        if (root instanceof Element && root.matches(selector)) configure(root);
        root.querySelectorAll(selector).forEach(configure);
      }
      // Home web apps often insert their login forms after the initial document loads.
      new MutationObserver(records => {
        for (const record of records) {
          if (record.type === 'attributes') {
            if (record.target.matches(selector)) configure(record.target);
          } else {
            for (const node of record.addedNodes) {
              if (node instanceof Element) scan(node);
            }
          }
        }
      }).observe(document, {subtree: true, childList: true, attributes: true, attributeFilter: ['autocapitalize']});
      document.addEventListener('focus', event => {
        if (event.target instanceof Element && event.target.matches(selector)) configure(event.target);
      }, true);
      scan(document);
    })();
    """#
}
