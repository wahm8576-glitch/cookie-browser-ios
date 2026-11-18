import SwiftUI

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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickLaunch.items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(.primary)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }
}
