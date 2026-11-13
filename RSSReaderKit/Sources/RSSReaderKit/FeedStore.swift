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
    /// A read or starred change is waiting for its save (UC-005 BR-002).
    @ObservationIgnored private var hasUnsavedChanges = false
    /// An import asked for a refresh while one was running (UC-003 BR-002).
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private let refreshInterval: Duration
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var nextScheduledRefresh: ContinuousClock.Instant?

    /// Read articles that dropped out of their feed are removed after this long (starred ones are kept).
    private static let retention: TimeInterval = 30 * 24 * 60 * 60

    public nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "RSSReader", directoryHint: .isDirectory)
            .appending(path: "library.json")
    }

    public init(fileURL: URL = FeedStore.defaultFileURL, refreshInterval: Duration = .seconds(30 * 60)) {
        self.fileURL = fileURL
        self.refreshInterval = refreshInterval
        load()
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // UC-005 BR-002: pending read and starred changes are saved when the app quits.
            MainActor.assumeIsolated { self?.save() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // UC-005 BR-002: and when it moves to the background: another app becomes active or it is hidden.
            MainActor.assumeIsolated { if self?.hasUnsavedChanges == true { self?.save() } }
        }
        #endif
        // On iOS the app saves when it moves to the background (see App/Views/RefreshSchedule.swift).
    }

    // MARK: - Queries

    /// The articles shown for a sidebar item, newest first. `keep` lists read articles that stay in
    /// "Unread" anyway, so the list does not shift under the user while they move through it.
    // UC-004 BR-001: Unread, All Articles, Starred, or one feed's articles.
    public func articles(in selection: SidebarItem?, keeping keep: Set<Article.ID> = []) -> [Article] {
        let filtered: [Article] = switch selection {
        // UC-004 BR-004: articles read during the visit stay in Unread until the list changes.
        // UC-005 BR-004: a read article not opened by displaying it leaves Unread at once.
        case .unread: articles.filter { !$0.isRead || keep.contains($0.id) }
        // UC-005 BR-004: an unstarred article leaves Starred at once.
        case .starred: articles.filter(\.isStarred)
        case .feed(let id): articles.filter { $0.feedID == id }
        case .all, nil: articles
        }
        // UC-004 BR-002: newest first by publication date, else by the time first fetched.
        return filtered.sorted { $0.sortDate > $1.sortDate }
    }

    /// The article `offset` places before (negative) or after (positive) the given one in the list of a
    /// sidebar item, if any (UC-004 step 6).
    public func neighbour(
        of id: Article.ID, offset: Int, in selection: SidebarItem?, keeping keep: Set<Article.ID> = []
    ) -> Article.ID? {
        let list = articles(in: selection, keeping: keep)
        let index: Int
        if let position = list.firstIndex(where: { $0.id == id }) {
            index = position + offset
        } else {
            // UC-005 BR-006: an article that left the list steps to the articles at its former place.
            guard offset != 0, let article = article(withID: id) else { return nil }
            let place = list.firstIndex { $0.sortDate < article.sortDate } ?? list.count
            index = offset > 0 ? place + offset - 1 : place + offset
        }
        return list.indices.contains(index) ? list[index].id : nil
    }

    public func article(withID id: Article.ID) -> Article? {
        articles.first { $0.id == id }
    }

    public func feed(withID id: UUID) -> Feed? {
        feeds.first { $0.id == id }
    }

    // UC-004 BR-006: unread articles per feed; the Unread list shows their total.
    public func unreadCountsByFeed() -> [UUID: Int] {
        articles.reduce(into: [:]) { counts, article in
            if !article.isRead { counts[article.feedID, default: 0] += 1 }
        }
    }

    // MARK: - Article state

    public func setRead(_ read: Bool, articleID: Article.ID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }), articles[i].isRead != read else { return }
        articles[i].isRead = read
        // UC-004 BR-008: saved like any read change; on failure it stays read for the next save.
        scheduleSave()
    }

    // UC-005 step 3: marks the article as unread if it was read, or as read if it was unread.
    public func toggleRead(_ articleID: Article.ID) {
        guard let article = article(withID: articleID) else { return }
        setRead(!article.isRead, articleID: articleID)
    }

    // UC-005 A1: stars the article if it was not starred, or removes the star if it was.
    public func toggleStar(_ articleID: Article.ID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[i].isStarred.toggle()
        scheduleSave()
    }

    /// Marks every unread article of the displayed list as read and returns the articles it marked (UC-005 A2).
    @discardableResult
    public func markAllRead(in selection: SidebarItem?) -> Set<Article.ID> {
        // UC-005 BR-001: Mark all as read affects only the articles of the displayed list.
        let ids = Set(articles(in: selection).filter { !$0.isRead }.map(\.id))
        // UC-005 A3: a list without unread articles leaves the library unchanged.
        guard !ids.isEmpty else { return [] }
        for i in articles.indices where ids.contains(articles[i].id) {
            articles[i].isRead = true
        }
        scheduleSave()
        return ids
    }

    // MARK: - Subscriptions

    public func addFeed(from input: String) async throws {
        let url = try Self.normalizedAddress(input)
        // UC-001 BR-003: a website address is followed to the first feed it advertises.
        let (feedURL, parsed) = try await FeedFetcher.discover(url)
        // UC-001 BR-009: a cancelled subscription adds nothing, even if the retrieval finished.
        try Task.checkCancellation()
        try subscribe(to: feedURL, parsed: parsed)
    }

    // UC-001 BR-001: trim, unwrap feed:, default to https://, accept only http(s) with a host.
    nonisolated static func normalizedAddress(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("feed:") {
            text = String(text.dropFirst(5))
            if text.hasPrefix("//") { text = "https:" + text }
        }
        // A leading "name:" is a scheme (mailto:, ftp://) unless a port number follows it (example.com:8080).
        let hasScheme = text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:(//|[^0-9])", options: .regularExpression) != nil
        if !hasScheme {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty else { throw FeedError.invalidURL }
        return url
    }

    /// Adds a retrieved feed and saves the library; undoes the addition when the save fails.
    func subscribe(to feedURL: URL, parsed: ParsedFeed) throws {
        // UC-001 BR-002: a feed is subscribed only once, compared by its final feed address.
        guard !feeds.contains(where: { $0.url == feedURL }) else { throw FeedError.alreadySubscribed }

        // UC-001 BR-004: the feed's own title as plain text, at most 200 characters, else the host name.
        let parsedTitle = parsed.title.map { HTMLText.plainText($0, limit: 200) } ?? ""
        let feed = Feed(
            title: parsedTitle.isEmpty ? (feedURL.host() ?? feedURL.absoluteString) : parsedTitle,
            url: feedURL,
            siteURL: parsed.siteURL
        )
        feeds.append(feed)
        sortFeeds()
        // UC-001 BR-006: the first articles follow the refresh rules; new articles are unread, not starred.
        merge(parsed.items, into: feed.id)
        do {
            try persist()
        } catch {
            // UC-001 BR-008: a subscription that cannot be saved is not added.
            feeds.removeAll { $0.id == feed.id }
            articles.removeAll { $0.feedID == feed.id }
            print("Failed to save library: \(error)")
            throw FeedError.saveFailed
        }
    }

    /// Removes a feed with its articles and saves the library; restores both when the save fails.
    public func removeFeed(id: UUID) throws {
        let previousFeeds = feeds
        let previousArticles = articles
        feeds.removeAll { $0.id == id }
        // UC-002 BR-001: every article leaves with its feed, read and starred ones included.
        articles.removeAll { $0.feedID == id }
        do {
            try persist()
        } catch {
            // UC-002 BR-002: an unsubscribe that cannot be saved is undone, states included.
            feeds = previousFeeds
            articles = previousArticles
            print("Failed to save library: \(error)")
            throw FeedError.unsubscribeFailed
        }
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

    /// Refreshes every subscribed feed. `requestedByImport` marks the refresh an import asks for (UC-006).
    public func refreshAll(requestedByImport: Bool = false) async {
        // UC-003 BR-002: one refresh at a time; an import's request waits for the running one (max. one).
        guard !isRefreshing else {
            if requestedByImport { refreshPending = true }
            return
        }
        // UC-003 A6: a library without feeds has nothing to refresh.
        guard !feeds.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            await refreshOnce()
        } while refreshPending && !feeds.isEmpty
    }

    private func refreshOnce() async {
        let requests = feeds.map { ($0.id, $0.url, $0.etag, $0.lastModified) }
        // UC-003 BR-011: each feed is fetched on its own; a failure does not stop the others.
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
        // UC-003 BR-012: an unsaved refresh stays in the library and goes out with the next save, silently.
        save()
    }

    private func apply(_ result: Result<FetchResult, Error>, toFeed id: UUID) {
        // UC-003 A4: the result of a feed unsubscribed during the refresh is discarded.
        guard let i = feeds.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success(.notModified):
            // UC-003 A1: an unchanged feed clears its error and keeps its articles.
            feeds[i].lastError = nil
        case .success(.updated(let parsed, let etag, let lastModified)):
            // UC-003 BR-013: the feed's title stays as given at subscription or import.
            feeds[i].etag = etag
            feeds[i].lastModified = lastModified
            feeds[i].lastError = nil
            if let site = parsed.siteURL { feeds[i].siteURL = site }
            let current = merge(parsed.items, into: id)
            // UC-003 BR-003: a damaged feed removes no article.
            guard parsed.isComplete else { return }
            removeExpiredArticles(ofFeed: id, keeping: current)
        case .failure(let error):
            // UC-003 BR-011: the problem stays with the feed until a later refresh of it succeeds.
            feeds[i].lastError = error.localizedDescription
        }
    }

    // UC-003 BR-008: read, unstarred, fetched over 30 days ago, and gone from its complete feed.
    // UC-005 BR-003: a starred article never expires.
    private func removeExpiredArticles(ofFeed id: UUID, keeping current: Set<Article.ID>) {
        let cutoff = Date.now.addingTimeInterval(-Self.retention)
        articles.removeAll {
            $0.feedID == id && $0.isRead && !$0.isStarred && $0.fetched < cutoff && !current.contains($0.id)
        }
    }

    // MARK: - Schedule

    /// Starts or resumes the scheduled refresh: at once when it is due, then every refresh interval.
    // UC-003 BR-001: refresh at start and every 30 minutes; a missed one follows on resume.
    public func resumeScheduledRefresh() {
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            while let delay = self?.runScheduledRefreshIfDue() {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
            }
        }
    }

    /// Stops the scheduled refresh while the app is in the background; a running refresh finishes.
    // UC-003 BR-001: no scheduled refresh runs while the app is in the background on iPhone and iPad.
    public func pauseScheduledRefresh() {
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    /// Starts the scheduled refresh when it is due and returns the time until the next one.
    private func runScheduledRefreshIfDue() -> Duration {
        let now = ContinuousClock.now
        if let due = nextScheduledRefresh, now < due { return due - now }
        nextScheduledRefresh = now + refreshInterval
        // Unstructured, so pausing the schedule does not cancel a refresh that is under way.
        Task { await refreshAll() }
        return refreshInterval
    }

    /// Inserts new items and updates existing ones, keeping read/starred state. Returns the IDs seen.
    @discardableResult
    private func merge(_ items: [ParsedItem], into feedID: UUID) -> Set<Article.ID> {
        var index = Dictionary(articles.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Article.ID>()
        let now = Date.now

        for item in items {
            // UC-003 BR-004: identified by guid, else link, else title; skipped without any, taken once.
            guard let key = item.guid ?? item.link?.absoluteString ?? item.title else { continue }
            let id = "\(feedID.uuidString)|\(key)"
            guard seen.insert(id).inserted else { continue }

            // UC-003 BR-006: content is the full content, else the summary; snippet prefers the summary.
            let html = item.content ?? item.summary ?? ""
            // UC-003 BR-005: plain-text title of at most 500 characters, "(Untitled)" when missing.
            let title = item.title.map { HTMLText.plainText($0, limit: 500) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? "(Untitled)"
            let snippet = HTMLText.plainText(item.summary ?? html)

            if let i = index[id] {
                // UC-003 BR-007: read and starred stay; the date is kept when the feed drops it.
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

    // UC-001 BR-005: subscriptions are listed alphabetically by title, ignoring case.
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
        do {
            try persist()
        } catch {
            // UC-005 A4, BR-002: the changes stay in effect, silently, and go out with the next save.
            print("Failed to save library: \(error)")
        }
    }

    /// Writes the library and reports a failure, for callers that must undo their change.
    private func persist() throws {
        saveTask?.cancel()
        saveTask = nil
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Library(feeds: feeds, articles: articles))
        try data.write(to: fileURL, options: .atomic)
        hasUnsavedChanges = false
    }

    /// Coalesces frequent changes (e.g. marking articles read while browsing) into one write.
    // UC-005 BR-002: read and starred changes are saved at most 2 seconds after the last one.
    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            save()
        }
    }
}
