import Foundation

struct BrowserContainer: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var lastURLString: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, lastURLString: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.lastURLString = lastURLString
        self.createdAt = createdAt
    }

    var lastURL: URL? {
        guard let lastURLString, let url = URL(string: lastURLString) else { return nil }
        return url
    }

    var lastHost: String? {
        lastURL?.host
    }
}
