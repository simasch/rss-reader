import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ViewInspector

/// UC-006 Import Subscriptions, tested against the real FeedStore and a temporary library file.
///
/// The Reader starts an import with Import OPML… in the subscription list's toolbar menu on iPhone and iPad, and in
/// the File menu on the Mac. On iPhone and iPad the tests choose the entry, check the file importer it presents, and
/// cancel it (A3). On the Mac the tests check the open panel the Import OPML… command presents (step 2). Choosing the
/// command itself (step 1 on the Mac) is not tested, an accepted limitation: a `CommandGroup` keeps its buttons in a
/// closure reflection cannot open, and the command runs the panel and its `NSAlert` modally. Neither platform's file selection can be
/// completed in a test either: SwiftUI's file importer crashes when its completion is called outside a real
/// presentation (iOS 18 and 27). So the selected file is imported with `FeedStore.importOPML(from:)`, the call both
/// entry points make with the file the Reader selected, and the business rules are tested through it on both
/// platforms. What both entry points do with the selected file — the refresh of step 7 and the messages of A1 and A4 —
/// is the shared `SubscriptionImport`: on iPhone and iPad it is driven through the subscription list, whose OPML Error
/// alert shows the message; on the Mac it is called directly, since the command's `NSAlert` is modal.
@MainActor
@Suite("UC-006 Import Subscriptions", .serialized)
struct UC006ImportSubscriptionsTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: new feeds are added with title, address, and website, sorted by title, and saved")
    func mainSuccessScenario() async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        let file = opml("""
        <outline text="Charlie" title="Charlie" type="rss" xmlUrl="https://charlie.example/feed.xml" htmlUrl="https://charlie.example/"/>
        <outline text="Alpha" title="Alpha" type="rss" xmlUrl="https://alpha.example/feed.xml" htmlUrl="https://alpha.example/"/>
        """)
        try await withImporter(feeds: [existing], answers: feedAnswers) { importer in
            let outcome = try await importer.importSelected(try importer.write(file))

            #expect(outcome.importedCount == 2)
            // Steps 4 and 5: every entry is added with its title, feed address, and website, and the list is sorted.
            #expect(importer.store.feeds.map(\.title) == ["Alpha", "Charlie", "Delta"])
            let alpha = try #require(importer.feed("Alpha"))
            #expect(alpha.url == alphaURL)
            #expect(alpha.siteURL == URL(string: "https://alpha.example/"))
            let charlie = try #require(importer.feed("Charlie"))
            #expect(charlie.url == charlieURL)
            #expect(charlie.siteURL == URL(string: "https://charlie.example/"))
            // Step 6: the library is saved.
            let reloaded = FeedStore(fileURL: importer.libraryURL)
            #expect(reloaded.feeds.map(\.title) == ["Alpha", "Charlie", "Delta"])
            #expect(reloaded.feeds.map(\.url) == [alphaURL, charlieURL, deltaURL])
            #expect(reloaded.feeds.map(\.siteURL) == [alpha.siteURL, charlie.siteURL, nil])
            // Step 7: all feeds are refreshed, the imported and the subscribed ones.
            let refresh = try #require(outcome.refresh)
            await refresh.value
            #expect(Set(importer.feedRequests()) == [alphaURL, charlieURL, deltaURL])
            let refreshedFeeds = Set(importer.store.articles.map(\.feedID))
            #expect(refreshedFeeds == Set(importer.store.feeds.map(\.id)))
            #if os(iOS)
            #expect(try await importer.alertMessages().isEmpty)
            #endif
        }
    }

    @Test("Step 7: an import during a running refresh queues the refresh of all feeds behind it (UC-003 BR-002)")
    func refreshIsQueuedBehindRunningRefresh() async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        var answers = feedAnswers
        answers[deltaURL] = .document(feedDocument(title: "Delta", site: nil), delay: .milliseconds(500))
        let file = opml(#"<outline text="Alpha" xmlUrl="https://alpha.example/feed.xml"/>"#)
        try await withImporter(feeds: [existing], answers: answers) { importer in
            let store = importer.store
            let running = Task { await store.refreshAll() }
            try await importer.waitUntil { store.isRefreshing }

            let outcome = try await importer.importSelected(try importer.write(file))

            #expect(outcome.importedCount == 1)
            // The running refresh did not include the imported feed yet.
            #expect(!importer.feedRequests().contains(alphaURL))
            await running.value
            await outcome.refresh?.value
            try await importer.waitUntil { !store.isRefreshing }
            // The queued refresh fetched all feeds, the imported one included.
            #expect(importer.feedRequests().filter { $0 == deltaURL }.count == 2)
            #expect(importer.feedRequests().filter { $0 == alphaURL }.count == 1)
            let alpha = try #require(importer.feed("Alpha"))
            #expect(store.articles.contains { $0.feedID == alpha.id })
        }
    }

    #if os(iOS)
    @Test("Step 1, step 2: the Reader chooses Import OPML… in the subscription list's menu, and the system asks for an OPML file")
    func readerChoosesImportAndIsAskedForFile() async throws {
        try await withImporter(feeds: []) { importer in
            #expect(try await importer.fileDialog() == nil)

            try await importer.chooseImport()

            let dialog = try #require(try await importer.fileDialog())
            // The unhosted test bundle declares no OPML type, so the type is recognized by its file name extension.
            #expect(dialog.allowedContentTypes.contains { $0.tags[.filenameExtension]?.contains("opml") == true })
            #expect(dialog.allowsMultipleSelection == false)
        }
    }
    #else
    @Test("Step 2: the Import OPML… command asks for one OPML file")
    func importCommandAsksForFile() {
        let panel = FeedCommands.makeImportPanel()

        // The unhosted test bundle declares no OPML type, so the type is recognized by its file name extension.
        #expect(panel.allowedContentTypes.contains { $0.tags[.filenameExtension]?.contains("opml") == true })
        #expect(panel.allowsMultipleSelection == false)
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
    }
    #endif


    // MARK: - A1 Unreadable file

    @Test("A1, BR-001: a file that cannot be read as an OPML subscription list shows the message, adds no feed, and leaves the library unchanged",
          arguments: UnreadableFile.allCases)
    func unreadableFileAddsNothing(file: UnreadableFile) async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        try await withImporter(feeds: [existing], answers: feedAnswers) { importer in
            let before = try Data(contentsOf: importer.libraryURL)

            let outcome = try await importer.importSelected(try file.write(in: importer.folder))

            // A1 step 1: the same message, whatever kept the file from being read.
            #expect(outcome.message == "The file is not an OPML subscription list.")
            #if os(iOS)
            #expect(try await importer.alertMessages() == ["The file is not an OPML subscription list."])
            #endif
            // Failure postcondition: no feed is added; the library is unchanged; nothing is refreshed.
            #expect(importer.store.feeds.map(\.url) == [deltaURL])
            #expect(try Data(contentsOf: importer.libraryURL) == before)
            #expect(outcome.refresh == nil)
            #expect(importer.feedRequests().isEmpty)
        }
    }

    // MARK: - A2 No new feeds

    @Test("A2: a file whose feeds are all subscribed, or that holds no entry with a valid feed address, leaves the library unchanged",
          arguments: NothingNewFile.allCases)
    func nothingNewLeavesLibraryUnchanged(file: NothingNewFile) async throws {
        let existing = [Feed(title: "Alpha", url: alphaURL), Feed(title: "Delta", url: deltaURL)]
        try await withImporter(feeds: existing, answers: feedAnswers) { importer in
            let feedsBefore = importer.store.feeds
            let before = try Data(contentsOf: importer.libraryURL)

            let outcome = try await importer.importSelected(try importer.write(opml(file.outlines)))

            // A2 step 1: the library is unchanged and no refresh is started.
            #expect(outcome.isNoNewFeeds)
            #expect(importer.store.feeds == feedsBefore)
            #expect(try Data(contentsOf: importer.libraryURL) == before)
            #expect(outcome.refresh == nil)
            #expect(importer.feedRequests().isEmpty)
            #expect(!importer.store.isRefreshing)
        }
    }

    // MARK: - A3 Reader cancels

    #if os(iOS)
    @Test("A3: cancelling the file selection adds no feed, changes nothing, and shows no message")
    func cancellingAddsNothing() async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        try await withImporter(feeds: [existing]) { importer in
            let before = try Data(contentsOf: importer.libraryURL)

            try await importer.chooseImport()
            try await importer.cancelFileSelection()

            #expect(importer.store.feeds.map(\.url) == [deltaURL])
            #expect(try Data(contentsOf: importer.libraryURL) == before)
            #expect(try await importer.alertMessages().isEmpty)
            #expect(!importer.store.isRefreshing)
        }
    }
    #else
    @Test("A3: a cancelled file selection imports nothing, changes nothing, and shows no message")
    func cancellingAddsNothing() async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        try await withImporter(feeds: [existing], answers: feedAnswers) { importer in
            let before = try Data(contentsOf: importer.libraryURL)

            let outcome = try await importer.importSelected(nil)

            #expect(outcome.isCancelled)
            #expect(outcome.message == nil)
            #expect(importer.store.feeds.map(\.url) == [deltaURL])
            #expect(try Data(contentsOf: importer.libraryURL) == before)
            #expect(importer.feedRequests().isEmpty)
        }
    }
    #endif

    // MARK: - A4 Library cannot be saved, BR-006 Only saved imports are added

    @Test("A4, BR-006: an import that cannot be saved removes the imported feeds again and leaves the library unchanged")
    func unsavableImportIsUndone() async throws {
        let existing = Feed(title: "Delta", url: deltaURL)
        let file = opml("""
        <outline text="Alpha" xmlUrl="https://alpha.example/feed.xml"/>
        <outline text="Charlie" xmlUrl="https://charlie.example/feed.xml"/>
        """)
        try await withImporter(feeds: [existing], answers: feedAnswers) { importer in
            let feedsBefore = importer.store.feeds
            let before = try Data(contentsOf: importer.libraryURL)
            let url = try importer.write(file)
            importer.makeLibraryUnwritable()

            let outcome = try await importer.importSelected(url)

            // A4 step 1, BR-006, failure postcondition: none of the imported feeds is in the library.
            #expect(importer.store.feeds == feedsBefore)
            #expect(try Data(contentsOf: importer.libraryURL) == before)
            // A4 step 2: a message that the subscriptions could not be imported is displayed.
            let message = try #require(outcome.message)
            #expect(message.localizedCaseInsensitiveContains("subscriptions could not be imported"))
            #if os(iOS)
            #expect(try await importer.alertMessages() == [message])
            #endif
            // BR-006: no refresh is started.
            #expect(outcome.refresh == nil)
            #expect(importer.feedRequests().isEmpty)
            #expect(!importer.store.isRefreshing)
        }
    }

    // MARK: - BR-001 Supported file

    @Test("BR-001: folders are flattened, every outline with a feed address becomes a feed whatever folder it is in")
    func foldersAreFlattened() async throws {
        let file = opml("""
        <outline text="News">
          <outline text="Alpha" xmlUrl="https://alpha.example/feed.xml"/>
          <outline text="Deep">
            <outline text="Bravo" xmlUrl="https://bravo.example/feed.xml"/>
          </outline>
        </outline>
        <outline text="Charlie" xmlUrl="https://charlie.example/feed.xml"/>
        <outline text="Empty folder"></outline>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            // The folders themselves are not feeds.
            #expect(importer.store.feeds.map(\.title) == ["Alpha", "Bravo", "Charlie"])
            #expect(importer.store.feeds.map(\.url) == [alphaURL, bravoURL, charlieURL])
        }
    }

    // MARK: - BR-002 No duplicates on import

    @Test("BR-002: an entry whose feed address is already subscribed is skipped, the subscribed feed is kept as it was")
    func subscribedAddressIsSkipped() async throws {
        let existing = Feed(title: "My Alpha", url: alphaURL, siteURL: URL(string: "https://alpha.example/home"))
        let file = opml("""
        <outline text="Alpha from file" xmlUrl="https://alpha.example/feed.xml" htmlUrl="https://other.example/"/>
        <outline text="Bravo" xmlUrl="https://bravo.example/feed.xml"/>
        """)
        try await withImporter(feeds: [existing]) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.map(\.title) == ["Bravo", "My Alpha"])
            #expect(importer.store.feeds.filter { $0.url == alphaURL } == [existing])
        }
    }

    @Test("BR-002: when the file holds the same feed address more than once, only its first entry is imported")
    func repeatedAddressImportsFirstEntry() async throws {
        let file = opml("""
        <outline text="Work">
          <outline text="Alpha First" xmlUrl="https://alpha.example/feed.xml" htmlUrl="https://alpha.example/first"/>
        </outline>
        <outline text="Home">
          <outline text="Alpha Second" xmlUrl="https://alpha.example/feed.xml" htmlUrl="https://alpha.example/second"/>
        </outline>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.count == 1)
            #expect(importer.store.feeds.first?.title == "Alpha First")
            #expect(importer.store.feeds.first?.siteURL == URL(string: "https://alpha.example/first"))
            #expect(FeedStore(fileURL: importer.libraryURL).feeds.map(\.title) == ["Alpha First"])
        }
    }

    @Test("BR-002, BR-005: addresses are compared after they are checked, against the subscriptions and within the file")
    func addressesAreComparedAfterChecking() async throws {
        let existing = Feed(title: "Alpha", url: alphaURL)
        let file = opml("""
        <outline text="Alpha again" xmlUrl="feed:https://alpha.example/feed.xml"/>
        <outline text="Alpha once more" xmlUrl="  alpha.example/feed.xml  "/>
        <outline text="Bravo" xmlUrl="bravo.example/feed.xml"/>
        <outline text="Bravo again" xmlUrl="feed://bravo.example/feed.xml"/>
        <outline text="Bravo once more" xmlUrl="https://bravo.example/feed.xml"/>
        """)
        try await withImporter(feeds: [existing]) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.map(\.title) == ["Alpha", "Bravo"])
            #expect(importer.store.feeds.map(\.url) == [alphaURL, bravoURL])
        }
    }

    // MARK: - BR-003 Imported feed title

    @Test("BR-003: the title is the entry's title, otherwise its text, otherwise the host name; spaces alone count as missing")
    func titleFallsBackToTextThenHost() async throws {
        let file = opml("""
        <outline title="Title wins" text="Text loses" xmlUrl="https://alpha.example/feed.xml"/>
        <outline text="Text only" xmlUrl="https://bravo.example/feed.xml"/>
        <outline title="   " text="Text after blank title" xmlUrl="https://charlie.example/feed.xml"/>
        <outline title="  " text="   " xmlUrl="https://delta.example/feed.xml"/>
        <outline xmlUrl="https://echo.example/feed.xml"/>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            #expect(importer.title(of: alphaURL) == "Title wins")
            #expect(importer.title(of: bravoURL) == "Text only")
            #expect(importer.title(of: charlieURL) == "Text after blank title")
            #expect(importer.title(of: deltaURL) == "delta.example")
            #expect(importer.title(of: echoURL) == "echo.example")
        }
    }

    @Test("BR-003: the title is plain text of at most 200 characters, a longer one cut to 199 and an ellipsis")
    func titleIsPlainTextOfAtMost200Characters() async throws {
        let exactly200 = String(repeating: "b", count: 200)
        let tooLong = String(repeating: "a", count: 250)
        let file = opml("""
        <outline title="\(tooLong)" xmlUrl="https://alpha.example/feed.xml"/>
        <outline title="\(exactly200)" xmlUrl="https://bravo.example/feed.xml"/>
        <outline title="&lt;b&gt;Charlie&lt;/b&gt; &amp;amp; Friends" xmlUrl="https://charlie.example/feed.xml"/>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            #expect(importer.title(of: alphaURL) == String(repeating: "a", count: 199) + "…")
            #expect(importer.title(of: alphaURL)?.count == 200)
            #expect(importer.title(of: bravoURL) == exactly200)
            #expect(importer.title(of: charlieURL) == "Charlie & Friends")
        }
    }

    // MARK: - BR-004 Order after import

    @Test("BR-004: imported feeds are listed with the subscribed ones alphabetically by title, ignoring case")
    func importedFeedsFollowSubscriptionOrder() async throws {
        let existing = [Feed(title: "bravo", url: bravoURL), Feed(title: "Delta", url: deltaURL)]
        let file = opml("""
        <outline text="echo" xmlUrl="https://echo.example/feed.xml"/>
        <outline text="Charlie" xmlUrl="https://charlie.example/feed.xml"/>
        <outline text="alpha" xmlUrl="https://alpha.example/feed.xml"/>
        """)
        try await withImporter(feeds: existing) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.map(\.title) == ["alpha", "bravo", "Charlie", "Delta", "echo"])
            #expect(FeedStore(fileURL: importer.libraryURL).feeds.map(\.title) == ["alpha", "bravo", "Charlie", "Delta", "echo"])
            #if os(iOS)
            #expect(try await importer.subscriptionRows() == 5)
            #endif
        }
    }

    // MARK: - BR-005 Feed addresses on import

    @Test("BR-005: spaces are ignored, feed: addresses become the web address that follows, and a missing scheme becomes https://")
    func addressesAreAcceptedAsOnSubscribe() async throws {
        let file = opml("""
        <outline text="Alpha" xmlUrl="  https://alpha.example/feed.xml  "/>
        <outline text="Bravo" xmlUrl="feed:https://bravo.example/feed.xml"/>
        <outline text="Charlie" xmlUrl="feed://charlie.example/feed.xml"/>
        <outline text="Delta" xmlUrl="delta.example/feed.xml"/>
        <outline text="Plain" xmlUrl="http://plain.example/rss"/>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.map(\.url) == [
                alphaURL, bravoURL, charlieURL, deltaURL, URL(string: "http://plain.example/rss")!,
            ])
        }
    }

    @Test("BR-005: an entry whose address is not an http or https address with a host name is skipped, the others are imported")
    func invalidAddressesAreSkipped() async throws {
        let file = opml("""
        <outline text="Mail" xmlUrl="mailto:someone@alpha.example"/>
        <outline text="Ftp" xmlUrl="ftp://files.example/feed.xml"/>
        <outline text="No host" xmlUrl="https://"/>
        <outline text="Blank" xmlUrl="   "/>
        <outline text="Bravo" xmlUrl="https://bravo.example/feed.xml"/>
        """)
        try await withImporter(feeds: []) { importer in
            try importer.importFile(file)

            #expect(importer.store.feeds.map(\.title) == ["Bravo"])
            #expect(importer.store.feeds.map(\.url) == [bravoURL])
        }
    }
}

// MARK: - Test data

private let alphaURL = URL(string: "https://alpha.example/feed.xml")!
private let bravoURL = URL(string: "https://bravo.example/feed.xml")!
private let charlieURL = URL(string: "https://charlie.example/feed.xml")!
private let deltaURL = URL(string: "https://delta.example/feed.xml")!
private let echoURL = URL(string: "https://echo.example/feed.xml")!

/// The Feed Publisher's answers for the feeds of the tests that refresh. Each feed names the website the
/// subscription file gives it (Delta none), since a refresh records the feed's website (UC-003 step 6).
private let feedAnswers: [URL: FeedPublisherStub.Answer] = [
    alphaURL: .document(feedDocument(title: "Alpha", site: "https://alpha.example/")),
    charlieURL: .document(feedDocument(title: "Charlie", site: "https://charlie.example/")),
    deltaURL: .document(feedDocument(title: "Delta", site: nil)),
]

/// An RSS feed with one article, linking to `site` when given.
private func feedDocument(title: String, site: String?) -> String {
    let link = site.map { "<link>\($0)</link>" } ?? ""
    return """
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>\(title)</title>\(link)<item><guid>1</guid><title>First</title></item></channel></rss>
    """
}

/// The feed addresses of the test data, to tell feed requests from favicon requests.
private let feedAddresses: Set<URL> = [alphaURL, bravoURL, charlieURL, deltaURL, echoURL]

extension SubscriptionImport.Outcome {
    var importedCount: Int? { if case .imported(let count, _) = self { count } else { nil } }
    var refresh: Task<Void, Never>? { if case .imported(_, let refresh) = self { refresh } else { nil } }
    var isNoNewFeeds: Bool { if case .noNewFeeds = self { true } else { false } }
    var isCancelled: Bool { if case .cancelled = self { true } else { false } }
}

/// An OPML subscription list with the given outlines in its body.
private func opml(_ outlines: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head><title>Exported subscriptions</title></head>
      <body>
    \(outlines)
      </body>
    </opml>
    """
}

/// Files that cannot be read as a subscription file (A1).
enum UnreadableFile: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case notXML
    case feedInsteadOfOPML
    case brokenOPML
    case missingFile

    var testDescription: String {
        switch self {
        case .notXML: "plain text"
        case .feedInsteadOfOPML: "an RSS feed, not an OPML list"
        case .brokenOPML: "OPML that breaks off"
        case .missingFile: "a file that no longer exists"
        }
    }

    func write(in folder: URL) throws -> URL {
        let url = folder.appending(path: "\(rawValue).opml")
        let text: String
        switch self {
        case .notXML: text = "These are my subscriptions: https://alpha.example/feed.xml"
        case .feedInsteadOfOPML: text = Documents.rss(title: "Alpha")
        case .brokenOPML: text = #"<?xml version="1.0"?><opml version="2.0"><body><outline text="Alpha" xmlUrl="https://alpha.example/feed.xml">"#
        case .missingFile: return url
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Files that hold no feed the library does not have yet (A2), for a library that holds Alpha and Delta.
enum NothingNewFile: CaseIterable, CustomTestStringConvertible, Sendable {
    case allSubscribed
    case noValidAddress
    case noEntries

    var testDescription: String {
        switch self {
        case .allSubscribed: "every feed already subscribed"
        case .noValidAddress: "no entry with a valid feed address"
        case .noEntries: "no feed entry at all"
        }
    }

    var outlines: String {
        switch self {
        case .allSubscribed:
            """
            <outline text="Alpha" xmlUrl="https://alpha.example/feed.xml"/>
            <outline text="Folder"><outline text="Delta" xmlUrl="feed:https://delta.example/feed.xml"/></outline>
            """
        case .noValidAddress:
            """
            <outline text="Mail" xmlUrl="mailto:someone@bravo.example"/>
            <outline text="Ftp" xmlUrl="ftp://files.example/feed.xml"/>
            <outline text="Folder only"/>
            """
        case .noEntries:
            ""
        }
    }
}

// MARK: - Test harness

/// What the file importer of the subscription list offers while it is presented.
private struct FileDialog {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection: Bool
    var onCancellation: () -> Void
}

/// Imports subscription files into one library; on iPhone and iPad the subscription list is shown over it.
@MainActor
private struct Importer {
    let store: FeedStore
    let libraryURL: URL
    let folder: URL
    #if os(iOS)
    let sidebar: SidebarView
    #endif

    func feed(_ title: String) -> Feed? {
        store.feeds.first { $0.title == title }
    }

    func title(of url: URL) -> String? {
        store.feeds.first { $0.url == url }?.title
    }

    /// Writes a subscription file next to the library.
    func write(_ text: String) throws -> URL {
        let url = folder.appending(path: "import-\(UUID().uuidString).opml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Steps 4 to 6 for the subscription file with the given content, as the Reader selected it: the call both entry
    /// points make with the selected file. Returns the number of feeds added.
    @discardableResult
    func importFile(_ text: String) throws -> Int {
        try store.importOPML(from: try write(text))
    }

    /// Steps 3 to 7 as both entry points run them for the file the Reader selected (`nil`: the selection was
    /// cancelled). On iPhone and iPad through the subscription list, which shows a failure in its alert.
    func importSelected(_ url: URL?) async throws -> SubscriptionImport.Outcome {
        let selection = url.map { Result<URL, Error>.success($0) }
        #if os(iOS)
        let box = ResultBox<SubscriptionImport.Outcome?>(nil)
        try await sidebar.inspection.inspect { view in
            box.value = try view.actualView().importSubscriptions(selection)
        }
        try await settle()
        return try #require(box.value)
        #else
        return SubscriptionImport(store: store).run(selection)
        #endif
    }

    /// The feed addresses the app requested from the Feed Publisher, in order; favicon requests are left out.
    func feedRequests() -> [URL] {
        FeedPublisherStub.receivedRequests.compactMap(\.url).filter { feedAddresses.contains($0) }
    }

    func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// The library's folder no longer accepts writes, so the library cannot be saved.
    func makeLibraryUnwritable() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path())
    }

    #if os(iOS)
    /// Step 1: the Reader chooses Import OPML… in the subscription list's toolbar menu.
    func chooseImport() async throws {
        try await sidebar.inspection.inspect { view in
            let buttons = try view.find(ViewType.Toolbar.self).findAll(ViewType.Button.self)
            let entry = try #require(buttons.first { (try? $0.labelView().find(text: "Import OPML…")) != nil })
            try entry.tap()
        }
        try await settle()
    }

    /// The file importer the subscription list presents, or nil while none is presented.
    func fileDialog() async throws -> FileDialog? {
        let box = ResultBox<FileDialog?>(nil)
        try await sidebar.inspection.inspect { view in
            box.value = fileImport(in: try view.actualView().body)
        }
        return box.value
    }

    /// A3: the Reader cancels the file selection.
    func cancelFileSelection() async throws {
        let dialog = try #require(try await fileDialog(), "No file importer is presented")
        dialog.onCancellation()
        try await settle()
    }

    /// The messages of the alerts the subscription list shows.
    func alertMessages() async throws -> [String] {
        let box = ResultBox<[String]>([])
        try await sidebar.inspection.inspect { view in
            box.value = view.findAll(ViewType.Alert.self).compactMap { try? $0.message().text().string() }
        }
        return box.value
    }

    /// The number of feeds the subscription list shows.
    func subscriptionRows() async throws -> Int {
        let box = ResultBox(0)
        try await sidebar.inspection.inspect { view in
            box.value = try view.find(ViewType.ForEach.self).count
        }
        return box.value
    }

    /// Lets SwiftUI apply the state changes of the last action.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
    #endif
}

#if os(iOS)
/// SwiftUI's file importer is a `FileDialogConfiguration` modifier that holds a `FileImportOperation` while the
/// importer is presented; the operation sits at a different place in the modifier on iOS 18 and iOS 27. ViewInspector
/// does not know the modifier, so the operation is searched in the view's body by reflection.
@MainActor
private func fileImport(in body: Any) -> FileDialog? {
    // Returns the operation and, where the modifier keeps one next to it (iOS 27), its presentation binding.
    func operation(in value: Any, depth: Int) -> (operation: Any, isPresented: Bool?)? {
        guard depth < 40 else { return nil }
        if String(describing: type(of: value)) == "FileImportOperation" { return (value, nil) }
        let children = Mirror(reflecting: value).children
        for child in children {
            guard var found = operation(in: child.value, depth: depth + 1) else { continue }
            if found.isPresented == nil,
               let binding = children.first(where: { $0.label == "isPresented" })?.value as? Binding<Bool> {
                found.isPresented = binding.wrappedValue
            }
            return found
        }
        return nil
    }
    // On iOS 18 the operation is there only while the importer is presented.
    guard let (found, isPresented) = operation(in: body, depth: 0), isPresented != false else { return nil }
    let fields = Dictionary(Mirror(reflecting: found).children.compactMap { child in child.label.map { ($0, child.value) } },
                            uniquingKeysWith: { first, _ in first })
    guard let types = fields["allowedContentTypes"] as? [UTType],
          let multiple = fields["allowsMultipleSelection"] as? Bool,
          let cancellation = fields["onCancellation"] as? () -> Void else {
        Issue.record("The file importer's operation has an unexpected shape: \(fields.keys.sorted())")
        return nil
    }
    // The completion is left alone: called outside a real presentation, SwiftUI's wrapper around it crashes.
    return FileDialog(allowedContentTypes: types, allowsMultipleSelection: multiple, onCancellation: cancellation)
}
#endif


@MainActor
private func waitForRefresh(of store: FeedStore) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while store.isRefreshing && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// A fresh library in a temporary folder holding `feeds`, saved to the library file. On iPhone and iPad the
/// subscription list is hosted over it.
@MainActor
private func withImporter(
    feeds: [Feed],
    answers: [URL: FeedPublisherStub.Answer] = [:],
    _ body: @MainActor (Importer) async throws -> Void
) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "UC006-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path())
        try? FileManager.default.removeItem(at: folder)
    }
    let libraryURL = folder.appending(path: "library.json")
    let library: [String: Any] = [
        "feeds": try JSONSerialization.jsonObject(with: JSONEncoder().encode(feeds)),
        "articles": [Any](),
    ]
    try JSONSerialization.data(withJSONObject: library).write(to: libraryURL)
    let store = FeedStore(fileURL: libraryURL)
    try #require(store.feeds.map(\.url) == feeds.map(\.url))

    // The stub answers the refresh of step 7 and, on iPhone and iPad, the subscription list's favicons; it is held
    // for the whole test as every suite does.
    try await FeedPublisherStub.withAnswers(answers) {
        #if os(iOS)
        let sidebar = SidebarView(selection: .constant(.unread))
        let importer = Importer(store: store, libraryURL: libraryURL, folder: folder, sidebar: sidebar)
        try await ViewHosting.host(NavigationStack { sidebar }.environment(store)) {
            try await body(importer)
        }
        #else
        try await body(Importer(store: store, libraryURL: libraryURL, folder: folder))
        #endif
        // A refresh still running would outlive the temporary library.
        try await waitForRefresh(of: store)
    }
}
