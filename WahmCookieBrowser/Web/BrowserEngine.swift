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
    @Published var lastErrorMessage: String?
    @Published var showLoadError: Bool = false

    private var observations: [NSKeyValueObservation] = []
    private var loadGeneration = 0
    private var finishedGeneration = 0
    private var lastNavigationFailed = false
    private var didCommitCurrentLoad = false
    private var loadWaiters: [LoadWaiter] = []

    private struct LoadWaiter {
        let generation: Int
        var continuation: CheckedContinuation<URL?, Never>?
    }

    init(containerID: UUID, initialURL: URL? = nil) {
        self.containerID = containerID

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: containerID)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = BrowserEngine.safariUserAgent
        if #available(iOS 16.4, *) {
            webView.isInspectable = false
        }
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
                        self?.progress = 1
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

    @discardableResult
    func submitAddress() -> Bool {
        let url = Self.normalizedURL(from: addressText)
        guard let url else { return false }
        addressText = displayAddress(for: url)
        lastErrorMessage = nil
        load(url: url)
        return true
    }

    func load(url: URL) {
        lastErrorMessage = nil
        showLoadError = false
        lastNavigationFailed = false
        didCommitCurrentLoad = false
        loadGeneration += 1
        addressText = displayAddress(for: url)
        isLoading = true
        progress = 0.05
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        webView.load(request)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
            isLoading = false
        } else if let url = currentURL ?? Self.normalizedURL(from: addressText) {
            load(url: url)
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
        lastErrorMessage = nil
        showLoadError = false
        lastNavigationFailed = false
        didCommitCurrentLoad = false
        loadGeneration += 1
        isLoading = true
        progress = 0.05
        if let url = currentURL ?? Self.normalizedURL(from: addressText) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView.load(request)
        } else {
            webView.reloadFromOrigin()
        }
    }

    /// Waits until the current navigation finishes, fails, or times out.
    func waitForNavigation(timeout: TimeInterval = 15) async -> URL? {
        try? await Task.sleep(for: .milliseconds(120))
        let generation = loadGeneration
        if finishedGeneration == generation && !webView.isLoading {
            return webView.url ?? currentURL
        }
        return await withCheckedContinuation { continuation in
            loadWaiters.append(LoadWaiter(generation: generation, continuation: continuation))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.completeWaiters(generation: generation, url: self.webView.url ?? self.currentURL)
            }
        }
    }

    var navigationDidFail: Bool { lastNavigationFailed }

    static func looksLikeLoginPage(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let segments = Set(path.split(separator: "/").map { String($0) })
        let loginSegments: Set<String> = [
            "login", "log-in", "signin", "sign-in", "signup", "sign-up",
            "auth", "oauth", "authenticate", "authentication",
            "accounts", "account-login", "session", "sessions"
        ]
        if !segments.isDisjoint(with: loginSegments) {
            return true
        }
        let hostPrefix = host.split(separator: ":").first.map(String.init) ?? host
        if hostPrefix.hasPrefix("accounts.")
            || hostPrefix.hasPrefix("login.")
            || hostPrefix.hasPrefix("signin.")
            || hostPrefix.hasPrefix("auth.")
            || hostPrefix.hasPrefix("sso.") {
            return true
        }
        return false
    }

    func suggestedURLFromCookies(_ cookies: [ParsedCookie]) -> URL? {
        if let currentURL { return currentURL }
        if let fromAddress = Self.normalizedURL(from: addressText), !Self.isSearchURL(fromAddress) {
            return fromAddress
        }
        for cookie in cookies {
            guard var domain = cookie.domain, !domain.isEmpty else { continue }
            if domain.hasPrefix(".") { domain.removeFirst() }
            if let url = URL(string: "https://\(domain)") { return url }
        }
        return nil
    }

    private func displayAddress(for url: URL) -> String {
        url.absoluteString
    }

    private func updateCurrentURL(_ url: URL?) {
        guard let url, url.scheme != "about" else { return }
        currentURL = url
        if !addressTextIsBeingEdited() {
            addressText = url.absoluteString
        }
    }

    private func addressTextIsBeingEdited() -> Bool {
        false
    }

    private func completeWaiters(generation: Int, url: URL?) {
        for index in loadWaiters.indices.reversed() {
            guard loadWaiters[index].generation == generation else { continue }
            if let continuation = loadWaiters[index].continuation {
                loadWaiters[index].continuation = nil
                continuation.resume(returning: url)
            }
            loadWaiters.remove(at: index)
        }
    }

    private func markNavigationFinished(failed: Bool) {
        finishedGeneration = loadGeneration
        lastNavigationFailed = failed
        isLoading = false
        if !failed { lastErrorMessage = nil }
        completeWaiters(generation: loadGeneration, url: webView.url ?? currentURL)
    }

    static func host(from address: String) -> String? {
        normalizedURL(from: address)?.host
    }

    static func isSearchURL(_ url: URL) -> Bool {
        (url.host ?? "").contains("google.com") && url.path.contains("/search")
    }

    /// Turns typed text into a URL. Bare hosts get https://; anything that is
    /// not a host (no dot / has spaces) is treated as a Google search, or as
    /// https://text as a last resort.
    static func normalizedURL(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip a copied leading @ or surrounding quotes.
        if trimmed.hasPrefix("@") { trimmed.removeFirst() }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = parseAbsoluteWebURL(trimmed) {
            return url
        }

        if trimmed.hasPrefix("//") {
            if let url = parseAbsoluteWebURL("https:" + trimmed) {
                return url
            }
        }

        let looksLikeHost = isLikelyHostOrURL(trimmed)
        if looksLikeHost {
            if let url = parseAbsoluteWebURL("https://" + trimmed) {
                return url
            }
        }

        // Not a clear host — search, then fall back to https://text.
        if let search = searchURL(for: trimmed) {
            return search
        }
        return parseAbsoluteWebURL("https://" + trimmed)
    }

    private static func parseAbsoluteWebURL(_ string: String) -> URL? {
        if let url = URL(string: string), isValidWebURL(url) {
            return url
        }
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded), isValidWebURL(url) {
            return url
        }
        return nil
    }

    private static func isValidWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    private static func isLikelyHostOrURL(_ text: String) -> Bool {
        if text.contains(" ") || text.contains("\t") { return false }
        // A path or host with a dot, or localhost, or an IPv4 address.
        if text == "localhost" || text.hasPrefix("localhost:") { return true }
        if text.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil {
            return true
        }
        // Must contain a dot in the hostname part (before the first slash).
        let hostPart = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let hostOnly = hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? hostPart
        return hostOnly.contains(".") && !hostOnly.hasPrefix(".") && !hostOnly.hasSuffix(".")
    }

    private static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static var safariUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
    }
}

extension BrowserEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastNavigationFailed = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isLoading = true
        didCommitCurrentLoad = true
        showLoadError = false
        updateCurrentURL(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateCurrentURL(webView.url)
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
        markNavigationFinished(failed: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            // Frame load interrupted (usually a redirect or download) — ignore.
            return
        }
        lastErrorMessage = nsError.localizedDescription
        if !didCommitCurrentLoad {
            showLoadError = true
        }
        markNavigationFinished(failed: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data"].contains(scheme) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
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
