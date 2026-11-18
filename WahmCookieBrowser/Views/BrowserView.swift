import SwiftUI
import UIKit

struct BrowserView: View {
    let container: BrowserContainer

    @EnvironmentObject private var store: ContainerStore
    @StateObject private var engine: BrowserEngine
    @State private var showCookieSheet = false
    @State private var injectionMessage: String?
    @State private var showInjectionBanner = false

    init(container: BrowserContainer) {
        self.container = container
        _engine = StateObject(wrappedValue: BrowserEngine(containerID: container.id, initialURL: container.lastURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            cookieBar
            progressBar
            WebViewRepresentable(webView: engine.webView)
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(engine.pageTitle.isEmpty ? container.name : engine.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    engine.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.title3)
                }
                .disabled(!engine.canGoBack)
                .accessibilityLabel("رجوع")

                Spacer()

                Button {
                    engine.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.title3)
                }
                .disabled(!engine.canGoForward)
                .accessibilityLabel("تقدم")

                Spacer()

                Button {
                    engine.reloadOrStop()
                } label: {
                    Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.title3)
                }
                .accessibilityLabel(engine.isLoading ? "إيقاف" : "تحديث")
            }
        }
        .sheet(isPresented: $showCookieSheet) {
            CookiePasteSheet(fallbackDomain: engine.currentURL?.host ?? BrowserEngine.host(from: engine.addressText)) { cookies in
                Task { await inject(cookies) }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .overlay(alignment: .top) {
            if showInjectionBanner, let injectionMessage {
                banner(injectionMessage)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showInjectionBanner)
        .onChange(of: engine.currentURL) { _, newURL in
            store.updateLastURL(container.id, url: newURL)
        }
        .onAppear {
            if engine.addressText.isEmpty, let last = container.lastURLString {
                engine.addressText = last
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("https://example.com", text: $engine.addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit { engine.submitAddress() }
            if !engine.addressText.isEmpty {
                Button {
                    engine.addressText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("مسح العنوان")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var cookieBar: some View {
        Button {
            showCookieSheet = true
        } label: {
            Label("تسجيل عبر كوكيز", systemImage: "key.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .disabled(engine.currentURL == nil && BrowserEngine.normalizedURL(from: engine.addressText) == nil)
    }

    @ViewBuilder
    private var progressBar: some View {
        if engine.isLoading || engine.progress > 0 && engine.progress < 1 {
            ProgressView(value: max(engine.progress, 0.05), total: 1)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 2)
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 4)
    }

    @MainActor
    private func inject(_ cookies: [ParsedCookie]) async {
        // If the page has not been opened yet but the address bar has a URL, load it first so the domain is known.
        if engine.currentURL == nil, let url = BrowserEngine.normalizedURL(from: engine.addressText) {
            engine.load(url: url)
        }
        let applied = await engine.injectCookies(cookies)
        engine.reloadAfterCookieInjection()
        injectionMessage = applied == 0 ? "تعذر حقن الكوكيز" : "تم حقن \(applied) كوكي — جاري فتح الموقع"
        showInjectionBanner = true
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            showInjectionBanner = false
        }
    }
}
