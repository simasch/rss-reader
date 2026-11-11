import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import ViewInspector

/// UC-002 Unsubscribe from Feed, tested through the app's main window (sidebar, article list, article view)
/// against the real FeedStore and a temporary library file, which `withLibrary` writes with two feeds and their
/// articles. The Reader unsubscribes with the Unsubscribe entry of the feed's menu in the subscription list.
@MainActor
@Suite("UC-002 Unsubscribe from Feed", .serialized)
struct UC002UnsubscribeFromFeedTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: the feed and all its articles leave the library, the sidebar and counts follow, the library is saved")
    func mainSuccessScenario() async throws {
        try await withReader { reader in
            #expect(try await reader.subscriptionRows() == 2)

            try await reader.unsubscribe("Alpha")

            // Step 2 and the success postconditions: no feed and no article of Alpha remain.
            #expect(reader.store.feeds.map(\.title) == ["Beta"])
            #expect(reader.store.articles.map(\.title).sorted() == ["Beta One", "Beta Two"])
            // Step 3: the subscription list and the unread counts no longer include the feed.
            #expect(try await reader.subscriptionRows() == 1)
            #expect(reader.store.unreadCountsByFeed() == [reader.feedID("Beta"): 2])
            // Step 4: the library is saved.
            let reloaded = FeedStore(fileURL: reader.libraryURL)
            #expect(reloaded.feeds.map(\.title) == ["Beta"])
            #expect(reloaded.articles.map(\.title).sorted() == ["Beta One", "Beta Two"])
        }
    }

    // MARK: - BR-001 Articles leave with their feed

    @Test("BR-001: read and starred articles are removed with their feed, at once and without asking first")
    func readAndStarredArticlesLeaveWithoutConfirmation() async throws {
        try await withReader { reader in
            // The fixture's Alpha One is read and Alpha Two is starred.
            #expect(reader.store.articles.contains { $0.title == "Alpha One" && $0.isRead })
            #expect(reader.store.articles.contains { $0.title == "Alpha Two" && $0.isStarred })

            try await reader.unsubscribe("Alpha")

            // Removed by choosing the menu entry alone: no confirmation stands between the choice and the removal.
            #expect(!reader.store.articles.contains { $0.title.hasPrefix("Alpha") })
            let reloaded = FeedStore(fileURL: reader.libraryURL)
            #expect(!reloaded.articles.contains { $0.title.hasPrefix("Alpha") })
            #expect(!reloaded.articles.contains { $0.isStarred })
        }
    }

    // MARK: - A1 Removed feed's article list was displayed

    @Test("A1: the removed feed's article list gives way to Unread, and its open article is no longer shown")
    func removedFeedsListGivesWayToUnread() async throws {
        try await withReader { reader in
            try await reader.selectList(.feed(reader.feedID("Alpha")))
            try await reader.openArticle("Alpha Three")
            #expect(try await reader.state().showsArticle)

            try await reader.unsubscribe("Alpha")

            let state = try await reader.state()
            #expect(state.list == .unread)
            #expect(state.selectedArticleID == nil)
            #expect(!state.showsArticle)
            #expect(state.listedTitles.allSatisfy { !$0.hasPrefix("Alpha") })
            #expect(state.listedTitles.contains("Beta One"))
        }
    }

    // MARK: - A2 Article of the removed feed was displayed in another list

    @Test("A2: Unread drops the feed's articles, also one kept there after reading, and clears the article view",
          arguments: [true, false])
    func unreadDropsFeedsArticles(openedArticleOfRemovedFeed: Bool) async throws {
        try await withReader { reader in
            try await reader.selectList(.unread)
            // Opening an article marks it read; UC-004 BR-004 keeps it in Unread for this visit.
            try await reader.openArticle("Alpha Three")
            #expect(try await reader.state().listedTitles.contains("Alpha Three"))
            if !openedArticleOfRemovedFeed {
                try await reader.openArticle("Beta One")
            }

            try await reader.unsubscribe("Alpha")

            let state = try await reader.state()
            #expect(state.list == .unread)
            #expect(state.listedTitles.allSatisfy { !$0.hasPrefix("Alpha") })
            if openedArticleOfRemovedFeed {
                #expect(state.selectedArticleID == nil)
                #expect(!state.showsArticle)
            } else {
                // An article of another feed stays displayed.
                #expect(state.selectedArticleID == reader.articleID("Beta One"))
                #expect(state.showsArticle)
            }
        }
    }

    @Test("A2: All Articles and Starred drop the feed's articles", arguments: [SidebarItem.all, .starred])
    func otherListsDropFeedsArticles(list: SidebarItem) async throws {
        try await withReader { reader in
            try await reader.selectList(list)
            #expect(try await reader.state().listedTitles.contains("Alpha Two"))
            try await reader.openArticle("Alpha Two")

            try await reader.unsubscribe("Alpha")

            let state = try await reader.state()
            #expect(state.list == list)
            #expect(state.listedTitles.allSatisfy { !$0.hasPrefix("Alpha") })
            #expect(state.selectedArticleID == nil)
            #expect(!state.showsArticle)
        }
    }

    // MARK: - A3 Library cannot be saved, BR-002 Only saved unsubscribes take effect

    @Test("A3, BR-002: a feed whose removal cannot be saved comes back with its articles and states, and the library is unchanged")
    func unsavableUnsubscribeIsUndone() async throws {
        try await withReader { reader in
            let feedsBefore = reader.store.feeds
            let articlesBefore = reader.store.articles
            let libraryBefore = try Data(contentsOf: reader.libraryURL)
            reader.makeLibraryUnwritable()

            try await reader.unsubscribe("Alpha")

            // A3 step 1, BR-002: the feed and its articles are back with their read and starred states.
            #expect(reader.store.feeds == feedsBefore)
            #expect(reader.store.articles == articlesBefore)
            // A3 step 2: the subscription list and the unread counts show the feed again.
            #expect(try await reader.subscriptionRows() == 2)
            #expect(reader.store.unreadCountsByFeed()[reader.feedID("Alpha")] == 2)
            // Failure postcondition: the library is unchanged.
            #expect(try Data(contentsOf: reader.libraryURL) == libraryBefore)
        }
    }

    @Test("A3: the Reader is told that the feed could not be unsubscribed")
    func failedUnsubscribeIsReported() async throws {
        try await withLibrary { store, libraryURL in
            makeUnwritable(libraryURL)
            let sidebar = SidebarView(selection: .constant(.unread))
            try await ViewHosting.host(NavigationStack { sidebar }.environment(store)) {
                try await sidebar.inspection.inspect { view in
                    #expect(throws: (any Error).self) { try view.find(ViewType.Alert.self) }
                    let rows = try view.find(ViewType.ForEach.self)
                    try unsubscribeEntry(inRow: Array(rows)[0]).tap()
                }
                try await sidebar.inspection.inspect { view in
                    let alert = try view.find(ViewType.Alert.self)
                    let message = try alert.message().text().string()
                    #expect(message.localizedCaseInsensitiveContains("could not be unsubscribed"))
                }
            }
            #expect(store.feeds.map(\.title) == ["Alpha", "Beta"])
        }
    }

    @Test("A3, BR-002: after a failed unsubscribe the display keeps its new state and shows the restored articles by the list's rules")
    func displayDoesNotReturnAfterFailedUnsubscribe() async throws {
        try await withReader { reader in
            try await reader.selectList(.feed(reader.feedID("Alpha")))
            try await reader.openArticle("Alpha Three")
            reader.makeLibraryUnwritable()

            try await reader.unsubscribe("Alpha")

            let state = try await reader.state()
            // A1 moved the display to Unread; it stays there, with no article selected.
            #expect(state.list == .unread)
            #expect(state.selectedArticleID == nil)
            #expect(!state.showsArticle)
            // Unread shows the restored unread articles, but not Alpha Three, read in the earlier visit.
            #expect(state.listedTitles.contains("Alpha Two"))
            #expect(!state.listedTitles.contains("Alpha One"))
            #expect(!state.listedTitles.contains("Alpha Three"))
        }
    }

    @Test("A3, BR-002: a read article kept in Unread does not reappear there when the feed comes back")
    func keptArticleDoesNotReappearAfterFailedUnsubscribe() async throws {
        try await withReader { reader in
            try await reader.selectList(.unread)
            try await reader.openArticle("Alpha Three")
            reader.makeLibraryUnwritable()

            try await reader.unsubscribe("Alpha")

            let state = try await reader.state()
            #expect(state.list == .unread)
            #expect(state.selectedArticleID == nil)
            #expect(!state.showsArticle)
            #expect(state.listedTitles.contains("Alpha Two"))
            #expect(!state.listedTitles.contains("Alpha Three"))
            #expect(reader.store.articles.contains { $0.title == "Alpha Three" && $0.isRead })
        }
    }
}

