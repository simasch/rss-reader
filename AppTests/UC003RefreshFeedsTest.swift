import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import ViewInspector

/// UC-003 Refresh Feeds, tested through the app's main window (sidebar, article list with its toolbar) against the
/// real FeedStore, a temporary library file that `withReader` writes with the feeds and articles a test needs, and
/// `FeedPublisherStub` in place of the Feed Publisher. The Reader refreshes with the toolbar's Refresh button, on the
/// Mac also from the Feeds menu or with ⌘R, and on iPhone and iPad by pulling down a list. The Scheduler is attached
/// to the window as in the app (`refreshSchedule`), with the scene phase under the test's control.
@MainActor
@Suite("UC-003 Refresh Feeds", .serialized)
struct UC003RefreshFeedsTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: new articles are added unread, known ones updated, the feed's version and website recorded, the library saved")
    func mainSuccessScenario() async throws {
        var alpha = Feed(title: "Alpha", url: alphaURL)
        alpha.etag = "\"v1\""
        alpha.lastModified = "Tue, 10 Nov 2026 08:00:00 GMT"
        alpha.lastError = "The server responded with HTTP 500."
        let stored = [
            StoredArticle(feed: alpha, key: "a1", title: "Old title", link: "https://alpha.example/old",
                          author: "Old Author", content: "<p>Old content</p>", published: date("2026-11-01T08:00:00Z"),
                          read: true, starred: true),
        ]
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
        <title>Alpha Publisher Renamed</title><link>https://alpha.example/site/</link>
        <item><guid>a1</guid><title>New title</title><link>https://alpha.example/new</link><author>New Author</author>
          <description>New summary</description><content:encoded><![CDATA[<p>New content</p>]]></content:encoded>
          <pubDate>Tue, 10 Nov 2026 09:00:00 GMT</pubDate></item>
        <item><guid>a2</guid><title>Brand new</title><description>Fresh</description></item>
        </channel></rss>
        """
        let headers = ["ETag": "\"v2\"", "Last-Modified": "Wed, 11 Nov 2026 08:00:00 GMT"]
        try await withReader(feeds: [alpha], articles: stored, answers: [alphaURL: .document(feed, headers: headers)]) { reader in
            try await reader.refreshFromToolbar()

            // Step 3: the feed is requested stating the version the System already has.
            let request = try #require(reader.feedRequests().first)
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
            #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Tue, 10 Nov 2026 08:00:00 GMT")

            // Step 5: the new article is added unread; the known one is updated in every field.
            let added = try #require(reader.article("Brand new"))
            #expect(!added.isRead && !added.isStarred)
            let updated = try #require(reader.article("New title"))
            #expect(updated.id == reader.articleID(alpha, "a1"))
            #expect(updated.link == URL(string: "https://alpha.example/new"))
            #expect(updated.author == "New Author")
            #expect(updated.contentHTML == "<p>New content</p>")
            #expect(updated.snippet == "New summary")
            #expect(updated.published == date("2026-11-10T09:00:00Z"))
            // Success postcondition, BR-007: read and starred states are unchanged.
            #expect(updated.isRead && updated.isStarred)
            #expect(reader.store.articles.count == 2)

            // Step 6: version and website recorded, earlier error cleared. BR-013: the title is kept.
            let refreshed = try #require(reader.store.feed(withID: alpha.id))
            #expect(refreshed.etag == "\"v2\"")
            #expect(refreshed.lastModified == "Wed, 11 Nov 2026 08:00:00 GMT")
            #expect(refreshed.siteURL == URL(string: "https://alpha.example/site/"))
            #expect(refreshed.lastError == nil)
            #expect(refreshed.title == "Alpha")
            #expect(try await reader.problemShown(forFeed: "Alpha") == nil)

            // Step 8: the library is saved and the refresh shows it has finished.
            let reloaded = FeedStore(fileURL: reader.libraryURL)
            #expect(reloaded.feeds == reader.store.feeds)
            #expect(Set(reloaded.articles) == Set(reader.store.articles))
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    @Test("Step 2: while the refresh runs the toolbar shows it, and shows when it has finished")
    func toolbarShowsRunningRefresh() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]), delay: .milliseconds(800))]) { reader in
            #expect(try await reader.toolbarRefresh() == .idle)

            try await reader.tapRefresh()
            try await reader.waitUntil { !reader.feedRequests().isEmpty }

            #expect(try await reader.toolbarRefresh() == .running)
            try await reader.waitUntilRefreshFinished()
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    @Test("Step 3: every subscribed feed is requested at the same time")
    func feedsAreRequestedAtTheSameTime() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let beta = Feed(title: "Beta", url: betaURL)
        let slow = Duration.seconds(1)
        try await withReader(feeds: [alpha, beta], answers: [
            alphaURL: .document(rss(["a1"]), delay: slow),
            betaURL: .document(rss(["b1"]), delay: slow),
        ]) { reader in
            let start = ContinuousClock.now
            try await reader.tapRefresh()
            try await reader.waitUntil { reader.feedRequests().count == 2 }

            // Both requests went out before the first answer, which takes a second, could arrive.
            #expect(ContinuousClock.now - start < .milliseconds(900))
            try await reader.waitUntilRefreshFinished()
            #expect(reader.store.articles.count == 2)
        }
    }

    // MARK: - A1 Feed unchanged, BR-009 Unchanged feeds

    @Test("A1, BR-009: an unchanged feed is not downloaded again, clears its error, keeps its articles and expires none")
    func unchangedFeedKeepsArticles() async throws {
        var alpha = Feed(title: "Alpha", url: alphaURL)
        alpha.etag = "\"v1\""
        alpha.lastError = "The server responded with HTTP 500."
        try await withReader(feeds: [alpha], articles: expiryCandidates(alpha),
                             answers: [alphaURL: .document("", status: 304)]) { reader in
            let before = reader.store.articles

            try await reader.refreshFromToolbar()

            #expect(reader.feedRequests().first?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
            #expect(reader.store.feed(withID: alpha.id)?.lastError == nil)
            #expect(try await reader.problemShown(forFeed: "Alpha") == nil)
            // BR-008: an unchanged feed expires no article, not even an expired one.
            #expect(reader.store.articles == before)
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    // MARK: - A2 Feed fails, BR-010, BR-011

    @Test("A2, BR-011: a failing feed records and shows its problem, the other feeds are refreshed, its articles stay",
          arguments: [
              FeedPublisherStub.Answer.document("Server error", status: 500),
              .failure(.timedOut),
              .failure(.cannotConnectToHost),
              .document("<!doctype html><html><body>No feed here</body></html>"),
          ])
    func failingFeedIsIsolated(answer: FeedPublisherStub.Answer) async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let beta = Feed(title: "Beta", url: betaURL)
        try await withReader(feeds: [alpha, beta], articles: expiryCandidates(alpha), answers: [
            alphaURL: answer,
            betaURL: .document(rss(["b1"])),
        ]) { reader in
            let before = reader.store.articles

            try await reader.refreshFromToolbar()

            // A2 step 1: the problem is recorded at the feed and shown with it in the subscription list.
            let problem = try #require(reader.store.feed(withID: alpha.id)?.lastError)
            #expect(!problem.isEmpty)
            #expect(try await reader.problemShown(forFeed: "Alpha") == problem)
            // BR-011: Beta is refreshed all the same and carries no problem.
            #expect(reader.store.articles.contains { $0.feedID == beta.id && $0.title == "Item b1" })
            #expect(reader.store.feed(withID: beta.id)?.lastError == nil)
            #expect(try await reader.problemShown(forFeed: "Beta") == nil)
            // Failure postconditions, BR-008: no article of Alpha changes its state or is removed.
            #expect(reader.store.articles.filter { $0.feedID == alpha.id } == before)
            // Step 8: the refresh finishes and the library is saved with the problem.
            #expect(try await reader.toolbarRefresh() == .idle)
            #expect(FeedStore(fileURL: reader.libraryURL).feed(withID: alpha.id)?.lastError == problem)
        }
    }

    @Test("BR-011: the problem is kept until a later refresh of the feed succeeds")
    func problemIsKeptUntilSuccess() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .failure(.timedOut)]) { reader in
            try await reader.refreshFromToolbar()
            let problem = try #require(reader.store.feed(withID: alpha.id)?.lastError)

            FeedPublisherStub.answer(alphaURL, with: .failure(.timedOut))
            try await reader.refreshFromToolbar()
            #expect(reader.store.feed(withID: alpha.id)?.lastError == problem)
            #expect(try await reader.problemShown(forFeed: "Alpha") == problem)

            FeedPublisherStub.answer(alphaURL, with: .document(rss(["a1"])))
            try await reader.refreshFromToolbar()
            #expect(reader.store.feed(withID: alpha.id)?.lastError == nil)
            #expect(try await reader.problemShown(forFeed: "Alpha") == nil)
        }
    }

    @Test("BR-010: the Feed Publisher is given 30 seconds to answer")
    func responseTimeLimit() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))]) { reader in
            try await reader.refreshFromToolbar()

            let request = try #require(reader.feedRequests().first)
            #expect(request.timeoutInterval == 30)
        }
    }

    // MARK: - A3 Feed damaged, BR-003

    @Test("A3, BR-003: a damaged feed adds and updates the articles before the damage, records the feed, and removes no article")
    func damagedFeedRemovesNoArticle() async throws {
        var alpha = Feed(title: "Alpha", url: alphaURL)
        alpha.lastError = "The server responded with HTTP 500."
        var stored = expiryCandidates(alpha)
        stored.append(StoredArticle(feed: alpha, key: "a1", title: "Old title", read: true, starred: true))
        let damaged = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Alpha</title><link>https://alpha.example/site/</link>
        <item><guid>a1</guid><title>Updated title</title></item>
        <item><guid>a2</guid><title>Readable new</title></item>
        <item><guid>a3</guid><title>Broken &
        """
        try await withReader(feeds: [alpha], articles: stored, answers: [
            alphaURL: .document(damaged, headers: ["ETag": "\"v2\""]),
        ]) { reader in
            try await reader.refreshFromToolbar()

            // A3 step 1: the articles before the damage are updated and added; the feed is recorded.
            let updated = try #require(reader.article("Updated title"))
            #expect(updated.isRead && updated.isStarred)
            #expect(reader.article("Readable new")?.isRead == false)
            let feed = try #require(reader.store.feed(withID: alpha.id))
            #expect(feed.etag == "\"v2\"")
            #expect(feed.siteURL == URL(string: "https://alpha.example/site/"))
            #expect(feed.lastError == nil)
            // A3 step 2, BR-003, BR-008: the expired article stays.
            #expect(reader.article("Expired") != nil)
            #expect(reader.store.articles.count == stored.count + 1)
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    @Test("BR-003: RSS 2.0, RSS 1.0, and Atom feeds are refreshed")
    func supportedFormatsAreRefreshed() async throws {
        let rdfURL = URL(string: "https://rdf.example/rss")!
        let atomURL = URL(string: "https://atom.example/atom")!
        let rssFeed = Feed(title: "RSS", url: alphaURL)
        let rdfFeed = Feed(title: "RDF", url: rdfURL)
        let atomFeed = Feed(title: "Atom", url: atomURL)
        let rdf = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
          <channel rdf:about="https://rdf.example/"><title>RDF Feed</title><link>https://rdf.example/</link></channel>
          <item rdf:about="https://rdf.example/1"><title>RDF Item</title><link>https://rdf.example/1</link></item>
        </rdf:RDF>
        """
        let atom = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Feed</title><link href="https://atom.example/"/>
          <entry><id>urn:1</id><title>Atom Item</title></entry>
        </feed>
        """
        try await withReader(feeds: [rssFeed, rdfFeed, atomFeed], answers: [
            alphaURL: .document(rss(["a1"])), rdfURL: .document(rdf), atomURL: .document(atom),
        ]) { reader in
            try await reader.refreshFromToolbar()

            #expect(reader.article("Item a1")?.feedID == rssFeed.id)
            #expect(reader.article("RDF Item")?.feedID == rdfFeed.id)
            #expect(reader.article("Atom Item")?.feedID == atomFeed.id)
            #expect(reader.store.feeds.allSatisfy { $0.lastError == nil })
        }
    }

    // MARK: - A4 Feed removed during refresh

    @Test("A4: the result of a feed unsubscribed while its refresh was running is discarded")
    func resultOfRemovedFeedIsDiscarded() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let beta = Feed(title: "Beta", url: betaURL)
        try await withReader(feeds: [alpha, beta], answers: [
            alphaURL: .document(rss(["a1", "a2"]), delay: .milliseconds(800)),
            betaURL: .document(rss(["b1"])),
        ]) { reader in
            try await reader.tapRefresh()
            try await reader.waitUntil { reader.feedRequests().count == 2 }
            try reader.store.removeFeed(id: alpha.id)

            try await reader.waitUntilRefreshFinished()
            try await Task.sleep(for: .milliseconds(900))

            #expect(reader.store.feeds.map(\.title) == ["Beta"])
            #expect(reader.store.articles.map(\.title) == ["Item b1"])
            let reloaded = FeedStore(fileURL: reader.libraryURL)
            #expect(reloaded.feeds.map(\.title) == ["Beta"])
            #expect(reloaded.articles.map(\.title) == ["Item b1"])
        }
    }

    // MARK: - A5 Refresh already running, BR-002 One refresh at a time

    @Test("A5, BR-002: a request while a refresh runs is ignored, and the refresh action is disabled meanwhile")
    func requestWhileRunningIsIgnored() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]), delay: .milliseconds(800))]) { reader in
            try await reader.tapRefresh()
            try await reader.waitUntil { !reader.feedRequests().isEmpty }

            await #expect(throws: (any Error).self) { try await reader.tapRefreshNow() }
            await reader.store.refreshAll()

            try await reader.waitUntilRefreshFinished()
            try await Task.sleep(for: .milliseconds(300))
            #expect(reader.feedRequests().count == 1)
        }
    }

    @Test("A5, BR-002: an import's request while a refresh runs starts one more refresh afterwards, at most one waits")
    func importRequestWaitsForRunningRefresh() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]), delay: .milliseconds(600))]) { reader in
            try await reader.tapRefresh()
            try await reader.waitUntil { !reader.feedRequests().isEmpty }

            // Two imports ask while the refresh runs: one more refresh follows, the second request is not kept.
            await reader.store.refreshAll(requestedByImport: true)
            await reader.store.refreshAll(requestedByImport: true)
            #expect(reader.feedRequests().count == 1)

            try await reader.waitUntil(timeout: .seconds(5)) { reader.feedRequests().count == 2 }
            try await reader.waitUntilRefreshFinished()
            try await Task.sleep(for: .milliseconds(900))
            #expect(reader.feedRequests().count == 2)
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    // MARK: - A6 Library holds no feed

    @Test("A6: a refresh of a library without feeds is ignored")
    func emptyLibraryIgnoresRefresh() async throws {
        try await withReader(feeds: [], answers: [:]) { reader in
            try await reader.tapRefresh()
            try await Task.sleep(for: .milliseconds(300))

            #expect(reader.feedRequests().isEmpty)
            #expect(!reader.store.isRefreshing)
            #expect(try await reader.toolbarRefresh() == .idle)
        }
    }

    // MARK: - A7 Library cannot be saved, BR-012 Unsaved refresh is kept

    @Test("A7, BR-012: a refresh that cannot be saved stays in the library, finishes silently, and goes out with the next save")
    func unsavedRefreshIsKept() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))]) { reader in
            let libraryBefore = try Data(contentsOf: reader.libraryURL)
            reader.makeLibraryUnwritable()

            try await reader.refreshFromToolbar()

            // A7 step 1: the refreshed articles stay in the library.
            #expect(reader.article("Item a1") != nil)
            #expect(try Data(contentsOf: reader.libraryURL) == libraryBefore)
            // A7 step 2: the refresh shows it has finished; BR-012: the Reader is not told.
            #expect(try await reader.toolbarRefresh() == .idle)
            #expect(try await reader.showsAlert() == false)

            // BR-012: the next save writes them.
            reader.makeLibraryWritable()
            reader.store.save()
            #expect(FeedStore(fileURL: reader.libraryURL).articles.map(\.title) == ["Item a1"])
        }
    }

    // MARK: - BR-001 Refresh schedule

    @Test("BR-001: the Scheduler refreshes at once when the app's window opens, then every refresh interval")
    func schedulerRefreshesAtStartAndEveryInterval() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))],
                             refreshInterval: .milliseconds(800), scheduled: true) { reader in
            try await reader.waitUntil(timeout: .milliseconds(400)) { reader.feedRequests().count == 1 }
            try await reader.waitUntilRefreshFinished()
            #expect(reader.article("Item a1") != nil)
            try await reader.waitUntil(timeout: .seconds(2)) { reader.feedRequests().count == 2 }
        }
    }

    @Test("BR-001: the refresh interval is 30 minutes")
    func refreshIntervalIsThirtyMinutes() throws {
        // The app creates its store with the default interval. The store keeps the interval private, so it is read
        // by reflection rather than by waiting 30 minutes.
        let file = FileManager.default.temporaryDirectory.appending(path: "UC003-\(UUID().uuidString).json")
        let store = FeedStore(fileURL: file)
        let interval = Mirror(reflecting: store).children.first { $0.label == "refreshInterval" }?.value as? Duration
        #expect(interval == .seconds(30 * 60))
    }

    #if os(iOS)
    @Test("BR-001: no refresh runs while the app is in the background; one that fell due follows on return to the foreground")
    func dueRefreshFollowsOnReturnToForeground() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))],
                             refreshInterval: .milliseconds(600), scheduled: true) { reader in
            try await reader.waitUntil { reader.feedRequests().count == 1 }

            reader.moveTo(.background)
            try await Task.sleep(for: .milliseconds(1200))
            #expect(reader.feedRequests().count == 1)

            reader.moveTo(.active)
            try await reader.waitUntil(timeout: .milliseconds(300)) { reader.feedRequests().count == 2 }
        }
    }

    @Test("BR-001: returning to the foreground before the interval elapsed does not refresh early")
    func returnBeforeDueWaitsForInterval() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))],
                             refreshInterval: .seconds(1), scheduled: true) { reader in
            try await reader.waitUntil { reader.feedRequests().count == 1 }

            reader.moveTo(.background)
            try await Task.sleep(for: .milliseconds(200))
            reader.moveTo(.active)
            try await Task.sleep(for: .milliseconds(400))
            #expect(reader.feedRequests().count == 1)

            try await reader.waitUntil(timeout: .seconds(1)) { reader.feedRequests().count == 2 }
        }
    }
    #endif

    @Test("BR-001: the Reader can refresh at any time from the toolbar")
    func readerRefreshesFromToolbar() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]))]) { reader in
            try await reader.refreshFromToolbar()
            #expect(reader.feedRequests().count == 1)
            #expect(reader.article("Item a1") != nil)
        }
    }

    @Test("BR-001: the toolbar's Refresh names the shortcut ⌘R only on the Mac, where it exists")
    func toolbarHintNamesShortcutOnlyOnMac() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [:]) { reader in
            let help = try await reader.toolbarRefreshHelp()
            #if os(macOS)
            #expect(help == "Refresh All (⌘R)")
            #else
            #expect(help == "Refresh All")
            #endif
        }
    }

    #if os(macOS)
    @Test("BR-001, BR-002: on the Mac the Reader refreshes from the Feeds menu or with ⌘R, disabled while a refresh runs")
    func readerRefreshesFromMenu() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(rss(["a1"]), delay: .milliseconds(800))]) { reader in
            let menu = MenuCommand(store: reader.store, menu: "Feeds", title: "Refresh All")
            #expect(try menu.isDisabled() == false)
            // BR-001: the menu command carries the keyboard shortcut ⌘R.
            let shortcut = try #require(try menu.keyboardShortcut())
            #expect(shortcut.key == KeyEquivalent("r"))
            #expect(shortcut.modifiers == .command)

            try menu.choose()
            try await reader.waitUntil { reader.feedRequests().count == 1 }
            // BR-002: the menu command is disabled while the refresh runs.
            #expect(try menu.isDisabled() == true)

            try await reader.waitUntilRefreshFinished()
            #expect(reader.article("Item a1") != nil)
            #expect(try menu.isDisabled() == false)
        }
    }
    #endif

    #if os(iOS)
    @Test("BR-001: on iPhone and iPad the Reader refreshes by pulling down the subscription list or the article list")
    func readerRefreshesByPullingDown() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let stored = [StoredArticle(feed: alpha, key: "a0", title: "Listed")]
        try await withReader(feeds: [alpha], articles: stored, answers: [alphaURL: .document(rss(["a0", "a1"]))]) { reader in
            try await reader.pullDown(in: .sidebar)
            try await reader.waitUntil { reader.feedRequests().count == 1 }
            try await reader.waitUntilRefreshFinished()
            #expect(reader.article("Item a1") != nil)

            try await reader.pullDown(in: .articles)
            try await reader.waitUntil { reader.feedRequests().count == 2 }
            try await reader.waitUntilRefreshFinished()
        }
    }
    #endif

    // MARK: - BR-004 Article identity

    @Test("BR-004: articles are identified by guid, else link, else title; items without any are skipped, repeats taken once")
    func articleIdentity() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let stored = [
            StoredArticle(feed: alpha, key: "https://alpha.example/by-link", title: "Known by link", read: true),
            StoredArticle(feed: alpha, key: "Known by title", title: "Known by title", starred: true),
        ]
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Alpha</title>
        <item><link>https://alpha.example/by-link</link><title>Link item renamed</title></item>
        <item><title>Known by title</title><description>Now with a summary</description></item>
        <item><guid>g1</guid><link>https://alpha.example/shared</link><title>Guid one</title></item>
        <item><guid>g2</guid><link>https://alpha.example/shared</link><title>Guid two</title></item>
        <item><guid>g1</guid><title>Guid one repeated</title></item>
        <item><description>No identifier at all</description></item>
        </channel></rss>
        """
        try await withReader(feeds: [alpha], articles: stored, answers: [alphaURL: .document(feed)]) { reader in
            try await reader.refreshFromToolbar()

            // The stored articles are found again by link and by title and updated, keeping their states.
            #expect(reader.article("Link item renamed")?.id == reader.articleID(alpha, "https://alpha.example/by-link"))
            #expect(reader.article("Link item renamed")?.isRead == true)
            #expect(reader.article("Known by title")?.snippet == "Now with a summary")
            #expect(reader.article("Known by title")?.isStarred == true)
            // The guid wins over the shared link; the repeated g1 is taken once; the item without identity is skipped.
            #expect(reader.store.articles.map(\.title).sorted()
                    == ["Guid one", "Guid two", "Known by title", "Link item renamed"])
        }
    }

    // MARK: - BR-005 Article title

    @Test("BR-005: the title is plain text of at most 500 characters, cut to 499 and an ellipsis, \"(Untitled)\" when missing")
    func articleTitle() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let exact = String(repeating: "a", count: 500)
        let long = String(repeating: "b", count: 501)
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Alpha</title>
        <item><guid>exact</guid><title>\(exact)</title></item>
        <item><guid>long</guid><title>\(long)</title></item>
        <item><guid>html</guid><title>&lt;b&gt;Bold&lt;/b&gt; &amp;amp; plain</title></item>
        <item><guid>untitled</guid><link>https://alpha.example/untitled</link></item>
        </channel></rss>
        """
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(feed)]) { reader in
            try await reader.refreshFromToolbar()

            @MainActor func title(_ key: String) -> String? {
                reader.store.article(withID: reader.articleID(alpha, key))?.title
            }
            #expect(title("exact") == exact)
            #expect(title("long") == String(repeating: "b", count: 499) + "\u{2026}")
            #expect(title("html") == "Bold & plain")
            #expect(title("untitled") == "(Untitled)")
        }
    }

    // MARK: - BR-006 Article snippet and content

    @Test("BR-006: content is the full content, else the summary; the snippet is the plain summary, else the content, at most 280 characters")
    func articleSnippetAndContent() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let exact = String(repeating: "e", count: 280)
        let long = String(repeating: "x", count: 300)
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>Alpha</title>
        <item><guid>both</guid><title>Both</title><description>&lt;b&gt;Short&lt;/b&gt; summary</description>
          <content:encoded><![CDATA[<p>Full content</p>]]></content:encoded></item>
        <item><guid>summary</guid><title>Summary only</title><description>&lt;p&gt;\(exact)&lt;/p&gt;</description></item>
        <item><guid>content</guid><title>Content only</title><content:encoded><![CDATA[<p>\(long)</p>]]></content:encoded></item>
        </channel></rss>
        """
        try await withReader(feeds: [alpha], answers: [alphaURL: .document(feed)]) { reader in
            try await reader.refreshFromToolbar()

            #expect(reader.article("Both")?.contentHTML == "<p>Full content</p>")
            #expect(reader.article("Both")?.snippet == "Short summary")
            #expect(reader.article("Summary only")?.contentHTML == "<p>\(exact)</p>")
            #expect(reader.article("Summary only")?.snippet == exact)
            #expect(reader.article("Content only")?.contentHTML == "<p>\(long)</p>")
            #expect(reader.article("Content only")?.snippet == String(repeating: "x", count: 279) + "\u{2026}")
        }
    }

    // MARK: - BR-007 State survives updates

    @Test("BR-007: updating an article keeps read and starred, and keeps its date when the feed no longer gives one",
          arguments: [(true, true), (true, false), (false, true), (false, false)])
    func stateSurvivesUpdates(read: Bool, starred: Bool) async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let published = date("2026-11-01T08:00:00Z")
        let stored = [StoredArticle(feed: alpha, key: "a1", title: "Before", published: published,
                                    read: read, starred: starred)]
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Alpha</title><item><guid>a1</guid><title>After</title></item></channel></rss>
        """
        try await withReader(feeds: [alpha], articles: stored, answers: [alphaURL: .document(feed)]) { reader in
            try await reader.refreshFromToolbar()

            let article = try #require(reader.article("After"))
            #expect(article.isRead == read)
            #expect(article.isStarred == starred)
            #expect(article.published == published)
        }
    }

    // MARK: - Step 7, BR-008 Article retention

    @Test("Step 7, BR-008: only read, unstarred articles first fetched over 30 days ago that left their complete feed expire")
    func expiredArticlesAreRemoved() async throws {
        let alpha = Feed(title: "Alpha", url: alphaURL)
        let beta = Feed(title: "Beta", url: betaURL)
        var stored = expiryCandidates(alpha)
        stored.append(StoredArticle(feed: alpha, key: "present", title: "Still in feed", fetchedDaysAgo: 31, read: true))
        // An expired-looking article of a feed that fails keeps its place (BR-008).
        stored.append(StoredArticle(feed: beta, key: "old", title: "Beta old", fetchedDaysAgo: 31, read: true))
        try await withReader(feeds: [alpha, beta], articles: stored, answers: [
            alphaURL: .document(rss(["present"])),
            betaURL: .failure(.timedOut),
        ]) { reader in
            try await reader.refreshFromToolbar()

            #expect(reader.article("Expired") == nil)
            #expect(reader.article("Starred old") != nil)
            #expect(reader.article("Unread old") != nil)
            #expect(reader.article("Read recent") != nil)
            #expect(reader.store.article(withID: reader.articleID(alpha, "present")) != nil)
            #expect(reader.article("Beta old") != nil)
            #expect(FeedStore(fileURL: reader.libraryURL).articles.contains { $0.title == "Expired" } == false)
        }
    }
}

