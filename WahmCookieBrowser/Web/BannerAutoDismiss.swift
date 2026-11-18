import WebKit

/// Injects a user script that auto-accepts common cookie-consent banners
/// and prefers "continue in browser" over app-install interstitials.
enum BannerAutoDismiss {
    static func install(on configuration: WKWebViewConfiguration) {
        let script = WKUserScript(
            source: javaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(script)
    }

    /// Called again after each finished navigation as a safety net.
    static let invokeJavaScript = "try { window.__wahmRunBannerAuto && window.__wahmRunBannerAuto(); } catch (e) {}"

    static let javaScript = #"""
(function () {
  try {
    if (window.__wahmBannerAutoInstalled) {
      if (window.__wahmRunBannerAuto) window.__wahmRunBannerAuto();
      return;
    }
    window.__wahmBannerAutoInstalled = true;

    var href = (location.href || "").toLowerCase();
    var isTop = (window === window.top);
    var isConsentFrame = /consent|cookie|privacymanager|onetrust|cmp\./.test(href);
    if (!isTop && !isConsentFrame) return;

    var ACCEPT = [
      "السماح للكل", "السماح للجميع", "السماح",
      "قبول الكل", "قبول الجميع", "قبول",
      "موافق", "أوافق",
      "allow all", "allow all cookies", "accept all", "accept all cookies",
      "accept cookies", "i agree", "i accept", "agree", "allow cookies",
      "allow", "accept"
    ];
    var ACCEPT_PREFERRED = [
      "السماح للكل", "السماح للجميع", "قبول الكل", "قبول الجميع",
      "allow all", "allow all cookies", "accept all", "accept all cookies"
    ];
    var CONTINUE_WEB = [
      "المتابعة في المتصفح", "المتابعه في المتصفح", "المتابعة على الويب",
      "استمر في المتصفح", "الاستمرار في المتصفح", "تبقى في المتصفح",
      "متابعة بدون التطبيق", "استخدم المتصفح",
      "continue on web", "continue on the web", "continue in browser",
      "continue in the browser", "open in browser", "stay in browser",
      "use the website", "use website", "not now", "no thanks",
      "ليس الآن", "ليس الان", "لا شكراً", "لا شكرا", "لاحقاً", "لاحقا"
    ];
    var OPEN_APP = [
      "فتح التطبيق", "افتح التطبيق", "فتح في التطبيق", "تنزيل التطبيق",
      "open app", "open in app", "get the app", "use the app",
      "download the app", "open tiktok", "open instagram", "open youtube",
      "open snapchat"
    ];
    var COOKIE_HINTS = [
      "cookie", "cookies", "ملفات تعريف الارتباط", "ملفات تعريف",
      "كوكيز", "كوكيس", "consent", "privacy", "خصوصيتك", "سياسة الخصوصية"
    ];
    var KNOWN_ACCEPT = [
      "#onetrust-accept-btn-handler",
      ".onetrust-accept-btn-handler",
      "#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll",
      "#CybotCookiebotDialogBodyButtonAccept",
      "button[data-testid='cookie-policy-manage-dialog-accept-button']",
      "button[data-testid='cookie-policy-dialog-accept-button']",
      "button[data-cookiebanner='accept_button']",
      "button[data-cookiebanner='accept_only_essential_button']",
      "button[aria-label='Accept all']",
      "button[aria-label='Allow all']",
      "button[aria-label='السماح للكل']",
      "button[aria-label='قبول الكل']",
      "button[data-e2e='cookie-banner-accept']",
      "#L2AGLb",
      "button#introAgreeButton",
      "#accept-cookies",
      "button#accept-all-cookies",
      ".js-accept-cookies"
    ];

    function norm(s) {
      return String(s || "").replace(/\s+/g, " ").trim().toLowerCase();
    }
    function visible(el) {
      if (!el || el.nodeType !== 1) return false;
      var st = window.getComputedStyle(el);
      if (!st || st.display === "none" || st.visibility === "hidden" || st.opacity === "0") return false;
      var r = el.getBoundingClientRect();
      return r.width > 8 && r.height > 8;
    }
    function textOf(el) {
      return norm(
        (el.innerText || el.textContent || "") + " " +
        (el.getAttribute("aria-label") || "") + " " +
        (el.value || "")
      );
    }
    function click(el) {
      if (!el || !visible(el)) return false;
      try { el.click(); return true; } catch (e) {}
      try {
        el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
        return true;
      } catch (e2) { return false; }
    }
    function allDeep(selector, root) {
      root = root || document;
      var out = [];
      function walk(node) {
        if (!node) return;
        if (node.querySelectorAll) {
          try { out.push.apply(out, node.querySelectorAll(selector)); } catch (e) {}
        }
        var els = node.querySelectorAll ? node.querySelectorAll("*") : [];
        for (var i = 0; i < els.length; i++) {
          if (els[i].shadowRoot) walk(els[i].shadowRoot);
        }
      }
      walk(root);
      return out;
    }
    function inCookieContext(el) {
      var node = el;
      for (var i = 0; i < 10 && node && node !== document; i++) {
        var blob = (
          (node.innerText || node.textContent || "").slice(0, 1500) + " " +
          (node.id || "") + " " + (node.className || "") + " " +
          (node.getAttribute && (node.getAttribute("role") || "") || "")
        ).toLowerCase();
        for (var h = 0; h < COOKIE_HINTS.length; h++) {
          if (blob.indexOf(COOKIE_HINTS[h]) !== -1) return true;
        }
        if (/onetrust|cookiebot|consent-banner|cookie-banner|cookieconsent|gdpr/.test(blob)) return true;
        node = node.parentElement || (node.getRootNode && node.getRootNode().host) || null;
      }
      return false;
    }
    function pageMentionsCookies() {
      var t = ((document.body && document.body.innerText) || "").slice(0, 9000).toLowerCase();
      for (var i = 0; i < COOKIE_HINTS.length; i++) {
        if (t.indexOf(COOKIE_HINTS[i]) !== -1) return true;
      }
      return false;
    }
    function exactIn(text, list) {
      for (var i = 0; i < list.length; i++) {
        if (text === norm(list[i])) return true;
      }
      return false;
    }

    var accepted = false;
    var continued = false;

    function clickKnownAccept() {
      for (var i = 0; i < KNOWN_ACCEPT.length; i++) {
        var els = allDeep(KNOWN_ACCEPT[i]);
        for (var j = 0; j < els.length; j++) {
          if (click(els[j])) return true;
        }
      }
      return false;
    }

    function clickAcceptByText() {
      if (!pageMentionsCookies()) return false;
      var els = allDeep("button, [role='button'], input[type='button'], input[type='submit'], a");
      var fallback = null;
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (!visible(el)) continue;
        var t = textOf(el);
        if (!t || t.length > 48) continue;
        if (!exactIn(t, ACCEPT)) continue;
        if (el.closest && el.closest("form") && !inCookieContext(el)) continue;
        if (!inCookieContext(el) && !pageMentionsCookies()) continue;
        if (exactIn(t, ACCEPT_PREFERRED)) {
          if (click(el)) return true;
        } else if (!fallback && inCookieContext(el)) {
          fallback = el;
        }
      }
      return !!(fallback && click(fallback));
    }

    function looksLikeInstallBanner() {
      var t = ((document.body && document.body.innerText) || "").toLowerCase();
      return (
        t.indexOf("فتح التطبيق") !== -1 ||
        t.indexOf("افتح التطبيق") !== -1 ||
        t.indexOf("open app") !== -1 ||
        t.indexOf("open in app") !== -1 ||
        t.indexOf("get the app") !== -1 ||
        t.indexOf("المتابعة في المتصفح") !== -1 ||
        t.indexOf("continue on web") !== -1 ||
        t.indexOf("continue in browser") !== -1
      );
    }

    function clickContinueOnWeb() {
      var els = allDeep("button, [role='button'], a, span");
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (!visible(el)) continue;
        var t = textOf(el);
        if (!t || t.length > 64) continue;
        if (exactIn(t, CONTINUE_WEB)) {
          if (click(el)) return true;
        }
      }
      return false;
    }

    function closeInstallInterstitial() {
      if (clickContinueOnWeb()) return true;
      if (!looksLikeInstallBanner()) return false;
      var closeSels = [
        "button[aria-label='Close']",
        "button[aria-label='close']",
        "button[aria-label='إغلاق']",
        "button[aria-label='اغلاق']",
        "[data-e2e='modal-close-inner-button']",
        "[data-e2e='modal-close-button']"
      ];
      for (var i = 0; i < closeSels.length; i++) {
        var els = allDeep(closeSels[i]);
        for (var j = 0; j < els.length; j++) {
          if (click(els[j])) return true;
        }
      }
      return false;
    }

    function run() {
      try {
        if (!accepted) accepted = clickKnownAccept() || clickAcceptByText();
        if (!continued) continued = closeInstallInterstitial();
      } catch (e) {}
    }

    window.__wahmRunBannerAuto = run;

    [0, 200, 500, 1000, 2000, 3500, 6000].forEach(function (d) {
      setTimeout(run, d);
    });

    var scheduled = false;
    var obs = new MutationObserver(function () {
      if (scheduled) return;
      scheduled = true;
      setTimeout(function () { scheduled = false; run(); }, 80);
    });
    if (document.documentElement) {
      obs.observe(document.documentElement, { childList: true, subtree: true });
    }
    document.addEventListener("DOMContentLoaded", run);
  } catch (err) {}
})();
"""#
}
