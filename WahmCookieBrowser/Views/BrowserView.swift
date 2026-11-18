import SwiftUI
import UIKit

struct BrowserView: View {
    let container: BrowserContainer

    @EnvironmentObject private var store: ContainerStore
    @StateObject private var engine: BrowserEngine
    @FocusState private var addressFocused: Bool

    @State private var showCookieSheet = false
    @State private var toast: Toast?
    @State private var isLoggingIn = false
    @State private var toastTask: Task<Void, Never>?
    @State private var chromeVisible = true

    init(container: BrowserContainer) {
        self.container = container
        _engine = StateObject(wrappedValue: BrowserEngine(containerID: container.id, initialURL: container.lastURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            if chromeVisible {
                VStack(spacing: 0) {
                    addressBar
                    cookieBar
                    QuickLaunchBar { item in
                        openShortcut(item)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .top) {
                WebViewRepresentable(webView: engine.webView)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: chromeVisible ? .bottom : [.top, .bottom])

                if engine.isLoading || (engine.progress > 0 && engine.progress < 1) {
                    ProgressView(value: min(max(engine.progress, 0.05), 1), total: 1)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                }

                if engine.currentURL == nil && !engine.isLoading && engine.lastErrorMessage == nil && chromeVisible {
                    emptyState
                        .allowsHitTesting(false)
                }

                if engine.showLoadError, let error = engine.lastErrorMessage, !engine.isLoading {
                    errorState(error)
                }

                if isLoggingIn {
                    loginOverlay
                }

                if let toast {
                    VStack {
                        toastBanner(toast)
                            .padding(.top, showChromeToggle ? 44 : 10)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }

                if showChromeToggle {
                    chromeToggle
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(engine.pageTitle.isEmpty ? container.name : engine.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(chromeVisible ? .visible : .hidden, for: .bottomBar)
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
        .animation(.easeInOut(duration: 0.32), value: chromeVisible)
        .animation(.spring(duration: 0.35), value: toast?.id)
        .animation(.easeInOut(duration: 0.2), value: isLoggingIn)
        .onChange(of: engine.currentURL) { _, newURL in
            store.updateLastURL(container.id, url: newURL)
            if newURL != nil {
                collapseChrome()
            }
        }
        .onAppear {
            if engine.addressText.isEmpty, let last = container.lastURLString {
                engine.addressText = last
            }
            if container.lastURL != nil || engine.currentURL != nil {
                chromeVisible = false
            }
        }
        .onDisappear {
            toastTask?.cancel()
        }
    }

    private var showChromeToggle: Bool {
        engine.currentURL != nil || engine.isLoading || !chromeVisible
    }

    private var chromeToggle: some View {
        Button {
            toggleChrome()
        } label: {
            Image(systemName: chromeVisible ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 28)
                .background(.black.opacity(0.40), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.28), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chromeVisible ? "إخفاء الشريط" : "إظهار الشريط")
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func collapseChrome() {
        addressFocused = false
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.32)) {
            chromeVisible = false
        }
    }

    private func toggleChrome() {
        if chromeVisible {
            addressFocused = false
            hideKeyboard()
        }
        withAnimation(.easeInOut(duration: 0.32)) {
            chromeVisible.toggle()
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.currentURL?.scheme == "http" ? "lock.open.fill" : "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("اكتب رابط الموقع", text: $engine.addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .environment(\.layoutDirection, .leftToRight)
                .onSubmit { go() }
            if !engine.addressText.isEmpty && addressFocused {
                Button {
                    engine.addressText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("مسح العنوان")
            }
            Button {
                go()
            } label: {
                Text("ذهاب")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(engine.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("فتح الموقع")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var cookieBar: some View {
        Button {
            addressFocused = false
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
        // Always visible and tappable, as requested.
    }

    @ViewBuilder
    private var progressBar: some View {
        if engine.isLoading || (engine.progress > 0 && engine.progress < 1) {
            ProgressView(value: min(max(engine.progress, 0.05), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("اكتب رابط الموقع ثم اضغط ذهاب")
                .font(.headline)
            Text("سيفتح الموقع هنا كمتصفح عادي، مع صفحة تسجيل الدخول الخاصة به.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).opacity(0.92))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text("تعذر فتح الموقع")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("إعادة المحاولة") {
                go()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).opacity(0.94))
    }

    private var loginOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("جاري تسجيل الدخول…")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .allowsHitTesting(true)
    }

    private func toastBanner(_ toast: Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(toast.kind == .success ? Color.white : Color.white)
        .background(toast.kind == .success ? Color.green.opacity(0.92) : Color.red.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal, 16)
    }

    private func openShortcut(_ item: QuickLaunchItem) {
        engine.addressText = item.url.absoluteString
        engine.load(url: item.url)
        collapseChrome()
    }

    private func go() {
        let raw = engine.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if !engine.submitAddress() {
            showToast(Toast(kind: .failure, message: "تعذر التعرف على الرابط"))
            return
        }
        collapseChrome()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func showToast(_ toast: Toast) {
        toastTask?.cancel()
        withAnimation {
            self.toast = toast
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation {
                if self.toast?.id == toast.id {
                    self.toast = nil
                }
            }
        }
    }

    @MainActor
    private func inject(_ cookies: [ParsedCookie]) async {
        if cookies.isEmpty {
            showToast(Toast(kind: .failure, message: "فشل تسجيل الدخول: لم يتم العثور على كوكيز صالحة"))
            return
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        if engine.currentURL == nil {
            if let url = engine.suggestedURLFromCookies(cookies) {
                engine.addressText = url.absoluteString
                engine.load(url: url)
                collapseChrome()
                _ = await engine.waitForNavigation(timeout: 12)
            }
        }

        let applied = await engine.injectCookies(cookies)
        if applied == 0 {
            showToast(Toast(kind: .failure, message: "فشل تسجيل الدخول: لم يتم العثور على كوكيز صالحة"))
            return
        }

        engine.reloadAfterCookieInjection()
        let finalURL = await engine.waitForNavigation(timeout: 16)

        if engine.navigationDidFail {
            showToast(Toast(kind: .failure, message: "فشل تسجيل الدخول — قد تكون الجلسة منتهية"))
            return
        }

        if let finalURL, BrowserEngine.looksLikeLoginPage(finalURL) {
            showToast(Toast(kind: .failure, message: "فشل تسجيل الدخول — قد تكون الجلسة منتهية"))
        } else {
            showToast(Toast(kind: .success, message: "تم تسجيل الدخول ✓"))
        }
    }
}

private struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let message: String
}
