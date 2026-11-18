import SwiftUI
import UIKit

struct QuickLaunchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let symbol: String
}

enum QuickLaunch {
    static let items: [QuickLaunchItem] = [
        item("tiktok", "تيك توك", "https://www.tiktok.com", "music.note"),
        item("instagram", "إنستغرام", "https://www.instagram.com", "camera"),
        item("facebook", "فيسبوك", "https://www.facebook.com", "person.2"),
        item("x", "إكس", "https://twitter.com", "at"),
        item("youtube", "يوتيوب", "https://www.youtube.com", "play.rectangle.fill"),
        item("snapchat", "سناب شات", "https://www.snapchat.com", "bolt"),
        item("whatsapp", "واتساب ويب", "https://web.whatsapp.com", "message"),
        item("google", "جوجل", "https://www.google.com", "magnifyingglass"),
        item("gmail", "جيميل", "https://mail.google.com", "envelope")
    ]

    private static func item(_ id: String, _ title: String, _ url: String, _ symbol: String) -> QuickLaunchItem {
        QuickLaunchItem(id: id, title: title, url: URL(string: url)!, symbol: symbol)
    }
}

struct QuickLaunchBar: View {
    var onSelect: (QuickLaunchItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("اختصارات")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(QuickLaunch.items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.body.weight(.semibold))
                            Text(item.title)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            Color.accentColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        // Explicit height so the bar cannot collapse to 0 in a VStack.
        .frame(maxWidth: .infinity)
    }
}