// MARK: - Test data

private let alphaURL = URL(string: "https://alpha.uc003.example/feed.xml")!
private let betaURL = URL(string: "https://beta.uc003.example/feed.xml")!

private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// An RSS 2.0 feed whose items are `Item <key>`, identified by the key.
private func rss(_ keys: [String]) -> String {
    let items = keys.map { "<item><guid>\($0)</guid><title>Item \($0)</title></item>" }.joined()
    return #"<?xml version="1.0"?><rss version="2.0"><channel><title>Feed</title>\#(items)</channel></rss>"#
}

/// An article as the library file holds it.
private struct StoredArticle {
    var feed: Feed
    var key: String
    var title: String
    var link: String?
    var author: String?
    var content = "<p>Stored</p>"
    var published: Date?
    var fetchedDaysAgo: Double = 1
    var read = false
    var starred = false

    var json: [String: Any] {
        var value: [String: Any] = [
            "id": "\(feed.id.uuidString)|\(key)", "feedID": feed.id.uuidString, "title": title,
            "contentHTML": content, "snippet": "Stored",
            "fetched": Date.now.addingTimeInterval(-fetchedDaysAgo * 86_400).timeIntervalSinceReferenceDate,
            "isRead": read, "isStarred": starred,
        ]
        if let link { value["link"] = link }
        if let author { value["author"] = author }
        if let published { value["published"] = published.timeIntervalSinceReferenceDate }
        return value
    }
}

