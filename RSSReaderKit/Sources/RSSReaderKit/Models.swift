import Foundation

public struct Feed: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var url: URL
    public var siteURL: URL?
    public var etag: String?
    public var lastModified: String?
    public var lastError: String?

    public init(title: String, url: URL, siteURL: URL? = nil) {
        self.title = title
        self.url = url
        self.siteURL = siteURL
    }
}

public struct Article: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let feedID: UUID
    public var title: String
    public var link: URL?
    public var author: String?
    public var contentHTML: String
    public var snippet: String
    public var published: Date?
    public let fetched: Date
    public var isRead: Bool = false
    public var isStarred: Bool = false

    public var sortDate: Date { published ?? fetched }
}

public enum SidebarItem: Hashable, Sendable {
    case unread
    case all
    case starred
    case feed(UUID)
}

public enum FeedError: LocalizedError {
    case invalidURL
    case notAFeed
    case noFeedFound
    case alreadySubscribed
    case saveFailed
    case unsubscribeFailed
    case notOPML
    case importFailed
    case exportFailed
    case badResponse
    case http(Int)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid web address."
        case .notAFeed: "The document is not an RSS or Atom feed."
        case .noFeedFound: "No feed was found at that address."
        case .alreadySubscribed: "You are already subscribed to this feed."
        case .saveFailed: "The feed could not be saved. Please try again."
        case .unsubscribeFailed: "The feed could not be unsubscribed. Please try again."
        case .notOPML: "The file is not an OPML subscription list."
        case .importFailed: "The subscriptions could not be imported. Please try again."
        case .exportFailed: "The subscriptions could not be exported."
        case .badResponse: "The server returned an unexpected response."
        case .http(let code): "The server responded with HTTP \(code)."
        case .parse(let message): "The feed could not be parsed: \(message)"
        }
    }
}
