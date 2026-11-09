import Foundation
import Testing
@testable import RSSReader

@MainActor
@Suite struct UnreadListTests {
    private struct Library: Codable {
        var feeds: [Feed]
        var articles: [Article]
    }

    /// A store loaded from a temporary library holding one feed with the given article ids.
    private func makeStore(articleIDs: [String]) throws -> FeedStore {
        let feed = Feed(title: "Example", url: URL(string: "https://example.com/feed.xml")!)
        let articles = articleIDs.enumerated().map { offset, id in
            Article(id: id, feedID: feed.id, title: id, link: nil, author: nil, contentHTML: "", snippet: "",
                    published: Date(timeIntervalSince1970: TimeInterval(offset)), fetched: .now)
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "RSSReaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "library.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Library(feeds: [feed], articles: articles)).write(to: url)
        return FeedStore(fileURL: url)
    }

    @Test func unreadKeepsSelectedReadArticleWhileOthersRemainUnread() throws {
        let store = try makeStore(articleIDs: ["a", "b"])
        store.setRead(true, articleID: "a")
        #expect(store.articles(in: .unread, keeping: "a").map(\.id) == ["b", "a"])
        #expect(store.articles(in: .unread).map(\.id) == ["b"])
    }

    @Test func unreadDropsLastArticleOnceItIsRead() throws {
        let store = try makeStore(articleIDs: ["a"])
        #expect(store.articles(in: .unread, keeping: "a").map(\.id) == ["a"])
        store.setRead(true, articleID: "a")
        #expect(store.articles(in: .unread, keeping: "a").isEmpty)
    }
}