/// Articles of `feed` that are absent from every feed document of the tests: only "Expired" meets every condition of
/// BR-008. The boundary values 31 and 29 days lie either side of the 30-day limit.
private func expiryCandidates(_ feed: Feed) -> [StoredArticle] {
    [
        StoredArticle(feed: feed, key: "expired", title: "Expired", fetchedDaysAgo: 31, read: true),
        StoredArticle(feed: feed, key: "starred-old", title: "Starred old", fetchedDaysAgo: 31, read: true, starred: true),
        StoredArticle(feed: feed, key: "unread-old", title: "Unread old", fetchedDaysAgo: 31),
        StoredArticle(feed: feed, key: "read-recent", title: "Read recent", fetchedDaysAgo: 29, read: true),
    ]
}

// MARK: - Test harness

private enum RefreshAction: Equatable {
    /// The Refresh button is enabled and labelled Refresh.
    case idle
    /// The button shows progress and is disabled.
    case running
    case other(String)
}

private enum PulledList {
    case sidebar
    case articles
}

/// The scene phase the hosted window sees, which the test changes as the system would when the app moves between
/// foreground and background.
@MainActor
@Observable
private final class ScenePhaseBox {
    var phase: ScenePhase = .active
}

/// The main window with the Scheduler attached as the app attaches it (`refreshSchedule`), under a scene phase the
/// test controls.
private struct ScheduledWindow: View {
    let content: ContentView
    let store: FeedStore
    let scene: ScenePhaseBox

