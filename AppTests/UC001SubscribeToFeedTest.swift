#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import ViewInspector

extension Inspection: InspectionEmissary {}

/// UC-001 Subscribe to Feed, tested through the add-feed form against the real FeedStore and a temporary library
/// file. The Feed Publisher is replaced by `FeedPublisherStub`.
@MainActor
@Suite("UC-001 Subscribe to Feed", .serialized)
struct UC001SubscribeToFeedTest {
    private let feedURL = URL(string: "https://example.com/feed.xml")!
    private let siteURL = URL(string: "https://example.com/")!

    // MARK: - Main success scenario

    @Test("Main success scenario: the feed is added, its articles are unread, the library is saved, the form closes")
    func mainSuccessScenario() async throws {
        try await withForm(answers: [feedURL: .document(Documents.rss(title: "Example Blog"))]) { form in
            // Step 2: the form explains that a feed address or a website address may be entered.
            let texts = try await form.texts()
            #expect(texts.contains { $0.localizedCaseInsensitiveContains("feed") && $0.localizedCaseInsensitiveContains("website") })

            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            let feed = try #require(form.store.feeds.first)
            #expect(form.store.feeds.count == 1)
            #expect(feed.title == "Example Blog")
            #expect(feed.url == feedURL)
            #expect(feed.siteURL == siteURL)
            #expect(form.store.articles.map(\.title).sorted() == ["First", "Second"])
            #expect(form.store.articles.allSatisfy { !$0.isRead && !$0.isStarred && $0.feedID == feed.id })

            // Step 9 and the success postconditions: the library is saved.
            let reloaded = FeedStore(fileURL: form.libraryURL)
            #expect(reloaded.feeds.map(\.url) == [feedURL])
            #expect(reloaded.feeds.first?.title == "Example Blog")
            #expect(reloaded.feeds.first?.siteURL == siteURL)
            #expect(reloaded.articles.count == 2)
            #expect(reloaded.articles.allSatisfy { !$0.isRead && !$0.isStarred })
        }
    }

    @Test("Step 1: the Reader chooses Add Feed in the sidebar and the add-feed form opens")
    func addFeedInSidebarOpensForm() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "UC001-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FeedStore(fileURL: dir.appending(path: "library.json"))
        let sidebar = SidebarView(selection: .constant(nil))
        #expect(!store.isAddingFeed)

        try await ViewHosting.host(NavigationStack { sidebar }.environment(store)) {
            try await sidebar.inspection.inspect { view in
                try view.find(button: "Add Feed").tap()
            }
            #expect(store.isAddingFeed)
        }
    }

    @Test("Step 2: the app's main window presents the add-feed form as a sheet while the Reader adds a feed")
    func contentViewPresentsAddFeedForm() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "UC001-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FeedStore(fileURL: dir.appending(path: "library.json"))
        let saved = Pasteboard.save()
        Pasteboard.set(nil)
        defer { Pasteboard.restore(saved) }

        #if os(macOS)
        try await ViewHosting.host(ContentView().environment(store).frame(width: 900, height: 600)) {
            #expect(AppWindow.sheetTexts() == nil)

            store.isAddingFeed = true
            let texts = try await AppWindow.waitForSheet()
            // The sheet shows the add-feed form; what the form shows is checked by the tests that inspect it.
            #expect(texts.contains { $0.contains("RSSReaderTests.AddFeedSheet") })

            store.isAddingFeed = false
            try await AppWindow.waitForNoSheet()
        }
        #else
        // ViewHosting's window on iOS belongs to no window scene: UIKit presents a sheet there but never dismisses
        // it, so the window cannot show the sheet closing. The main window's sheet is inspected on the view instead.
        let view = ContentView()
        try await ViewHosting.host(view.environment(store).frame(width: 900, height: 600)) {
            try await view.inspection.inspect { view in
                #expect(throws: (any Error).self) { try view.find(ViewType.Sheet.self) }
            }

            store.isAddingFeed = true
            try await view.inspection.inspect { view in
                // The sheet shows the add-feed form; what the form shows is checked by the tests that inspect it.
                _ = try view.find(ViewType.Sheet.self).view(AddFeedSheet.self)
            }

            store.isAddingFeed = false
            try await view.inspection.inspect { view in
                #expect(throws: (any Error).self) { try view.find(ViewType.Sheet.self) }
            }
        }
        #endif
    }

    // MARK: - A1 Address prefilled from clipboard