// MARK: - Test harness

private let alphaURL = URL(string: "https://alpha.example/feed.xml")!
private let betaURL = URL(string: "https://beta.example/feed.xml")!

/// What the main window shows: the selected list, the articles it lists, and the article view.
private struct WindowState {
    var list: SidebarItem?
    var selectedArticleID: Article.ID?
    var listedTitles: [String]
    var showsArticle: Bool
}

/// Drives one hosted main window.
@MainActor
private struct Reader {
    let view: ContentView
    let store: FeedStore
    let libraryURL: URL

    func feedID(_ title: String) -> UUID {
        store.feeds.first { $0.title == title }!.id
    }

    func articleID(_ title: String) -> Article.ID {
        store.articles.first { $0.title == title }!.id
    }

    /// Inspects the live window. The store is put into the inspected hierarchy again, so the sidebar and the
    /// article list ViewInspector builds from it find it in their environment, as they do in the app.
    private func inspect(_ body: @escaping @MainActor @Sendable (InspectableView<ViewType.ClassifiedView>) async throws -> Void) async throws {
        let store = store
        try await view.inspection.inspect { view in
            try await body(try view.actualView().environment(store).inspect())
        }
    }

    /// The number of feeds the subscription list shows.
    func subscriptionRows() async throws -> Int {
        let box = ResultBox(0)
        try await inspect { view in
            box.value = try view.find(SidebarView.self).find(ViewType.ForEach.self).count
        }
        return box.value
    }