    var body: some View {
        content
            .refreshSchedule(store)
            .environment(\.scenePhase, scene.phase)
    }
}

/// Drives one hosted main window.
@MainActor
private struct Reader {
    let view: ContentView
    let store: FeedStore
    let libraryURL: URL
    let scene: ScenePhaseBox

    /// The app moves to the foreground or background.
    func moveTo(_ phase: ScenePhase) {
        scene.phase = phase
    }

    func articleID(_ feed: Feed, _ key: String) -> Article.ID {
        "\(feed.id.uuidString)|\(key)"
    }

    func article(_ title: String) -> Article? {
        store.articles.first { $0.title == title }
    }

    /// The feed requests the Feed Publisher received, without the favicon requests of the subscription list.
    func feedRequests() -> [URLRequest] {
        FeedPublisherStub.receivedRequests.filter { $0.url?.lastPathComponent != "favicon.ico" }
    }

    /// Inspects the live window. The store is put into the inspected hierarchy again, so the child views
    /// ViewInspector builds find it in their environment, as they do in the app.
    private func inspect(_ body: @escaping @MainActor @Sendable (InspectableView<ViewType.ClassifiedView>) async throws -> Void) async throws {
        let store = store
        try await view.inspection.inspect { view in
            try await body(try view.actualView().environment(store).inspect())
        }
    }

