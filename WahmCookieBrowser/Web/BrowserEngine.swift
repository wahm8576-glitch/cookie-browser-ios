import Foundation
import WebKit

@MainActor
final class BrowserEngine: NSObject, ObservableObject {
    let webView: WKWebView
    let containerID: UUID

    @Published var addressText: String = ""
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var pageTitle: String = ""
    @Published var currentURL: URL?

    private var observations: [NSKeyValueObservation] = []

    init(containerID: UUID, initialURL: URL? = nil) {
        self.containerID = containerID

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: containerID)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = BrowserEngine.safariUserAgent
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.progress = view.estimatedProgress
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.isLoading = view.isLoading
                    if !view.isLoading {
                        self?.progress = 0
                    }
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.canGoBack = view.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.canGoForward = view.canGoForward
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.pageTitle = view.title ?? ""
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.updateCurrentURL(view.url)
                }
            }
        ]

        if let initialURL {
            addressText = initialURL.absoluteString
            load(url: initialURL)
        }
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    func submitAddress() {
        guard let url = Self.normalizedURL(from: addressText) else { return }
        addressText = url.absoluteString
        load(url: url)
    }

    func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func injectCookies(_ parsed: [ParsedCookie]) async -> Int {
        let fallback = currentURL?.host ?? Self.host(from: addressText)
        let store = webView.configuration.websiteDataStore.httpCookieStore
        var applied = 0
        for cookie in parsed {
            if let httpCookie = cookie.asHTTPCookie(fallbackDomain: fallback) {
                await store.setCookie(httpCookie)
                applied += 1
            }
        }
        return applied
    }

    func reloadAfterCookieInjection() {
        if let url = currentURL ?? Self.normalizedURL(from: addressText) {
            // A fresh request after cookies are in the store is more reliable than a simple reload.
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        } else {
            webView.reloadFromOrigin()
        }
    }

    private func updateCurrentURL(_ url: URL?) {
        currentURL = url
        if let url, !isLoading || addressText.isEmpty || !addressTextContainsDraft() {
            addressText = url.absoluteString
        } else if let url {
            addressText = url.absoluteString
        }
    }

    private func addressTextContainsDraft() -> Bool {
        false
    }

    static func host(from address: String) -> String? {
        normalizedURL(from: address)?.host
    }

    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()), url.host != nil {
            return url
        }

        var candidate = trimmed
        if candidate.hasPrefix("//") {
            candidate = "https:" + candidate
        } else if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let url = URL(string: candidate), let host = url.host, host.contains(".") || host == "localhost" else {
            return nil
        }
        return url
    }

    private static var safariUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    }
}

extension BrowserEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateCurrentURL(webView.url)
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data"].contains(scheme) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension BrowserEngine: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(defaultText)
    }
}
