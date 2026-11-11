import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// Holds all feeds and articles, persists them as JSON in Application Support, and refreshes feeds.
@MainActor
@Observable
public final class FeedStore {
    public private(set) var feeds: [Feed] = []
    public private(set) var articles: [Article] = []
    public private(set) var isRefreshing = false
    public var isAddingFeed = false

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Read articles that dropped out of their feed are removed after this long (starred ones are kept).
    private static let retention: TimeInterval = 30 * 24 * 60 * 60

    public nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "RSSReader", directoryHint: .isDirectory)
            .appending(path: "library.json")
    }

    public init(fileURL: URL = FeedStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        #endif
        // On iOS the app saves when it moves to the background (see App/RSSReaderApp.swift).
    }

    // MARK: - Queries

    /// The articles shown for a sidebar item, newest first. `keep` lists read articles that stay in
    /// "Unread" anyway, so the list does not shift under the user while they move through it.
    public func articles(in selection: SidebarItem?, keeping keep: Set<Article.ID> = []) -> [Article] {
        let filtered: [Article] = switch selection {
        case .unread: articles.filter { !$0.isRead || keep.contains($0.id) }
        case .starred: articles.filter(\.isStarred)
        case .feed(let id): articles.filter { $0.feedID == id }
        case .all, nil: articles
        }
        return filtered.sorted { $0.sortDate > $1.sortDate }
    }

    public func article(withID id: Article.ID) -> Article? {
        articles.first { $0.id == id }
    }

    public func feed(withID id: UUID) -> Feed? {
        feeds.first { $0.id == id }
    }

    public func unreadCountsByFeed() -> [UUID: Int] {
        articles.reduce(into: [:]) { counts, article in
            if !article.isRead { counts[article.feedID, default: 0] += 1 }
        }
    }

    // MARK: - Article state

    public func setRead(_ read: Bool, articleID: Article.ID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }), articles[i].isRead != read else { return }
        articles[i].isRead = read
        scheduleSave()
    }

    public func toggleRead(_ articleID: Article.ID) {
        guard let article = article(withID: articleID) else { return }
        setRead(!article.isRead, articleID: articleID)
    }

    public func toggleStar(_ articleID: Article.ID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[i].isStarred.toggle()
        scheduleSave()
    }

    public func markAllRead(in selection: SidebarItem?) {
        let ids = Set(articles(in: selection).filter { !$0.isRead }.map(\.id))
        guard !ids.isEmpty else { return }
        for i in articles.indices where ids.contains(articles[i].id) {
            articles[i].isRead = true
        }
        scheduleSave()
    }

    // MARK: - Subscriptions

    public func addFeed(from input: String) async throws {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("feed:") {
            text = String(text.dropFirst(5))
            if text.hasPrefix("//") { text = "https:" + text }
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { throw FeedError.invalidURL }

        let (feedURL, parsed) = try await FeedFetcher.discover(url)
        guard !feeds.contains(where: { $0.url == feedURL }) else { throw FeedError.alreadySubscribed }

        let parsedTitle = parsed.title.map { HTMLText.plainText($0, limit: 200) } ?? ""
        let feed = Feed(
            title: parsedTitle.isEmpty ? (feedURL.host() ?? feedURL.absoluteString) : parsedTitle,
            url: feedURL,
            siteURL: parsed.siteURL
        )
        feeds.append(feed)
        sortFeeds()
        merge(parsed.items, into: feed.id)
        save()
    }

    public func removeFeed(id: UUID) {
        feeds.removeAll { $0.id == id }
        articles.removeAll { $0.feedID == id }
        save()
    }

    @discardableResult
    public func importOPML(from url: URL) throws -> Int {
        // Files picked on iOS are security-scoped; the call is a no-op for ordinary URLs.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let entries = try OPML.parse(Data(contentsOf: url))
        var added = 0
        for entry in entries where !feeds.contains(where: { $0.url == entry.url }) {
            feeds.append(Feed(title: entry.title, url: entry.url, siteURL: entry.siteURL))
            added += 1
        }
        if added > 0 {
            sortFeeds()
            save()
        }
        return added
    }

    public func exportOPML(to url: URL) throws {
        try OPML.export(feeds).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Refresh

    public func refreshAll() async {
        guard !isRefreshing, !feeds.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let requests = feeds.map { ($0.id, $0.url, $0.etag, $0.lastModified) }
        await withTaskGroup(of: (UUID, Result<FetchResult, Error>).self) { group in
            for (id, url, etag, lastModified) in requests {
                group.addTask {
                    do {
                        return (id, .success(try await FeedFetcher.fetch(url, etag: etag, lastModified: lastModified)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                apply(result, toFeed: id)
            }
        }
        save()
    }

    private func apply(_ result: Result<FetchResult, Error>, toFeed id: UUID) {
        guard let i = feeds.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success(.notModified):
            feeds[i].lastError = nil
        case .success(.updated(let parsed, let etag, let lastModified)):
            feeds[i].etag = etag
            feeds[i].lastModified = lastModified
            feeds[i].lastError = nil
            if let site = parsed.siteURL { feeds[i].siteURL = site }
            let current = merge(parsed.items, into: id)
            let cutoff = Date.now.addingTimeInterval(-Self.retention)
            articles.removeAll {
                $0.feedID == id && $0.isRead && !$0.isStarred && $0.fetched < cutoff && !current.contains($0.id)
            }
        case .failure(let error):
            feeds[i].lastError = error.localizedDescription
        }
    }

    /// Inserts new items and updates existing ones, keeping read/starred state. Returns the IDs seen.
    @discardableResult
    private func merge(_ items: [ParsedItem], into feedID: UUID) -> Set<Article.ID> {
        var index = Dictionary(articles.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Article.ID>()
        let now = Date.now

        for item in items {
            guard let key = item.guid ?? item.link?.absoluteString ?? item.title else { continue }
            let id = "\(feedID.uuidString)|\(key)"
            guard seen.insert(id).inserted else { continue }

            let html = item.content ?? item.summary ?? ""
            let title = item.title.map { HTMLText.plainText($0, limit: 500) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? "(Untitled)"
            let snippet = HTMLText.plainText(item.summary ?? html)

            if let i = index[id] {
                articles[i].title = title
                articles[i].link = item.link
                articles[i].author = item.author
                articles[i].contentHTML = html
                articles[i].snippet = snippet
                articles[i].published = item.date ?? articles[i].published
            } else {
                index[id] = articles.count
                articles.append(Article(
                    id: id, feedID: feedID, title: title, link: item.link, author: item.author,
                    contentHTML: html, snippet: snippet, published: item.date, fetched: now
                ))
            }
        }
        return seen
    }

    private func sortFeeds() {
        feeds.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Persistence

    private struct Library: Codable {
        var feeds: [Feed]
        var articles: [Article]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let library = try JSONDecoder().decode(Library.self, from: data)
            feeds = library.feeds
            articles = library.articles
        } catch {
            // Keep the unreadable file around instead of overwriting it on the next save.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    public func save() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Library(feeds: feeds, articles: articles))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save library: \(error)")
        }
    }

    /// Coalesces frequent changes (e.g. marking articles read while browsing) into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            save()
        }
    }
}