    private static func refreshButton(in view: InspectableView<ViewType.ClassifiedView>) throws -> InspectableView<ViewType.Button> {
        let toolbar = try view.find(ArticleListView.self).find(ViewType.Toolbar.self)
        for button in toolbar.findAll(ViewType.Button.self) {
            let label = try button.labelView()
            if (try? label.find(text: "Refresh")) != nil || (try? label.find(ViewType.ProgressView.self)) != nil {
                return button
            }
        }
        struct NoRefreshButton: Error {}
        throw NoRefreshButton()
    }

    /// The state of the toolbar's Refresh button.
    func toolbarRefresh() async throws -> RefreshAction {
        let box = ResultBox(RefreshAction.other("not inspected"))
        try await inspect { view in
            let button = try Self.refreshButton(in: view)
            let label = try button.labelView()
            let progress = (try? label.find(ViewType.ProgressView.self)) != nil
            let titled = (try? label.find(text: "Refresh")) != nil
            box.value = switch (titled, progress, button.isDisabled()) {
            case (true, false, false): .idle
            case (false, true, true): .running
            case let state: .other("titled \(state.0), progress \(state.1), disabled \(state.2)")
            }
        }
        return box.value
    }

    /// The help text of the toolbar's Refresh button.
    func toolbarRefreshHelp() async throws -> String {
        let box = ResultBox("")
        try await inspect { view in
            box.value = try Self.refreshButton(in: view).help().string()
        }
        return box.value
    }

