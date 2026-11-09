import Foundation

struct Feed: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var url: URL
    var siteURL: URL?
    var etag: String?
    var lastModified: String?
    var lastError: String?
}

struct Article: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let feedID: UUID
    var title: String
    var link: URL?
    var author: String?
    var contentHTML: String
    var snippet: String
    var published: Date?
    let fetched: Date
    var isRead: Bool = false
    var isStarred: Bool = false

    var sortDate: Date { published ?? fetched }
}

enum SidebarItem: Hashable, Sendable {
    case unread
    case all
    case starred
    case feed(UUID)
}

enum FeedError: LocalizedError {
    case invalidURL
    case notAFeed
    case noFeedFound
    case alreadySubscribed
    case badResponse
    case http(Int)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid web address."
        case .notAFeed: "The document is not an RSS or Atom feed."
        case .noFeedFound: "No feed was found at that address."
        case .alreadySubscribed: "You are already subscribed to this feed."
        case .badResponse: "The server returned an unexpected response."
        case .http(let code): "The server responded with HTTP \(code)."
        case .parse(let message): "The feed could not be parsed: \(message)"
        }
    }
}
