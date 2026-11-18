import SwiftUI
import WebKit

/// Hosts the shared WKWebView so it always fills the SwiftUI slot
/// (WKWebView has no intrinsic size and can collapse to 0×0 in a VStack).
/// The web view is forced LTR so site pages render correctly even when the
/// app chrome is RTL.
final class WebViewHost: UIView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        clipsToBounds = true
        semanticContentAttribute = .forceLeftToRight
        webView.semanticContentAttribute = .forceLeftToRight
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.isOpaque = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        attach()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if webView.superview !== self {
            attach()
        }
        webView.frame = bounds
    }

    private func attach() {
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.frame = bounds
            addSubview(webView)
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WebViewHost {
        WebViewHost(webView: webView)
    }

    func updateUIView(_ uiView: WebViewHost, context: Context) {
        uiView.webView.frame = uiView.bounds
        uiView.setNeedsLayout()
    }
}