    /// Step 1: the Reader taps Refresh in the toolbar.
    func tapRefresh() async throws {
        try await tapRefreshNow()
    }

    /// Taps Refresh; throws when the button is disabled.
    func tapRefreshNow() async throws {
        try await inspect { view in
            try Self.refreshButton(in: view).tap()
        }
    }

    /// The Reader taps Refresh and waits until every feed has been requested and the refresh has finished.
    func refreshFromToolbar() async throws {
        let before = feedRequests().count
        try await tapRefresh()
        try await waitUntil { feedRequests().count >= before + store.feeds.count }
        try await waitUntilRefreshFinished()
    }

    func waitUntilRefreshFinished() async throws {
        try await waitUntil { !store.isRefreshing }
        try await Task.sleep(for: .milliseconds(100))
    }

    func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The condition was not met within \(timeout)")
    }

    #if os(iOS)
    /// The Reader pulls down a list.
    func pullDown(in list: PulledList) async throws {
        try await inspect { view in
            // ViewInspector calls the refresh action outside the main actor; the inspected view is not shared.
            nonisolated(unsafe) let target = switch list {
            case .sidebar: try view.find(SidebarView.self).find(ViewType.List.self)
            case .articles: try view.find(ArticleListView.self).find(ViewType.List.self)
            }
            try await target.callRefreshable()
        }
    }
    #endif

    /// The problem the subscription list shows with the feed, or nil when it shows none.
    func problemShown(forFeed title: String) async throws -> String? {
        let index = try #require(store.feeds.firstIndex { $0.title == title })
        let box = ResultBox<String?>(nil)
        try await inspect { view in
            let rows = try view.find(SidebarView.self).find(ViewType.ForEach.self)
            box.value = try problem(inRow: Array(rows)[index])
        }
        return box.value
    }

    /// Whether the sidebar shows an alert.
    func showsAlert() async throws -> Bool {
        let box = ResultBox(false)
        try await inspect { view in
            box.value = (try? view.find(SidebarView.self).find(ViewType.Alert.self)) != nil
        }
        return box.value
    }

    func makeLibraryUnwritable() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: libraryURL.deletingLastPathComponent().path()
        )
    }

    func makeLibraryWritable() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: libraryURL.deletingLastPathComponent().path()
        )
    }
}