    func state() async throws -> WindowState {
        let box = ResultBox(WindowState(list: nil, selectedArticleID: nil, listedTitles: [], showsArticle: false))
        try await inspect { view in
            let list = try view.find(ArticleListView.self)
            let actual = try list.actualView()
            box.value = WindowState(
                list: actual.sidebarSelection,
                selectedArticleID: actual.selectedArticleID,
                listedTitles: try list.findAll(ViewType.Text.self).map { try $0.string() },
                showsArticle: (try? view.find(ArticleDetailView.self)) != nil
            )
        }
        return box.value
    }

    /// The Reader selects a list in the sidebar.
    func selectList(_ item: SidebarItem) async throws {
        try await inspect { view in
            let sidebar = try view.find(SidebarView.self).actualView()
            sidebar.selection = item
        }
        try await settle()
    }

    /// The Reader opens an article of the displayed list.
    func openArticle(_ title: String) async throws {
        let id = articleID(title)
        try await inspect { view in
            let list = try view.find(ArticleListView.self).actualView()
            list.selectedArticleID = id
        }
        try await settle()
    }

    /// Step 1: the Reader chooses Unsubscribe in the feed's menu in the subscription list.
    func unsubscribe(_ title: String) async throws {
        let index = try #require(store.feeds.firstIndex { $0.title == title })
        try await inspect { view in
            let rows = try view.find(SidebarView.self).find(ViewType.ForEach.self)
            try unsubscribeEntry(inRow: Array(rows)[index]).tap()
        }
        try await settle()
    }

    func makeLibraryUnwritable() {
        makeUnwritable(libraryURL)
    }

