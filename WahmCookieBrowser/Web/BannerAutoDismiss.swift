import WebKit

/// Auto-accepts cookie-consent banners and dismisses app-install sheets.
/// Installed on each container's WKWebViewConfiguration (isolated data store),
/// at document start and end, in every frame.
enum BannerAutoDismiss {
    static func install(on configuration: WKWebViewConfiguration) {
        for time in [WKUserScriptInjectionTime.atDocumentStart, .atDocumentEnd] {
            let script = WKUserScript(
                source: javaScript,
                injectionTime: time,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        }
    }

    static let invokeJavaScript = "try { window.__wahmRunBannerAuto && window.__wahmRunBannerAuto(true); } catch (e) {}"

    static let javaScript = #"""
(function () {
  try {
    if (window.__wahmBannerAutoInstalled && window.__wahmRunBannerAuto) {
      window.__wahmRunBannerAuto(true);
      return;
    }
    window.__wahmBannerAutoInstalled = true;

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
      "كوكيز", "كوكيس", "consent", "privacy", "خصوصيتك", "سياسة الخصوصية",
      "هل تسمح"
    ];
    var KNOWN_ACCEPT = [
      "#onetrust-accept-btn-handler",
      ".onetrust-accept-btn-handler",
      "#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll",
      "#CybotCookiebotDialogBodyButtonAccept",
      "button[data-testid='cookie-policy-manage-dialog-accept-button']",
      "button[data-testid='cookie-policy-dialog-accept-button']",
      "button[data-cookiebanner='accept_button']",
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
      if (!st || st.display === "none" || st.visibility === "hidden" || Number(st.opacity) === 0) return false;
      var r = el.getBoundingClientRect();
      return r.width > 4 && r.height > 4;
    }
    function textOf(el) {
      return norm(
        (el.innerText || el.textContent || "") + " " +
        (el.getAttribute && (el.getAttribute("aria-label") || el.getAttribute("title") || "") || "") + " " +
        (el.value || "")
      );
    }
    function exactIn(text, list) {
      for (var i = 0; i < list.length; i++) {
        if (text === norm(list[i])) return true;
      }
      return false;
    }
    function containsAny(text, list) {
      for (var i = 0; i < list.length; i++) {
        var n = norm(list[i]);
        if (n && text.indexOf(n) !== -1) return true;
      }
      return false;
    }
    function click(el) {
      if (!el) return false;
      try { el.scrollIntoView({ block: "center", inline: "center" }); } catch (e) {}
      try { if (el.focus) el.focus(); } catch (e2) {}
      var opts = { bubbles: true, cancelable: true, view: window, composed: true, buttons: 1 };
      var types = ["pointerover","mouseover","pointerdown","mousedown","pointerup","mouseup","click"];
      for (var i = 0; i < types.length; i++) {
        try {
          var t = types[i];
          var ev;
          if (t.indexOf("pointer") === 0 && window.PointerEvent) {
            ev = new PointerEvent(t, Object.assign({ pointerId: 1, pointerType: "touch", isPrimary: true }, opts));
          } else {
            ev = new MouseEvent(t, opts);
          }
          el.dispatchEvent(ev);
        } catch (e3) {}
      }
      try { if (el.click) el.click(); } catch (e4) {}
      return true;
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
    function allElements(root) {
      return allDeep("*", root);
    }
    function inCookieContext(el) {
      var node = el;
      for (var i = 0; i < 12 && node && node !== document; i++) {
        var blob = (
          ((node.innerText || node.textContent || "") + "").slice(0, 2000) + " " +
          (node.id || "") + " " + (node.className || "") + " " +
          (node.getAttribute && (node.getAttribute("role") || "") || "")
        ).toLowerCase();
        if (containsAny(blob, COOKIE_HINTS) || /onetrust|cookiebot|consent-banner|cookie-banner|cookieconsent|gdpr|tiktok-cookie/.test(blob)) {
          return true;
        }
        node = node.parentElement || (node.getRootNode && node.getRootNode().host) || null;
      }
      return false;
    }
    function pageMentionsCookies() {
      var t = ((document.body && document.body.innerText) || "").slice(0, 12000).toLowerCase();
      return containsAny(t, COOKIE_HINTS);
    }
    function bannerStillVisible() {
      var t = ((document.body && document.body.innerText) || "").slice(0, 12000);
      var n = norm(t);
      if (!n) return false;
      if (containsAny(n, ACCEPT_PREFERRED) && containsAny(n, COOKIE_HINTS)) return true;
      if (n.indexOf("هل تسمح") !== -1 && (n.indexOf("السماح") !== -1 || n.indexOf("رفض") !== -1)) return true;
      return false;
    }

    function clickKnownAccept() {
      for (var i = 0; i < KNOWN_ACCEPT.length; i++) {
        var els = allDeep(KNOWN_ACCEPT[i]);
        for (var j = 0; j < els.length; j++) {
          if (visible(els[j])) { click(els[j]); return true; }
        }
      }
      return false;
    }

    function clickAcceptByText() {
      var els = allElements();
      var preferred = [];
      var generic = [];
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (!visible(el)) continue;
        var t = textOf(el);
        if (!t || t.length > 64) continue;
        var isPref = exactIn(t, ACCEPT_PREFERRED) || containsAny(t, ACCEPT_PREFERRED);
        var isGen = exactIn(t, ACCEPT);
        if (!isPref && !isGen) continue;
        if (isPref) {
          preferred.push(el);
        } else if (inCookieContext(el) || pageMentionsCookies()) {
          generic.push(el);
        }
      }
      var list = preferred.concat(generic);
      for (var k = 0; k < list.length; k++) {
        click(list[k]);
        return true;
      }
      return false;
    }

    function clickContinueOnWeb() {
      var els = allElements();
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (!visible(el)) continue;
        var t = textOf(el);
        if (!t || t.length > 72) continue;
        if (exactIn(t, CONTINUE_WEB) || containsAny(t, CONTINUE_WEB)) {
          click(el);
          return true;
        }
      }
      return false;
    }

    function looksLikeInstallBanner() {
      var t = norm(((document.body && document.body.innerText) || "").slice(0, 9000));
      return containsAny(t, OPEN_APP) || containsAny(t, CONTINUE_WEB);
    }

    function isProtected(el) {
      if (!el || el === document.body || el === document.documentElement) return true;
      var id = (el.id || "").toLowerCase();
      if (id === "app" || id === "root" || id === "main" || id === "tiktok-app") return true;
      var tag = (el.tagName || "").toLowerCase();
      if (tag === "main" || tag === "html" || tag === "body") return true;
      return false;
    }

    function hideNode(el) {
      if (!el || isProtected(el)) return false;
      try {
        el.style.setProperty("display", "none", "important");
        el.style.setProperty("visibility", "hidden", "important");
        el.style.setProperty("pointer-events", "none", "important");
        el.style.setProperty("opacity", "0", "important");
        el.setAttribute("aria-hidden", "true");
        if (el.parentNode) el.parentNode.removeChild(el);
        return true;
      } catch (e) {
        try { el.style.display = "none"; return true; } catch (e2) { return false; }
      }
    }

    function unlockPage() {
      try {
        document.documentElement.style.setProperty("overflow", "auto", "important");
        document.body.style.setProperty("overflow", "auto", "important");
        document.documentElement.style.setProperty("pointer-events", "auto", "important");
        document.body.style.setProperty("pointer-events", "auto", "important");
        document.documentElement.classList.remove("modal-open", "no-scroll", "noscroll");
        document.body.classList.remove("modal-open", "no-scroll", "noscroll");
      } catch (e) {}
    }

    function collectOverlayCandidates() {
      var found = [];
      var seen = {};
      function consider(el) {
        if (!el || isProtected(el) || seen[el]) return;
        seen[el] = true;
        var st;
        try { st = window.getComputedStyle(el); } catch (e) { return; }
        if (!st) return;
        var pos = st.position;
        var r = el.getBoundingClientRect();
        var large = r.width * r.height > window.innerWidth * window.innerHeight * 0.2
          || (r.width >= window.innerWidth * 0.7 && r.height >= window.innerHeight * 0.25)
          || (r.top <= 16 && r.left <= 16 && r.width >= window.innerWidth - 32 && r.height >= window.innerHeight - 32);
        var blob = norm(((el.innerText || el.textContent || "") + " " + (el.id || "") + " " + (el.className || "")).slice(0, 2500));
        var cookieish = containsAny(blob, COOKIE_HINTS) || containsAny(blob, ACCEPT_PREFERRED) || blob.indexOf("رفض") !== -1 || blob.indexOf("decline") !== -1 || blob.indexOf("هل تسمح") !== -1;
        var installish = containsAny(blob, OPEN_APP) || containsAny(blob, CONTINUE_WEB);
        var named = /cookie|consent|gdpr|onetrust|cookiebot|banner|install|interstitial/.test(((el.id || "") + " " + (el.className || "")).toLowerCase());
        if ((cookieish || installish || named) && (pos === "fixed" || pos === "sticky" || pos === "absolute" || large || named)) {
          found.push(el);
        }
      }
      var explicit = [];
      try {
        explicit = allDeep("[class*='cookie'], [id*='cookie'], [class*='Cookie'], [id*='Cookie'], [class*='consent'], [id*='consent'], [class*='Consent'], [class*='banner'], [id*='banner']");
      } catch (e) {}
      for (var i = 0; i < explicit.length; i++) consider(explicit[i]);
      if (document.body) {
        var kids = document.body.children;
        for (var k = 0; k < kids.length; k++) {
          consider(kids[k]);
          var grand = kids[k].children;
          for (var g = 0; g < grand.length; g++) consider(grand[g]);
        }
      }
      return found;
    }

    function forceRemoveOverlays() {
      var removed = false;
      var candidates = collectOverlayCandidates();
      for (var i = 0; i < candidates.length; i++) {
        if (hideNode(candidates[i])) removed = true;
      }
      if (removed) unlockPage();
      return removed;
    }

    var clickAttempts = 0;
    var removed = false;

    function run(forceRemove) {
      try {
        clickKnownAccept();
        clickAcceptByText();
        clickContinueOnWeb();
        clickAttempts += 1;
        if (forceRemove || clickAttempts >= 6) {
          if (bannerStillVisible() || looksLikeInstallBanner()) {
            if (forceRemoveRemoveSafe()) removed = true;
          }
        }
      } catch (e) {}
    }

    function forceRemoveRemoveSafe() {
      return forceRemoveOverlays();
    }

    window.__wahmRunBannerAuto = function (force) {
      run(!!force && clickAttempts >= 4);
    };

    run(false);
    var ticks = 0;
    var timer = setInterval(function () {
      ticks += 1;
      run(ticks >= 8);
      if (ticks >= 24) {
        clearInterval(timer);
        if (bannerStillVisible() || looksLikeInstallBanner()) forceRemoveOverlays();
      }
    }, 500);

    var scheduled = false;
    try {
      var obs = new MutationObserver(function () {
        if (scheduled) return;
        scheduled = true;
        setTimeout(function () { scheduled = false; run(false); }, 60);
      });
      if (document.documentElement) {
        obs.observe(document.documentElement, { childList: true, subtree: true });
      }
    } catch (e) {}
    document.addEventListener("DOMContentLoaded", function () { run(false); });
  } catch (err) {}
})();
"""#
}