#if os(macOS)
/// A command of the Mac's menu bar (`FeedCommands`). ViewInspector cannot inspect `Commands`, so the menu's content
/// view is taken from the command body by reflection and the button with `title` is inspected on its own. The body is
/// built anew for every look, as SwiftUI does when the store changes.
@MainActor
private struct MenuCommand {
    let store: FeedStore
    let menu: String
    let title: String

    private struct NoMenuCommand: Error, CustomStringConvertible {
        let description: String
    }

    private func button() throws -> InspectableView<ViewType.Button> {
        try find(in: menuContent())
    }

    private func menuContent() throws -> any View {
        func menuContent(in value: Any, depth: Int) -> (any View)? {
            guard depth < 24 else { return nil }
            let mirror = Mirror(reflecting: value)
            if String(describing: type(of: value)).hasPrefix("CommandMenu<"),
               String(describing: value).contains(menu),
               let content = mirror.children.first(where: { $0.label == "content" })?.value as? any View {
                return content
            }
            for child in mirror.children {
                if let found = menuContent(in: child.value, depth: depth + 1) { return found }
            }
            return nil
        }
        guard let content = menuContent(in: FeedCommands(store: store).body, depth: 0) else {
            throw NoMenuCommand(description: "No menu \(menu) in FeedCommands")
        }
        return content
    }

