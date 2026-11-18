import SwiftUI

struct CookiePasteSheet: View {
    let fallbackDomain: String?
    var onInject: ([ParsedCookie]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var parsed: [ParsedCookie] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextEditor(text: $text)
                            .frame(minHeight: 180)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: text) { _, newValue in
                                parsed = CookieParser.parse(newValue, fallbackDomain: fallbackDomain)
                            }
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("الصق نص الكوكيز هنا…")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    } header: {
                        Text("نص الكوكيز")
                    } footer: {
                        Text("يدعم ترويسة Cookie بصيغة name=value; name2=value2 وكذلك التصدير متعدد الأسطر (الاسم = القيمة ثم سطر الخصائص: domain و path و secure و httpOnly و expires).")
                    }

                    Section("المعاينة") {
                        if parsed.isEmpty {
                            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "الصق النص لعرض الكوكيز المكتشفة."
                                 : "لم يتم التعرف على أي كوكيز في النص.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("تم التعرف على \(parsed.count) كوكي")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                            ForEach(parsed) { cookie in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cookie.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(summary(for: cookie))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                Button {
                    onInject(parsed)
                    dismiss()
                } label: {
                    Text("حقن الكوكيز والدخول")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsed.isEmpty)
                .padding()
            }
            .navigationTitle("تسجيل عبر الكوكيز")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !text.isEmpty {
                        Button("مسح") {
                            text = ""
                            parsed = []
                        }
                    }
                }
            }
        }
    }

    private func summary(for cookie: ParsedCookie) -> String {
        var parts: [String] = []
        if let domain = cookie.domain, !domain.isEmpty {
            parts.append(domain)
        } else if let fallbackDomain, !fallbackDomain.isEmpty {
            parts.append(fallbackDomain)
        }
        parts.append(cookie.path)
        if cookie.isSecure { parts.append("secure") }
        if cookie.isHTTPOnly { parts.append("httpOnly") }
        return parts.joined(separator: "  ·  ")
    }
}