#if os(macOS)
    @Test("A1: a web or feed address on the clipboard prefills the address field", arguments: [
        "https://example.com/feed.xml", "http://example.com/rss", "feed://example.com/feed.xml",
    ])
    func clipboardAddressPrefillsField(clipboard: String) async throws {
        try await withForm(clipboard: clipboard) { form in
            let address = try await form.address()
            #expect(address == clipboard)
        }
    }

    @Test("A1: clipboard text with spaces or that is no web address is not prefilled", arguments: [
        "https://example.com/my feed.xml", "Hello world", "mailto:someone@example.com",
    ])
    func otherClipboardTextIsNotPrefilled(clipboard: String) async throws {
        try await withForm(clipboard: clipboard) { form in
            let address = try await form.address()
            #expect(address == "")
        }
    }
#else
    @Test("A1: on iPhone and iPad the clipboard is not used to prefill the address field")
    func clipboardIsNotUsedOnIOS() async throws {
        try await withForm(clipboard: "https://example.com/feed.xml") { form in
            let address = try await form.address()
            #expect(address == "")
        }
    }
#endif

    // MARK: - A2 Invalid address, BR-001 Accepted addresses

    @Test("A2, BR-001: an address that is not an http(s) address with a host name is rejected", arguments: [
        "ftp://example.com/feed.xml", "https://", "mailto:someone@example.com", "javascript:alert(1)",
    ])
    func invalidAddressIsRejected(address: String) async throws {
        try await withForm { form in
            try await form.submit(address)
            try await form.waitForText("That doesn't look like a valid web address.")

            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
            #expect(FeedPublisherStub.receivedRequests.isEmpty)
            #expect(try await form.canConfirm())
        }
    }

    @Test("BR-001: spaces are ignored, feed: is unwrapped, a missing scheme becomes https", arguments: [
        "  https://example.com/feed.xml  ",
        "feed:https://example.com/feed.xml",
        "feed://example.com/feed.xml",
        "example.com/feed.xml",
    ])
    func acceptedAddressesAreNormalized(address: String) async throws {
        try await withForm(answers: [feedURL: .document(Documents.rss(title: "Example Blog"))]) { form in
            try await form.submit(address)
            try await form.waitUntilClosed()

            #expect(FeedPublisherStub.receivedRequests.first?.url == feedURL)
            #expect(form.store.feeds.map(\.url) == [feedURL])
        }
    }

    @Test("BR-001: an http address is kept as http")
    func httpAddressIsAccepted() async throws {
        let httpFeed = URL(string: "http://example.com/feed.xml")!
        try await withForm(answers: [httpFeed: .document(Documents.rss(title: "Example Blog"))]) { form in
            try await form.submit("http://example.com/feed.xml")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.map(\.url) == [httpFeed])
        }
    }

    @Test("BR-001: a host with a port number and no scheme is completed to https")
    func hostWithPortIsCompleted() async throws {
        let portFeed = URL(string: "https://localhost:8080/feed.xml")!
        try await withForm(answers: [portFeed: .document(Documents.rss(title: "Local"))]) { form in
            try await form.submit("localhost:8080/feed.xml")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.map(\.url) == [portFeed])
        }
    }

    // MARK: - BR-010 An address is required

    @Test("Step 3, BR-010: the form can be confirmed only when the address holds more than spaces")
    func addressIsRequired() async throws {
        try await withForm { form in
            #expect(try await form.canConfirm() == false)
            try await form.inspect { view in
                try view.find(ViewType.TextField.self).setInput("   ")
            }
            #expect(try await form.canConfirm() == false)
            let textsWithSpaces = try await form.texts()
            #expect(!textsWithSpaces.contains("That doesn't look like a valid web address."))
            try await form.inspect { view in
                try view.find(ViewType.TextField.self).setInput("example.com")
            }
            #expect(try await form.canConfirm())
            #expect(FeedPublisherStub.receivedRequests.isEmpty)
        }
    }

    // MARK: - A3 Website instead of feed, BR-003 Feed discovery

    @Test("A3, BR-003: for a website address the first advertised feed is subscribed under its own address")
    func websiteAddressSubscribesFirstAdvertisedFeed() async throws {
        let atomURL = URL(string: "https://example.com/atom.xml")!
        // BR-001 completes "example.com" to "https://example.com", without a trailing slash.
        let bareSiteURL = URL(string: "https://example.com")!
        try await withForm(answers: [
            bareSiteURL: .document(Documents.webPage(advertising: ["/feed.xml", "/atom.xml"])),
            feedURL: .document(Documents.rss(title: "Example Blog")),
            atomURL: .document(Documents.rss(title: "Second Feed")),
        ]) { form in
            try await form.submit("example.com")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.map(\.url) == [feedURL])
            #expect(form.store.feeds.map(\.title) == ["Example Blog"])
            #expect(!FeedPublisherStub.receivedRequests.contains { $0.url == atomURL })
            #expect(FeedStore(fileURL: form.libraryURL).feeds.map(\.url) == [feedURL])
        }
    }

    @Test("A3, BR-003: an advertised address that is again a web page is unreadable; discovery stops after one step")
    func discoveryTakesOneStepOnly() async throws {
        let nestedPage = URL(string: "https://example.com/feed.xml")!
        let deeperFeed = URL(string: "https://example.com/deeper.xml")!
        try await withForm(answers: [
            siteURL: .document(Documents.webPage(advertising: ["/feed.xml"])),
            nestedPage: .document(Documents.webPage(advertising: ["/deeper.xml"])),
            deeperFeed: .document(Documents.rss(title: "Too Deep")),
        ]) { form in
            let before = try await form.texts()
            try await form.submit("https://example.com/")
            let message = try await form.waitForNewText(notIn: before)

            #expect(!message.isEmpty)
            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
            #expect(form.store.articles.isEmpty)
            #expect(!FeedPublisherStub.receivedRequests.contains { $0.url == deeperFeed })
        }
    }

    // MARK: - A4 No feed found

    @Test("A4: a web page that advertises no feed shows the no-feed message")
    func webPageWithoutFeedShowsMessage() async throws {
        try await withForm(answers: [siteURL: .document(Documents.webPage(advertising: []))]) { form in
            try await form.submit("https://example.com/")
            try await form.waitForText("No feed was found at that address.")

            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
            #expect(try await form.canConfirm())
        }
    }

    // MARK: - A5 Feed Publisher unreachable or feed unreadable, BR-007 Response time limit

    @Test("A5: an error answer, an unreachable publisher, or an unreadable feed show a message and add nothing",
          arguments: [
              FeedPublisherStub.Answer.document("Server error", status: 500),
              .document("Not found", status: 404),
              .failure(.timedOut),
              .failure(.cannotFindHost),
              .failure(.notConnectedToInternet),
          ])
    func failedRetrievalShowsMessage(answer: FeedPublisherStub.Answer) async throws {
        try await withForm(answers: [feedURL: answer]) { form in
            let before = try await form.texts()
            try await form.submit("https://example.com/feed.xml")
            let message = try await form.waitForNewText(notIn: before)

            #expect(!message.isEmpty)
            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
            #expect(form.store.articles.isEmpty)
            #expect(FeedStore(fileURL: form.libraryURL).feeds.isEmpty)
            #expect(try await form.canConfirm())
        }
    }

    @Test("A5: a damaged feed at the entered address reports its own problem, not that no feed was found")
    func damagedFeedReportsItsProblem() async throws {
        let broken = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Broken"
        try await withForm(answers: [feedURL: .document(broken)]) { form in
            let before = try await form.texts()
            try await form.submit("https://example.com/feed.xml")
            let message = try await form.waitForNewText(notIn: before)

            #expect(!message.isEmpty)
            #expect(message != "No feed was found at that address.")
            #expect(message != "That doesn't look like a valid web address.")
            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
        }
    }

    @Test("A5: an advertised feed that cannot be retrieved shows a message and adds nothing")
    func failedAdvertisedFeedShowsMessage() async throws {
        try await withForm(answers: [
            siteURL: .document(Documents.webPage(advertising: ["/feed.xml"])),
            feedURL: .failure(.timedOut),
        ]) { form in
            let before = try await form.texts()
            try await form.submit("https://example.com/")
            let message = try await form.waitForNewText(notIn: before)

            #expect(!message.isEmpty)
            #expect(form.store.feeds.isEmpty)
        }
    }

    @Test("BR-007: the Feed Publisher is given 30 seconds to answer")
    func publisherIsGivenThirtySeconds() async throws {
        try await withForm(answers: [
            siteURL: .document(Documents.webPage(advertising: ["/feed.xml"])),
            feedURL: .document(Documents.rss(title: "Example Blog")),
        ]) { form in
            try await form.submit("https://example.com/")
            try await form.waitUntilClosed()

            let requests = FeedPublisherStub.receivedRequests
            #expect(requests.count == 2)
            #expect(requests.allSatisfy { $0.timeoutInterval == 30 })
        }
    }

    // MARK: - A6 Already subscribed, BR-002 No duplicate subscriptions

    @Test("A6, BR-002: a feed already in the library is not added again")
    func alreadySubscribedFeedIsRejected() async throws {
        try await withForm(
            existing: [("Example Blog", feedURL)],
            answers: [feedURL: .document(Documents.rss(title: "Example Blog"))]
        ) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitForText("You are already subscribed to this feed.")

            #expect(form.isOpen)
            #expect(form.store.feeds.map(\.url) == [feedURL])
            #expect(form.store.articles.isEmpty)
        }
    }

    @Test("A6, BR-002: the comparison uses the final feed address after redirects")
    func duplicateIsDetectedAfterRedirect() async throws {
        let oldURL = URL(string: "https://old.example.com/rss")!
        try await withForm(
            existing: [("Example Blog", feedURL)],
            answers: [oldURL: .redirect(to: feedURL), feedURL: .document(Documents.rss(title: "Example Blog"))]
        ) { form in
            try await form.submit("https://old.example.com/rss")
            try await form.waitForText("You are already subscribed to this feed.")

            #expect(form.store.feeds.map(\.url) == [feedURL])
        }
    }

    @Test("BR-002: a redirected feed is stored under its final address")
    func redirectedFeedIsStoredUnderFinalAddress() async throws {
        let oldURL = URL(string: "https://old.example.com/rss")!
        try await withForm(answers: [
            oldURL: .redirect(to: feedURL), feedURL: .document(Documents.rss(title: "Example Blog")),
        ]) { form in
            try await form.submit("https://old.example.com/rss")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.map(\.url) == [feedURL])
        }
    }

    // MARK: - BR-004 Feed title

    @Test("BR-004: a title of 200 characters is kept, a longer one is cut to 199 characters and an ellipsis")
    func longTitleIsShortened() async throws {
        let exact = String(repeating: "a", count: 200)
        let long = String(repeating: "b", count: 250)
        let exactURL = URL(string: "https://exact.example.com/feed.xml")!
        let longURL = URL(string: "https://long.example.com/feed.xml")!
        try await withForm(answers: [
            exactURL: .document(Documents.rss(title: exact)), longURL: .document(Documents.rss(title: long)),
        ]) { form in
            try await form.submit("https://exact.example.com/feed.xml")
            try await form.waitUntil { form.store.feeds.count == 1 }
            #expect(form.store.feeds.first?.title == exact)
        }
        try await withForm(answers: [longURL: .document(Documents.rss(title: long))]) { form in
            try await form.submit("https://long.example.com/feed.xml")
            try await form.waitUntilClosed()

            let title = try #require(form.store.feeds.first?.title)
            #expect(title == String(repeating: "b", count: 199) + "\u{2026}")
            #expect(title.count == 200)
        }
    }

    @Test("BR-004: the title is plain text")
    func titleIsPlainText() async throws {
        let rss = Documents.rss(title: "&lt;b&gt;Fish &amp;amp; Chips&lt;/b&gt;")
        try await withForm(answers: [feedURL: .document(rss)]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.first?.title == "Fish & Chips")
        }
    }

    @Test("BR-004: a feed without a title is named after the host of its feed address")
    func untitledFeedUsesHostName() async throws {
        try await withForm(answers: [feedURL: .document(Documents.rss(title: nil))]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.first?.title == "example.com")
        }
    }

    // MARK: - BR-005 Subscription order

    @Test("Step 8, BR-005: the new feed is listed alphabetically by title, ignoring case")
    func feedsAreSortedByTitleIgnoringCase() async throws {
        try await withForm(
            existing: [("banana", URL(string: "https://b.example.com/rss")!),
                       ("Cherry", URL(string: "https://c.example.com/rss")!)],
            answers: [feedURL: .document(Documents.rss(title: "Apple"))]
        ) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            #expect(form.store.feeds.map(\.title) == ["Apple", "banana", "Cherry"])
        }
    }

    // MARK: - BR-006 Article rules on subscribe

    @Test("BR-006: the first articles follow the refresh rules for identity and titles")
    func firstArticlesFollowRefreshRules() async throws {
        let rss = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Example Blog</title>
        <item><guid>1</guid><title>First</title></item>
        <item><guid>1</guid><title>First again</title></item>
        <item><link>https://example.com/untitled</link></item>
        <item><description>No identifier at all</description></item>
        </channel></rss>
        """
        try await withForm(answers: [feedURL: .document(rss)]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            // UC-003 BR-004: a repeated item is taken once, an item without identifier, link, or title is skipped.
            // UC-003 BR-005: an item without a title is named "(Untitled)".
            #expect(form.store.articles.map(\.title).sorted() == ["(Untitled)", "First"])
            #expect(form.store.articles.allSatisfy { !$0.isRead && !$0.isStarred })
        }
    }

    @Test("BR-006: content is the full content, else the summary; the snippet is the plain summary, else the content, at most 280 characters")
    func firstArticlesTakeContentAndSnippetByRefreshRules() async throws {
        let longText = String(repeating: "x", count: 300)
        let rss = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>Example Blog</title>
        <item><guid>both</guid><title>Both</title><description>&lt;b&gt;Short&lt;/b&gt; summary</description>
          <content:encoded><![CDATA[<p>Full content</p>]]></content:encoded></item>
        <item><guid>summary</guid><title>Summary only</title><description>&lt;p&gt;Only a summary&lt;/p&gt;</description></item>
        <item><guid>content</guid><title>Content only</title><content:encoded><![CDATA[<p>\(longText)</p>]]></content:encoded></item>
        </channel></rss>
        """
        try await withForm(answers: [feedURL: .document(rss)]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            let byTitle = Dictionary(uniqueKeysWithValues: form.store.articles.map { ($0.title, $0) })
            // UC-003 BR-006
            #expect(byTitle["Both"]?.contentHTML == "<p>Full content</p>")
            #expect(byTitle["Both"]?.snippet == "Short summary")
            #expect(byTitle["Summary only"]?.contentHTML == "<p>Only a summary</p>")
            #expect(byTitle["Summary only"]?.snippet == "Only a summary")
            #expect(byTitle["Content only"]?.contentHTML == "<p>\(longText)</p>")
            #expect(byTitle["Content only"]?.snippet == String(repeating: "x", count: 279) + "\u{2026}")
        }
    }

    @Test("BR-006: RSS 1.0 and Atom feeds can be subscribed")
    func rss1AndAtomFeedsAreAccepted() async throws {
        let rdf = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
          <channel rdf:about="https://rdf.example.com/"><title>RDF Feed</title><link>https://rdf.example.com/</link></channel>
          <item rdf:about="https://rdf.example.com/1"><title>RDF Item</title><link>https://rdf.example.com/1</link></item>
        </rdf:RDF>
        """
        let atom = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Feed</title><link href="https://atom.example.com/"/>
          <entry><id>urn:1</id><title>Atom Item</title></entry>
        </feed>
        """
        let rdfURL = URL(string: "https://rdf.example.com/rss")!
        let atomURL = URL(string: "https://atom.example.com/atom")!
        try await withForm(answers: [rdfURL: .document(rdf)]) { form in
            try await form.submit("https://rdf.example.com/rss")
            try await form.waitUntilClosed()
            #expect(form.store.feeds.map(\.title) == ["RDF Feed"])
            #expect(form.store.articles.map(\.title) == ["RDF Item"])
        }
        try await withForm(answers: [atomURL: .document(atom)]) { form in
            try await form.submit("https://atom.example.com/atom")
            try await form.waitUntilClosed()
            #expect(form.store.feeds.map(\.title) == ["Atom Feed"])
            #expect(form.store.articles.map(\.title) == ["Atom Item"])
        }
    }

    @Test("BR-006: a damaged feed is subscribed with the articles read before the damage")
    func damagedFeedWithReadableArticlesIsSubscribed() async throws {
        let damaged = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Example Blog</title>
        <item><guid>1</guid><title>Readable</title></item>
        <item><guid>2</guid><title>Broken &
        """
        try await withForm(answers: [feedURL: .document(damaged)]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntilClosed()

            // UC-003 BR-003
            #expect(form.store.feeds.map(\.title) == ["Example Blog"])
            #expect(form.store.articles.map(\.title) == ["Readable"])
        }
    }

    // MARK: - A7 Reader cancels, BR-009 Cancelling adds no feed

    @Test("A7: cancelling before confirming closes the form without changes")
    func cancelBeforeConfirmingClosesForm() async throws {
        try await withForm(answers: [feedURL: .document(Documents.rss(title: "Example Blog"))]) { form in
            try await form.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://example.com/feed.xml")
                try view.find(button: "Cancel").tap()
            }
            try await form.waitUntilClosed()

            #expect(form.store.feeds.isEmpty)
            #expect(FeedPublisherStub.receivedRequests.isEmpty)
        }
    }

    @Test("A7, BR-009: cancelling while the feed is retrieved adds no feed, even when the retrieval succeeds")
    func cancelDuringRetrievalAddsNothing() async throws {
        try await withForm(answers: [
            feedURL: .document(Documents.rss(title: "Example Blog"), delay: .milliseconds(800)),
        ]) { form in
            try await form.submit("https://example.com/feed.xml")
            try await form.waitUntil { !FeedPublisherStub.receivedRequests.isEmpty }
            try await form.inspect { view in
                try view.find(button: "Cancel").tap()
            }
            try await form.waitUntilClosed()
            try await Task.sleep(for: .milliseconds(1200))

            #expect(form.store.feeds.isEmpty)
            #expect(form.store.articles.isEmpty)
            #expect(FeedStore(fileURL: form.libraryURL).feeds.isEmpty)
        }
    }

    // MARK: - A8 Library cannot be saved, BR-008 Only saved subscriptions are added

    @Test("A8, BR-008: a feed whose subscription cannot be saved is removed again and the form says so")
    func unsavableSubscriptionIsNotAdded() async throws {
        try await withForm(libraryCannotBeSaved: true,
                           answers: [feedURL: .document(Documents.rss(title: "Example Blog"))]) { form in
            let before = try await form.texts()
            try await form.submit("https://example.com/feed.xml")
            let message = try await form.waitForNewText(notIn: before)

            #expect(message.localizedCaseInsensitiveContains("could not be saved"))
            #expect(form.isOpen)
            #expect(form.store.feeds.isEmpty)
            #expect(form.store.articles.isEmpty)
            // The Reader can confirm again (A8 step 3).
            #expect(try await form.canConfirm())
            #expect(try await form.address() == "https://example.com/feed.xml")
        }
    }
}

// MARK: - Test harness

/// The add-feed form as ContentView presents it: a sheet bound to `FeedStore.isAddingFeed`.
private struct SheetHost: View {
    @Bindable var store: FeedStore
    let sheet: AddFeedSheet

    var body: some View {
        Color.clear
            .frame(width: 600, height: 400)
            .sheet(isPresented: $store.isAddingFeed) { sheet }
            .environment(store)
    }
}

/// Drives one hosted add-feed form.
@MainActor
private struct Form {
    let sheet: AddFeedSheet
    let store: FeedStore
    let libraryURL: URL

    var isOpen: Bool { store.isAddingFeed }

    func inspect(_ body: @escaping @MainActor @Sendable (InspectableView<ViewType.View<AddFeedSheet>>) async throws -> Void) async throws {
        try await sheet.inspection.inspect(body)
    }

    func texts() async throws -> [String] {
        let box = Box<[String]>([])
        try await inspect { view in
            box.value = try view.findAll(ViewType.Text.self).map { try $0.string() }
        }
        return box.value
    }

    func address() async throws -> String {
        let box = Box("")
        try await inspect { view in
            box.value = try view.find(ViewType.TextField.self).input()
        }
        return box.value
    }

    func canConfirm() async throws -> Bool {
        let box = Box(false)
        try await inspect { view in
            box.value = try !view.find(button: "Add").isDisabled()
        }
        return box.value
    }

    /// Step 3: the Reader enters an address and confirms.
    func submit(_ address: String) async throws {
        try await inspect { view in
            try view.find(ViewType.TextField.self).setInput(address)
        }
        try await inspect { view in
            try view.find(button: "Add").tap()
        }
    }

    func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func waitUntilClosed() async throws {
        try await waitUntil { !store.isAddingFeed }
    }

    func waitForText(_ text: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if try await texts().contains(text) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The form never showed \"\(text)\"; it shows \(try await texts())")
    }

    /// Waits for a message the form did not show before, and returns it.
    func waitForNewText(notIn before: [String]) async throws -> String {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let new = try await texts().first(where: { !before.contains($0) }) { return new }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The form showed no message; it shows \(try await texts())")
        return ""
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Opens the add-feed form over a fresh library in a temporary folder, with the given feeds already subscribed,
/// the Feed Publisher answering from `answers`, and `clipboard` on the general pasteboard. The Reader's own
/// clipboard is restored afterwards.
@MainActor
private func withForm(
    existing: [(title: String, url: URL)] = [],
    libraryCannotBeSaved: Bool = false,
    clipboard: String? = nil,
    answers: [URL: FeedPublisherStub.Answer] = [:],
    _ body: @MainActor (Form) async throws -> Void
) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "UC001-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var libraryURL = dir.appending(path: "library.json")
    let store = FeedStore(fileURL: libraryURL)
    if !existing.isEmpty {
        let outlines = existing.map {
            #"<outline type="rss" text="\#($0.title)" title="\#($0.title)" xmlUrl="\#($0.url.absoluteString)"/>"#
        }.joined()
        let opml = dir.appending(path: "existing.opml")
        try #"<?xml version="1.0"?><opml version="2.0"><head/><body>\#(outlines)</body></opml>"#
            .write(to: opml, atomically: true, encoding: .utf8)
        try store.importOPML(from: opml)
    }
    let activeStore: FeedStore
    if libraryCannotBeSaved {
        // The library's folder is a plain file, so the library cannot be written.
        let blocker = dir.appending(path: "blocker")
        try Data().write(to: blocker)
        libraryURL = blocker.appending(path: "library.json")
        activeStore = FeedStore(fileURL: libraryURL)
    } else {
        activeStore = store
    }

    // The stub is held for the whole test, so no other suite's answers replace these meanwhile.
    try await FeedPublisherStub.withAnswers(answers) {
        let saved = Pasteboard.save()
        Pasteboard.set(clipboard)
        defer { Pasteboard.restore(saved) }

        activeStore.isAddingFeed = true
        let sheet = AddFeedSheet()
        let form = Form(sheet: sheet, store: activeStore, libraryURL: libraryURL)
        try await ViewHosting.host(SheetHost(store: activeStore, sheet: sheet)) {
            try await body(form)
            activeStore.isAddingFeed = false
        }
    }
}

#if os(macOS)
/// Looks at the window the view is hosted in to see which sheet it presents. SwiftUI exposes no controls or
/// accessibility elements in a test process, so the sheet's content is identified by the SwiftUI view type its
/// hosting view or controller holds.
@MainActor
private enum AppWindow {
    /// The description of the presented sheet, line by line, or nil when no sheet is presented.
    static func sheetTexts() -> [String]? {
        guard let sheet = presentedSheet() else { return nil }
        var description = ""
        dump(sheet, to: &description, maxDepth: 12)
        return description.split(separator: "\n").map(String.init)
    }

    private static func presentedSheet() -> Any? {
        NSApplication.shared.windows.lazy.compactMap(\.attachedSheet).first?.contentView
    }

    static func waitForSheet() async throws -> [String] {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let texts = sheetTexts(), texts.contains(where: { $0.contains("AddFeedSheet") }) { return texts }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("No sheet was presented")
        return sheetTexts() ?? []
    }

    static func waitForNoSheet() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if sheetTexts() == nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The sheet did not close")
    }
}

#endif

/// Saves and restores the general pasteboard around a test, since A1 reads it on the Mac when the form opens.
@MainActor
private enum Pasteboard {
    #if os(macOS)
    typealias Contents = [[NSPasteboard.PasteboardType: Data]]

    static func save() -> Contents {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func set(_ string: String?) {
        NSPasteboard.general.clearContents()
        if let string { NSPasteboard.general.setString(string, forType: .string) }
    }

    static func restore(_ contents: Contents) {
        NSPasteboard.general.clearContents()
        let items = contents.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }
    #else
    // The simulator's pasteboard is not the Reader's, and reading it would ask for permission: only write it.
    typealias Contents = Void

    static func save() -> Contents {}

    static func set(_ string: String?) {
        UIPasteboard.general.items = []
        if let string { UIPasteboard.general.string = string }
    }

    static func restore(_ contents: Contents) {
        UIPasteboard.general.items = []
    }
    #endif
}