    private func find<V: View>(in view: V) throws -> InspectableView<ViewType.Button> {
        for button in try view.inspect().findAll(ViewType.Button.self)
        where (try? button.labelView().text().string()) == title {
            return button
        }
        throw NoMenuCommand(description: "No command \(title) in menu \(menu)")
    }

    func isDisabled() throws -> Bool {
        try button().isDisabled()
    }

    /// The keyboard shortcut of the command. ViewInspector does not read shortcuts, so the modifier that wraps the
    /// command's button is searched by reflection; the menu must hold this one command for the answer to be its own.
    func keyboardShortcut() throws -> KeyboardShortcut? {
        let content = try menuContent()
        func buttons<V: View>(in view: V) throws -> Int { try view.inspect().findAll(ViewType.Button.self).count }
        guard try buttons(in: content) == 1 else {
            throw NoMenuCommand(description: "Menu \(menu) holds more than one command")
        }
        _ = try button()
        func shortcut(in value: Any, depth: Int) -> KeyboardShortcut? {
            guard depth < 24 else { return nil }
            if let found = value as? KeyboardShortcut { return found }
            for child in Mirror(reflecting: value).children {
                if let found = shortcut(in: child.value, depth: depth + 1) { return found }
            }
            return nil
        }
        return shortcut(in: content, depth: 0)
    }

    /// The Reader chooses the command; throws when it is disabled.
    func choose() throws {
        try button().tap()
    }
}
#endif

private final class ResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// The problem a subscription-list row shows: the warning symbol's accessibility label on the Mac, and on iPhone and
/// iPad also the caption under the title. ViewInspector cannot look inside a badged row, so the row's view is taken
/// from it by reflection and inspected on its own.
@MainActor
private func problem(inRow row: InspectableView<ViewType.ClassifiedView>) throws -> String? {
    func feedRow(in value: Any, depth: Int) -> (any View)? {
        guard depth < 24 else { return nil }
        if String(describing: type(of: value)) == "FeedRow", let view = value as? any View { return view }
        for child in Mirror(reflecting: value).children {
            if let found = feedRow(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
    guard let feedRow = feedRow(in: row, depth: 0) else {
        Issue.record("The row holds no FeedRow")
        return nil
    }
    func inspect<V: View>(_ view: V) throws -> String? {
        let inspected = try view.inspect()
        let symbols = inspected.findAll(ViewType.Image.self).compactMap { image -> String? in
            guard (try? image.actualImage().name()) == "exclamationmark.triangle.fill" else { return nil }
            return try? image.accessibilityLabel().string()
        }
        #if os(iOS)
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        let caption = texts.count > 1 ? texts[1] : nil
        if let symbol = symbols.first {
            #expect(caption == symbol, "The problem is written under the title on iPhone and iPad")
        }
        #endif
        return symbols.first
    }
    return try inspect(feedRow)
}

/// Opens the main window over a fresh library in a temporary folder that holds `feeds` and `articles`, written as
/// the file FeedStore keeps, with the Feed Publisher answering from `answers`. With `scheduled`, the window carries
/// the Scheduler as in the app; otherwise no refresh starts unless the test asks for one.
@MainActor
private func withReader(
    feeds: [Feed],
    articles: [StoredArticle] = [],
    answers: [URL: FeedPublisherStub.Answer],
    refreshInterval: Duration = .seconds(3600),
    scheduled: Bool = false,
    _ body: @MainActor (Reader) async throws -> Void
) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "UC003-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path())
        try? FileManager.default.removeItem(at: dir)
    }
    let libraryURL = dir.appending(path: "library.json")
    let library: [String: Any] = [
        "feeds": try JSONSerialization.jsonObject(with: JSONEncoder().encode(feeds)),
        "articles": articles.map(\.json),
    ]
    try JSONSerialization.data(withJSONObject: library).write(to: libraryURL)
    let store = FeedStore(fileURL: libraryURL, refreshInterval: refreshInterval)
    try #require(store.feeds.map(\.id) == feeds.map(\.id))
    try #require(store.articles.count == articles.count)

    try await FeedPublisherStub.withAnswers(answers) {
        let view = ContentView()
        let scene = ScenePhaseBox()
        let reader = Reader(view: view, store: store, libraryURL: libraryURL, scene: scene)
        let window: AnyView = scheduled
            ? AnyView(ScheduledWindow(content: view, store: store, scene: scene))
            : AnyView(view)
        try await ViewHosting.host(window.environment(store).frame(width: 1000, height: 600)) {
            try await body(reader)
            // The schedule stops and a refresh still under way finishes before the stub goes to the next suite.
            store.pauseScheduledRefresh()
            try await reader.waitUntil(timeout: .seconds(5)) { !store.isRefreshing }
        }
    }
}