    /// Lets SwiftUI apply the state changes of the last action.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// The Unsubscribe entry of a subscription-list row's context menu. ViewInspector can neither search a context
/// menu nor look inside a badged row, so the menu's buttons are taken from the row's modifiers by reflection.
@MainActor
private func unsubscribeEntry(inRow row: InspectableView<ViewType.ClassifiedView>) throws -> InspectableView<ViewType.Button> {
    var buttons: [Button<Text>] = []
    func collect(_ value: Any, depth: Int) {
        guard depth < 24 else { return }
        if let button = value as? Button<Text> {
            buttons.append(button)
            return
        }
        for child in Mirror(reflecting: value).children { collect(child.value, depth: depth + 1) }
    }
    let modifiers = Mirror(reflecting: row).descendant("content", "medium", "viewModifiers") as? [Any] ?? []
    for modifier in modifiers {
        if let menu = Mirror(reflecting: modifier).descendant("modifier", "menuView") { collect(menu, depth: 0) }
    }
    for button in buttons {
        let entry = try button.inspect().button()
        if try entry.labelView().text().string() == "Unsubscribe" { return entry }
    }
    struct NoUnsubscribeEntry: Error {}
    Issue.record("The feed's menu has no Unsubscribe entry")
    throw NoUnsubscribeEntry()
}

/// The library's folder no longer accepts writes, so the library cannot be saved.
private func makeUnwritable(_ libraryURL: URL) {
    try? FileManager.default.setAttributes(
        [.posixPermissions: 0o555], ofItemAtPath: libraryURL.deletingLastPathComponent().path()
    )
}

/// A fresh library in a temporary folder that holds two feeds, Alpha (three articles: Alpha One read, Alpha Two
/// starred, Alpha Three unread) and Beta (two unread articles), saved to the library file.
@MainActor
private func withLibrary(_ body: @MainActor (FeedStore, URL) async throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "UC002-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path())
        try? FileManager.default.removeItem(at: dir)
    }
    let libraryURL = dir.appending(path: "library.json")
    // The library is written as the file FeedStore keeps, so the suite needs no Feed Publisher stub, which is
    // global and in use by suites running at the same time.
    let alpha = Feed(title: "Alpha", url: alphaURL)
    let beta = Feed(title: "Beta", url: betaURL)
    let fetched = Date.now.addingTimeInterval(-3600)
    func article(_ feed: Feed, _ key: String, _ title: String, minutesAgo: Double,
                 read: Bool = false, starred: Bool = false) -> [String: Any] {
        [
            "id": "\(feed.id.uuidString)|\(key)", "feedID": feed.id.uuidString, "title": title,
            "contentHTML": "<p>\(title)</p>", "snippet": title,
            "published": Date.now.addingTimeInterval(-minutesAgo * 60).timeIntervalSinceReferenceDate,
            "fetched": fetched.timeIntervalSinceReferenceDate, "isRead": read, "isStarred": starred,
        ]
    }
    let feeds = try JSONSerialization.jsonObject(with: JSONEncoder().encode([alpha, beta]))
    let library: [String: Any] = [
        "feeds": feeds,
        "articles": [
            article(alpha, "a1", "Alpha One", minutesAgo: 10, read: true),
            article(alpha, "a2", "Alpha Two", minutesAgo: 20, starred: true),
            article(alpha, "a3", "Alpha Three", minutesAgo: 30),
            article(beta, "b1", "Beta One", minutesAgo: 15),
            article(beta, "b2", "Beta Two", minutesAgo: 25),
        ],
    ]
    try JSONSerialization.data(withJSONObject: library).write(to: libraryURL)
    let store = FeedStore(fileURL: libraryURL)
    try #require(store.feeds.map(\.title) == ["Alpha", "Beta"])
    try #require(store.articles.count == 5)

    try await body(store, libraryURL)
}

/// Opens the main window over the library of `withLibrary`.
@MainActor
private func withReader(_ body: @MainActor (Reader) async throws -> Void) async throws {
    try await withLibrary { store, libraryURL in
        let view = ContentView()
        let reader = Reader(view: view, store: store, libraryURL: libraryURL)
        try await ViewHosting.host(view.environment(store).frame(width: 1000, height: 600)) {
            try await body(reader)
        }
    }
}
