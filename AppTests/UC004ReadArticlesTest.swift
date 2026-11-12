import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import ViewInspector
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// UC-004 Read Articles, tested through the app's main window (sidebar, article list, article view) against the real
/// FeedStore and a temporary library file that `withReader` writes. The Reader selects lists in the sidebar, opens
/// articles in the list, steps with the article view's Previous and Next buttons, and uses the article view's toolbar
/// and the list rows' menus to open, share, and copy links. Opening a page in the browser goes through the window's
/// `openURL` action, which the tests record instead of starting the browser.
@MainActor
@Suite("UC-004 Read Articles", .serialized, .timeLimit(.minutes(1)))
struct UC004ReadArticlesTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: the Reader picks a list, opens an article, steps through the next ones, and exactly those are read")
    func mainSuccessScenario() async throws {
        try await withReader { reader in
            // Step 1: Unread is selected when the window opens.
            #expect(try await reader.state().list == .unread)

            // Steps 2 and 3: the Reader selects All Articles and sees its articles.
            try await reader.selectList(.all)
            #expect(try await reader.state().listedTitles == ["Comet", "Quasar", "Eclipse", "Pulsar", "Nebula"])

            // Steps 4 and 5: the opened article is displayed and read.
            try await reader.openArticle("Quasar")
            #expect(try await reader.displayedTitle() == "Quasar")
            #expect(reader.article("Quasar").isRead)

            // Steps 6 to 8: the next articles of the list are displayed and read in turn.
            try await reader.tapArticleButton("Next Article")
            #expect(try await reader.displayedTitle() == "Eclipse")
            #expect(reader.article("Eclipse").isRead)
            try await reader.tapArticleButton("Next Article")
            #expect(try await reader.displayedTitle() == "Pulsar")
            #expect(reader.article("Pulsar").isRead)

            // Success postconditions: every opened article is read and the unread counts follow.
            #expect(try await reader.unreadBadge() == 1)
            #expect(try await reader.feedBadges() == ["Alpha": 1, "Beta": 0])
            // Failure postcondition: the article the Reader did not open keeps its state, and so does the read one.
            #expect(!reader.article("Nebula").isRead)
            #expect(reader.article("Comet").isRead)
        }
    }

    @Test("Step 1: the sidebar shows the smart lists, the subscribed feeds and their unread counts, with Unread selected")
    func sidebarOnOpening() async throws {
        try await withReader { reader in
            let texts = try await reader.sidebarTexts()
            #expect(texts.contains("Unread"))
            #expect(texts.contains("All Articles"))
            #expect(texts.contains("Starred"))
            #expect(try await reader.feedBadges() == ["Alpha": 2, "Beta": 2])
            #expect(try await reader.unreadBadge() == 4)
            #expect(try await reader.sidebarSelection() == .unread)
            #expect(try await reader.state().list == .unread)
        }
    }

    @Test("Step 3: each listed article shows its feed, date, title, snippet, read state, and star")
    func listRowContents() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            let rows = try await reader.state().rows
            let comet = try #require(rows.first { $0.title == "Comet" })
            let eclipse = try #require(rows.first { $0.title == "Eclipse" })

            #expect(comet.feed == "Alpha")
            #expect(comet.date == reader.article("Comet").published!.formatted(.relative(presentation: .named)))
            #expect(comet.snippet == "Comet snippet")
            #expect(!comet.starred)
            #expect(eclipse.feed == "Alpha")
            #expect(eclipse.snippet == "Eclipse snippet")
            #expect(eclipse.starred)
            // Comet is read and Eclipse is unread: the rows tell them apart, and the unread one is marked.
            let readMark = try #require(comet.readMark)
            let unreadMark = try #require(eclipse.readMark)
            #expect(readMark != unreadMark)
            #expect(unreadMark != .clear)
        }
    }

    @Test("Step 5: the displayed article shows its feed, author, publication date, title, and content")
    func displayedArticleContents() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Comet")

            let html = try #require(try await reader.displayedHTML())
            let comet = reader.article("Comet")
            #expect(html.contains("Alpha"))
            #expect(html.contains("Ann Author"))
            #expect(html.contains(comet.published!.formatted(date: .long, time: .shortened)))
            #expect(html.contains("Comet"))
            #expect(html.contains("<p>Comet body</p>"))
        }
    }

    @Test("Steps 6 and 7: the Reader moves to the previous article, which is displayed and marked as read")
    func previousArticle() async throws {
        try await withReader { reader in
            try await reader.selectList(.feed(reader.feedID("Alpha")))
            try await reader.openArticle("Nebula")
            #expect(!reader.article("Eclipse").isRead)

            try await reader.tapArticleButton("Previous Article")

            #expect(try await reader.displayedTitle() == "Eclipse")
            #expect(reader.article("Eclipse").isRead)
        }
    }

    // MARK: - A1 No Feeds Yet

    @Test("A1: an empty library shows \"No Feeds\" and offers to add a feed, which opens the add-feed form (UC-001)")
    func noFeedsOffersToAddFeed() async throws {
        try await withReader(feeds: [], articles: []) { reader in
            #expect(try await reader.state().messages.contains("No Feeds"))
            #expect(try await reader.showsAddFeedForm() == false)

            try await reader.tapListButton("Add Feed…")

            #expect(reader.store.isAddingFeed)
            #expect(try await reader.showsAddFeedForm())
            reader.store.isAddingFeed = false
        }
    }

    // MARK: - A2 List Is Empty

    @Test("A2: an empty Unread list says \"You're all caught up.\"")
    func emptyUnreadList() async throws {
        let (feeds, articles) = caughtUpLibrary()
        try await withReader(feeds: feeds, articles: articles) { reader in
            let state = try await reader.state()
            #expect(state.list == .unread)
            #expect(state.rows.isEmpty)
            #expect(state.messages.contains("You're all caught up."))
            #expect(!state.messages.contains("Nothing here yet."))
        }
    }

    @Test("A2: an empty Starred list or feed says \"Nothing here yet.\"", arguments: ["Starred", "Beta"])
    func emptyOtherList(list: String) async throws {
        let (feeds, articles) = caughtUpLibrary()
        try await withReader(feeds: feeds, articles: articles) { reader in
            try await reader.selectList(list == "Starred" ? .starred : .feed(reader.feedID("Beta")))
            let state = try await reader.state()
            #expect(state.rows.isEmpty)
            #expect(state.messages.contains("Nothing here yet."))
            #expect(!state.messages.contains("You're all caught up."))
        }
    }

    @Test("A2: All Articles without any article says \"Nothing here yet.\"")
    func emptyAllArticlesList() async throws {
        try await withReader(feeds: [alpha], articles: []) { reader in
            try await reader.selectList(.all)
            let state = try await reader.state()
            #expect(state.rows.isEmpty)
            #expect(state.messages.contains("Nothing here yet."))
        }
    }

    // MARK: - A3 Open in Browser

    @Test("A3: the Reader opens the displayed article's web page in the default browser")
    func openDisplayedArticleInBrowser() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Quasar")

            try await reader.tapArticleButton("Open in Browser")

            #expect(reader.openedURLs == [URL(string: "https://beta.example/quasar")!])
            // The use case continues at step 6: the article stays displayed.
            #expect(try await reader.displayedTitle() == "Quasar")
        }
    }

    @Test("A3: the Reader clicks a link in the displayed article's content and it opens in the default browser, not in the app")
    func openContentLinkInBrowser() async throws {
        let content = #"<p>See <a href="https://elsewhere.example/source">the source</a>.</p>"#
        let articles = [StoredArticle(feed: beta, key: "linked", title: "Linked", link: "https://beta.example/linked",
                                      content: content, minutesAgo: 5)]
        try await withReader(articles: articles) { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Linked")
            #expect(try await reader.displayedHTML()?.contains(#"href="https://elsewhere.example/source""#) == true)

            let policy = try await reader.clickContentLink(URL(string: "https://elsewhere.example/source")!)

            // BR-005: the link goes to the default browser and the article view does not follow it.
            #expect(reader.openedURLs == [URL(string: "https://elsewhere.example/source")!])
            #expect(policy == .cancel)
            // The use case continues at step 6: the article stays displayed.
            #expect(try await reader.displayedTitle() == "Linked")
        }
    }

    // MARK: - A4 Share or Copy a Link from the List

    @Test("A4: the Reader copies the link of an article in the list to the clipboard")
    func copyLinkFromList() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await withClipboard {
                try await reader.tapRowMenuButton("Copy Link", ofArticle: "Eclipse")
                try await Clipboard.expectHolds("https://alpha.example/eclipse")
            }
            // Copying from the list opens no article.
            #expect(try await reader.state().selectedArticleID == nil)
            #expect(!reader.article("Eclipse").isRead)
        }
    }

    @Test("A4: the Reader shares the link of an article in the list through the share sheet")
    func shareLinkFromList() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            let menu = try await reader.rowMenu(ofArticle: "Eclipse")
            #expect(menu.sharedURL == URL(string: "https://alpha.example/eclipse"))
        }
    }

    // MARK: - A5 Share or Copy the Displayed Article's Link

    @Test("A5: the Reader copies the displayed article's link to the clipboard")
    func copyDisplayedArticleLink() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Quasar")
            try await withClipboard {
                try await reader.tapArticleButton("Copy Link")
                try await Clipboard.expectHolds("https://beta.example/quasar")
            }
            #expect(try await reader.displayedTitle() == "Quasar")
        }
    }

    @Test("A5: the Reader shares the displayed article's link through the share sheet")
    func shareDisplayedArticleLink() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Quasar")
            #expect(try await reader.articleToolbar().sharedURL == URL(string: "https://beta.example/quasar"))
        }
    }

    // MARK: - A6 Reader Selects Another List

    @Test("A6: selecting another list clears the article selection and forgets the articles read during the visit")
    func anotherListForgetsVisit() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            #expect(try await reader.state().listedTitles.contains("Quasar"))

            try await reader.selectList(.all)
            let all = try await reader.state()
            #expect(all.selectedArticleID == nil)
            #expect(!all.showsArticle)

            try await reader.selectList(.unread)
            let unread = try await reader.state()
            #expect(unread.listedTitles == ["Eclipse", "Pulsar", "Nebula"])
            #expect(reader.article("Quasar").isRead)
        }
    }

    // MARK: - BR-001 Smart Lists

    @Test("BR-001: each list shows its articles", arguments: [
        ("Unread", ["Quasar", "Eclipse", "Pulsar", "Nebula"]),
        ("All Articles", ["Comet", "Quasar", "Eclipse", "Pulsar", "Nebula"]),
        ("Starred", ["Eclipse"]),
        ("Alpha", ["Comet", "Eclipse", "Nebula"]),
        ("Beta", ["Quasar", "Pulsar"]),
    ])
    func listContents(list: String, expected: [String]) async throws {
        try await withReader { reader in
            let item: SidebarItem = switch list {
            case "Unread": .unread
            case "All Articles": .all
            case "Starred": .starred
            default: .feed(reader.feedID(list))
            }
            try await reader.selectList(item)
            #expect(Set(try await reader.state().listedTitles) == Set(expected))
        }
    }

    // MARK: - BR-002 Article Order

    @Test("BR-002: articles are listed newest first; one without a publication date is placed by when it was first fetched")
    func articleOrder() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            // Pulsar has no publication date and was fetched 30 minutes ago, between Eclipse (20) and Nebula (40).
            #expect(try await reader.state().listedTitles == ["Comet", "Quasar", "Eclipse", "Pulsar", "Nebula"])
            try await reader.selectList(.feed(reader.feedID("Beta")))
            #expect(try await reader.state().listedTitles == ["Quasar", "Pulsar"])
        }
    }

    // MARK: - BR-003 Opening Marks as Read

    @Test("BR-003: displaying an article marks it as read and no other article", arguments: ["Starred", "Beta"])
    func openingMarksAsRead(list: String) async throws {
        try await withReader { reader in
            let before = reader.store.articles
            try await reader.selectList(list == "Starred" ? .starred : .feed(reader.feedID("Beta")))
            let title = list == "Starred" ? "Eclipse" : "Pulsar"

            try await reader.openArticle(title)

            #expect(reader.article(title).isRead)
            for article in before where article.title != title {
                #expect(reader.store.article(withID: article.id) == article)
            }
        }
    }

    // MARK: - BR-004 Stable Unread List

    @Test("BR-004: articles read during the visit stay in Unread, and the Reader can move back to them")
    func unreadListStaysStable() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            try await reader.tapArticleButton("Next Article")
            #expect(try await reader.displayedTitle() == "Eclipse")

            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Pulsar", "Nebula"])
            try await reader.tapArticleButton("Previous Article")
            #expect(try await reader.displayedTitle() == "Quasar")
            #expect(reader.article("Quasar").isRead && reader.article("Eclipse").isRead)
        }
    }

    // MARK: - BR-005 Safe Article Display

    @Test("BR-005: article content is displayed without running the scripts it contains")
    func scriptsDoNotRun() async throws {
        let content = #"<p>Visible text</p><script>document.title = 'script ran'; document.body.setAttribute('data-ran', 'yes');</script>"#
        let articles = [StoredArticle(feed: alpha, key: "script", title: "Scripted", content: content, minutesAgo: 5)]
        try await withArticleView(feeds: [alpha], articles: articles, showing: "Scripted") { webView in
            // The page is displayed once its text is there.
            var text: String?
            let deadline = ContinuousClock.now + .seconds(3)
            while ContinuousClock.now < deadline, text?.contains("Visible text") != true {
                try await Task.sleep(for: .milliseconds(50))
                text = try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''") as? String
            }
            #expect(text?.contains("Visible text") == true)
            let title = try await webView.evaluateJavaScript("document.title") as? String
            #expect(title != "script ran")
            let ran = try await webView.evaluateJavaScript("document.body.getAttribute('data-ran') === null") as? Bool
            #expect(ran == true)
        }
    }

    // MARK: - BR-006 Unread Counts

    @Test("BR-006: the sidebar shows each feed's unread count and their total for Unread, and both follow an opened article")
    func unreadCounts() async throws {
        try await withReader { reader in
            #expect(try await reader.feedBadges() == ["Alpha": 2, "Beta": 2])
            #expect(try await reader.unreadBadge() == 4)

            try await reader.openArticle("Quasar")

            #expect(try await reader.feedBadges() == ["Alpha": 2, "Beta": 1])
            #expect(try await reader.unreadBadge() == 3)
        }
    }

    // MARK: - BR-007 Open and Share Need a Link

    @Test("BR-007: the displayed article offers open in browser, share, and copy link only when it has a link")
    func articleViewOffersLinkActionsOnlyWithLink() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Quasar")
            let withLink = try await reader.articleToolbar()
            #expect(withLink.buttons.contains("Open in Browser"))
            #expect(withLink.buttons.contains("Copy Link"))
            #expect(withLink.sharedURL != nil)

            try await reader.openArticle("Nebula")
            let withoutLink = try await reader.articleToolbar()
            #expect(!withoutLink.buttons.contains("Open in Browser"))
            #expect(!withoutLink.buttons.contains("Copy Link"))
            #expect(withoutLink.sharedURL == nil)
        }
    }

    @Test("BR-007: an article of the list offers share and copy link only when it has a link")
    func listOffersLinkActionsOnlyWithLink() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            let withLink = try await reader.rowMenu(ofArticle: "Quasar")
            #expect(withLink.buttons.contains("Copy Link"))
            #expect(withLink.sharedURL != nil)

            let withoutLink = try await reader.rowMenu(ofArticle: "Nebula")
            #expect(!withoutLink.buttons.contains("Copy Link"))
            #expect(withoutLink.sharedURL == nil)
        }
    }

    // MARK: - BR-008 Saving Read State

    @Test("BR-008: an article marked as read by displaying it is saved like any read change (UC-005 BR-002: within 2 seconds)")
    func readStateIsSaved() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")

            try await reader.waitUntil(timeout: .milliseconds(2500)) {
                reader.reloadedArticle("Quasar")?.isRead == true
            }
            #expect(reader.reloadedArticle("Eclipse")?.isRead == false)
        }
    }

    @Test("BR-008: when the library cannot be saved the article stays read, the Reader is not told, and the next save stores it")
    func unsavedReadStateGoesWithNextSave() async throws {
        try await withReader { reader in
            reader.makeLibraryUnwritable()
            try await reader.openArticle("Quasar")
            // Past the 2 seconds of UC-005 BR-002, so the save has been tried and failed.
            try await Task.sleep(for: .milliseconds(2500))

            #expect(reader.article("Quasar").isRead)
            #expect(reader.reloadedArticle("Quasar")?.isRead == false)
            #expect(try await reader.showsAlert() == false)
            // Failure postcondition: no article the Reader did not open changes its read state.
            for title in ["Eclipse", "Pulsar", "Nebula"] {
                #expect(!reader.article(title).isRead, "\(title) in memory")
                #expect(reader.reloadedArticle(title)?.isRead == false, "\(title) in the library")
            }

            reader.makeLibraryWritable()
            try await reader.openArticle("Eclipse")
            try await reader.waitUntil(timeout: .milliseconds(2500)) {
                reader.reloadedArticle("Eclipse")?.isRead == true
            }
            #expect(reader.reloadedArticle("Quasar")?.isRead == true)
            // Failure postcondition: the later save stores no read state for the articles still not opened.
            for title in ["Pulsar", "Nebula"] {
                #expect(!reader.article(title).isRead, "\(title) in memory")
                #expect(reader.reloadedArticle(title)?.isRead == false, "\(title) in the library")
            }
        }
    }
}

// MARK: - Test data

private let alpha = Feed(title: "Alpha", url: URL(string: "https://alpha.example/feed.xml")!)
private let beta = Feed(title: "Beta", url: URL(string: "https://beta.example/feed.xml")!)

/// An article as the library file holds it. Times are minutes before the test starts.
private struct StoredArticle {
    var feed: Feed
    var key: String
    var title: String
    var link: String?
    var author: String?
    var content: String?
    /// Minutes since publication; nil for an article without a publication date.
    var minutesAgo: Double?
    var fetchedMinutesAgo: Double = 60
    var read = false
    var starred = false

    func json(now: Date) -> [String: Any] {
        var value: [String: Any] = [
            "id": "\(feed.id.uuidString)|\(key)", "feedID": feed.id.uuidString, "title": title,
            "contentHTML": content ?? "<p>\(title) body</p>", "snippet": "\(title) snippet",
            "fetched": now.addingTimeInterval(-fetchedMinutesAgo * 60).timeIntervalSinceReferenceDate,
            "isRead": read, "isStarred": starred,
        ]
        if let link { value["link"] = link }
        if let author { value["author"] = author }
        if let minutesAgo { value["published"] = now.addingTimeInterval(-minutesAgo * 60).timeIntervalSinceReferenceDate }
        return value
    }
}

/// Alpha: Comet (read), Eclipse (starred), Nebula (no link). Beta: Quasar, Pulsar (no publication date, fetched 30
/// minutes ago). Newest first: Comet 10, Quasar 15, Eclipse 20, Pulsar 30, Nebula 40 minutes ago.
private let standardArticles: [StoredArticle] = [
    StoredArticle(feed: alpha, key: "comet", title: "Comet", link: "https://alpha.example/comet",
                  author: "Ann Author", minutesAgo: 10, read: true),
    StoredArticle(feed: alpha, key: "eclipse", title: "Eclipse", link: "https://alpha.example/eclipse",
                  minutesAgo: 20, starred: true),
    StoredArticle(feed: alpha, key: "nebula", title: "Nebula", minutesAgo: 40),
    StoredArticle(feed: beta, key: "quasar", title: "Quasar", link: "https://beta.example/quasar",
                  author: "Bob Writer", minutesAgo: 15),
    StoredArticle(feed: beta, key: "pulsar", title: "Pulsar", link: "https://beta.example/pulsar",
                  minutesAgo: nil, fetchedMinutesAgo: 30),
]

/// Alpha with one read, unstarred article; Beta without articles.
private func caughtUpLibrary() -> ([Feed], [StoredArticle]) {
    ([alpha, beta], [StoredArticle(feed: alpha, key: "comet", title: "Comet", minutesAgo: 10, read: true)])
}

// MARK: - Test harness

/// One listed article as its row shows it.
private struct Row {
    var feed: String?
    var date: String?
    var title: String?
    var snippet: String?
    var starred: Bool
    /// The colour of the row's read-state mark.
    var readMark: Color?
}

/// What the main window shows: the selected list, its rows, the texts of an empty list, and the article view.
private struct WindowState {
    var list: SidebarItem?
    var selectedArticleID: Article.ID?
    var rows: [Row] = []
    var messages: [String] = []
    var showsArticle = false

    var listedTitles: [String] { rows.compactMap(\.title) }
}

/// The link actions a toolbar or a row's menu offers: the titles of its buttons and the link its share item passes.
private struct LinkActions {
    var buttons: [String]
    var sharedURL: URL?
}

private final class OpenedURLs: @unchecked Sendable {
    var urls: [URL] = []
}

/// Drives one hosted main window.
@MainActor
private struct Reader {
    let view: ContentView
    let store: FeedStore
    let libraryURL: URL
    let opened: OpenedURLs

    var openedURLs: [URL] { opened.urls }

    func feedID(_ title: String) -> UUID {
        store.feeds.first { $0.title == title }!.id
    }

    func article(_ title: String) -> Article {
        store.articles.first { $0.title == title }!
    }

    /// The article as the library file holds it.
    func reloadedArticle(_ title: String) -> Article? {
        FeedStore(fileURL: libraryURL).articles.first { $0.title == title }
    }

    /// Inspects the live window. The store and the recording `openURL` action are put into the inspected hierarchy
    /// again, so the child views ViewInspector builds find them in their environment, as they do in the app.
    private func inspect(_ body: @escaping @MainActor @Sendable (InspectableView<ViewType.ClassifiedView>) async throws -> Void) async throws {
        let store = store
        let opened = opened
        try await view.inspection.inspect { view in
            let action = OpenURLAction { url in
                opened.urls.append(url)
                return .handled
            }
            try await body(try view.actualView().environment(store).environment(\.openURL, action).inspect())
        }
    }

    // MARK: Sidebar

    func sidebarSelection() async throws -> SidebarItem? {
        let box = ResultBox<SidebarItem?>(nil)
        try await inspect { view in
            box.value = try view.find(SidebarView.self).actualView().selection
        }
        return box.value
    }

    /// Every text the sidebar shows outside the feed rows: section titles, smart lists, toolbar.
    func sidebarTexts() async throws -> [String] {
        let box = ResultBox<[String]>([])
        try await inspect { view in
            box.value = texts(in: try view.find(SidebarView.self).actualView().body)
        }
        return box.value
    }

    /// The count on the Unread smart list; nil when it shows none.
    func unreadBadge() async throws -> Int? {
        let box = ResultBox<Int?>(nil)
        try await inspect { view in
            let body = try view.find(SidebarView.self).actualView().body
            let unread = values(in: body) { value in
                String(describing: type(of: value)).hasPrefix("BadgedView<") && texts(in: value).contains("Unread")
            }
            box.value = try #require(unread.first.map(badgeNumber))
        }
        return box.value
    }

    /// The count each feed row shows, by feed title; 0 for a row without a count.
    func feedBadges() async throws -> [String: Int] {
        let box = ResultBox<[String: Int]>([:])
        try await inspect { view in
            let rows = try view.find(SidebarView.self).find(ViewType.ForEach.self)
            for row in rows {
                let badged = try #require(values(in: row) { String(describing: type(of: $0)).hasPrefix("BadgedView<") }.first)
                let feedRow = try #require(values(in: badged) { String(describing: type(of: $0)) == "FeedRow" }.first as? any View)
                let title = try #require(try feedRow.inspect().findAll(ViewType.Text.self).first?.string())
                box.value[title] = badgeNumber(badged) ?? 0
            }
        }
        return box.value
    }

    /// Whether the window shows an alert.
    func showsAlert() async throws -> Bool {
        let box = ResultBox(false)
        try await inspect { view in
            box.value = (try? view.find(ViewType.Alert.self)) != nil
                || (try? view.find(SidebarView.self).find(ViewType.Alert.self)) != nil
        }
        return box.value
    }

    /// The Reader selects a list in the sidebar.
    func selectList(_ item: SidebarItem) async throws {
        try await inspect { view in
            try view.find(SidebarView.self).actualView().selection = item
        }
        try await settle()
    }

    // MARK: Article list

    func state() async throws -> WindowState {
        let box = ResultBox(WindowState())
        try await inspect { view in
            let list = try view.find(ArticleListView.self)
            let actual = try list.actualView()
            var state = WindowState(list: actual.sidebarSelection, selectedArticleID: actual.selectedArticleID)
            if let rows = try? list.find(ViewType.ForEach.self) {
                state.rows = try rows.map(Self.row)
            }
            state.messages = texts(in: actual.body)
            state.showsArticle = (try? view.find(ArticleDetailView.self)) != nil
            box.value = state
        }
        return box.value
    }

    private static func row(_ row: InspectableView<ViewType.ClassifiedView>) throws -> Row {
        let texts = try row.findAll(ViewType.Text.self).map { try $0.string() }
        let starred = row.findAll(ViewType.Image.self).contains { (try? $0.actualImage().name()) == "star.fill" }
        // The mark is a filled shape inside the row's view, which ViewInspector does not reach, so the view is taken
        // from the row by reflection and its fill read from the view's body.
        func fill<V: View>(_ view: V) -> Color? {
            let shape = values(in: view.body) { String(describing: type(of: $0)).hasPrefix("_ShapeView<") }.first
            return shape.flatMap { values(in: $0) { $0 is Color }.first as? Color }
        }
        let rowView = values(in: row) { String(describing: type(of: $0)) == "ArticleRow" }.first as? any View
        return Row(
            feed: texts.indices.contains(0) ? texts[0] : nil,
            date: texts.indices.contains(1) ? texts[1] : nil,
            title: texts.indices.contains(2) ? texts[2] : nil,
            snippet: texts.indices.contains(3) ? texts[3] : nil,
            starred: starred,
            readMark: rowView.flatMap { fill($0) }
        )
    }

    /// The Reader opens an article of the displayed list.
    func openArticle(_ title: String) async throws {
        let id = article(title).id
        try await inspect { view in
            try view.find(ArticleListView.self).actualView().selectedArticleID = id
        }
        try await settle()
    }

    /// The Reader chooses a button the article list shows in place of articles.
    func tapListButton(_ title: String) async throws {
        try await inspect { view in
            try view.find(ArticleListView.self).find(button: title).tap()
        }
        try await settle()
    }

    /// Whether the window presents the add-feed form.
    func showsAddFeedForm() async throws -> Bool {
        let box = ResultBox(false)
        try await inspect { view in
            box.value = (try? view.find(ViewType.Sheet.self).find(AddFeedSheet.self)) != nil
        }
        return box.value
    }

    /// The link actions of a list row's menu. ViewInspector cannot search a context menu, so its content is taken
    /// from the row's modifiers by reflection.
    func rowMenu(ofArticle title: String) async throws -> LinkActions {
        let box = ResultBox(LinkActions(buttons: []))
        try await inspect { view in
            let menu = try Self.menuContent(ofArticle: title, in: view)
            box.value = LinkActions(
                buttons: menuButtons(in: menu).compactMap { try? $0.inspect().button().labelView().text().string() },
                sharedURL: sharedURL(in: menu)
            )
        }
        return box.value
    }

    /// The Reader chooses an entry of a list row's menu.
    func tapRowMenuButton(_ entry: String, ofArticle title: String) async throws {
        try await inspect { view in
            let menu = try Self.menuContent(ofArticle: title, in: view)
            let button = try #require(menuButtons(in: menu).first {
                (try? $0.inspect().button().labelView().text().string()) == entry
            })
            try button.inspect().button().tap()
        }
        try await settle()
    }

    private static func menuContent(ofArticle title: String, in view: InspectableView<ViewType.ClassifiedView>) throws -> [Any] {
        let rows = try view.find(ArticleListView.self).find(ViewType.ForEach.self)
        let row = try #require(rows.first { (try? Self.row($0).title) == title })
        let modifiers = Mirror(reflecting: row).descendant("content", "medium", "viewModifiers") as? [Any] ?? []
        return modifiers.compactMap { Mirror(reflecting: $0).descendant("modifier", "menuView") }
    }

    // MARK: Article view

    private static func articleView(in view: InspectableView<ViewType.ClassifiedView>) throws -> InspectableView<ViewType.View<ArticleDetailView>> {
        try view.find(ArticleDetailView.self)
    }

    /// The title of the displayed article; nil when none is displayed.
    func displayedTitle() async throws -> String? {
        let box = ResultBox<String?>(nil)
        try await inspect { view in
            box.value = (try? Self.articleView(in: view).actualView().article.title)
        }
        return box.value
    }

    /// The page the article view displays.
    func displayedHTML() async throws -> String? {
        let box = ResultBox<String?>(nil)
        try await inspect { view in
            box.value = try Self.articleView(in: view).find(ArticleWebView.self).actualView().html
        }
        return box.value
    }

    /// The buttons and the share item of the article view's toolbar.
    func articleToolbar() async throws -> LinkActions {
        let box = ResultBox(LinkActions(buttons: []))
        try await inspect { view in
            let toolbar = try Self.articleView(in: view).find(ArticleWebView.self).toolbar()
            box.value = LinkActions(
                buttons: toolbar.findAll(ViewType.Button.self).compactMap { try? $0.labelView().find(ViewType.Text.self).string() },
                sharedURL: sharedURL(in: toolbar)
            )
        }
        return box.value
    }

    /// The Reader clicks a link to `url` inside the displayed article's content. The web view hands a clicked link to
    /// its coordinator as a link-activated navigation; this asks the coordinator of the displayed article view what
    /// to do with it and returns its answer.
    func clickContentLink(_ url: URL) async throws -> WKNavigationActionPolicy {
        let box = ResultBox<WKNavigationActionPolicy>(.allow)
        try await inspect { view in
            let webView = try Self.articleView(in: view).find(ArticleWebView.self).actualView()
            box.value = webView.makeCoordinator().policy(for: .linkActivated, url: url)
        }
        try await settle()
        return box.value
    }

    /// The Reader chooses a button of the article view's toolbar.
    func tapArticleButton(_ title: String) async throws {
        try await inspect { view in
            let toolbar = try Self.articleView(in: view).find(ArticleWebView.self).toolbar()
            let button = try #require(toolbar.findAll(ViewType.Button.self).first {
                (try? $0.labelView().find(ViewType.Text.self).string()) == title
            })
            try button.tap()
        }
        try await settle()
    }

    // MARK: Library and timing

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

    /// Lets SwiftUI apply the state changes of the last action.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The condition was not met within \(timeout)")
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Reflection

/// Every value inside `root` that matches, searched depth-first. ViewInspector cannot look inside badged views,
/// context menus, or share links, so the tests take what those views hold by reflection.
private func values(in root: Any, depth: Int = 0, where matches: (Any) -> Bool) -> [Any] {
    guard depth < 40 else { return [] }
    if matches(root) { return [root] }
    return Mirror(reflecting: root).children.flatMap { values(in: $0.value, depth: depth + 1, where: matches) }
}

/// The strings of every `Text` inside `root`.
@MainActor
private func texts(in root: Any) -> [String] {
    values(in: root) { $0 is Text }.compactMap { try? ($0 as! Text).inspect().text().string() }
}

/// The number a `BadgedView` shows; nil when it shows none.
private func badgeNumber(_ badged: Any) -> Int? {
    guard let label = Mirror(reflecting: badged).descendant("badgeLabel") else { return nil }
    return values(in: label) { $0 is Int }.first as? Int
}

private func menuButtons(in menu: [Any]) -> [Button<Text>] {
    values(in: menu) { $0 is Button<Text> }.compactMap { $0 as? Button<Text> }
}

/// The link the first share item inside `root` passes to the share sheet.
private func sharedURL(in root: Any) -> URL? {
    guard let share = values(in: root, where: { String(describing: type(of: $0)).hasPrefix("ShareLink<") }).first else {
        return nil
    }
    return values(in: share) { $0 is URL }.first as? URL
}

// MARK: - Clipboard

@MainActor
private enum Clipboard {
    #if os(iOS)
    /// The pasteboard's change count when the test took the clipboard.
    static var startCount = 0
    #endif

    /// The clipboard holds `link`. On iPhone and iPad reading the pasteboard asks the Reader for permission, which
    /// blocks an unhosted test, so there the test checks without reading: the pasteboard changed and holds a web
    /// address. The Mac checks the link itself.
    static func expectHolds(_ link: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        #if os(macOS)
        #expect(NSPasteboard.general.string(forType: .string) == link, sourceLocation: sourceLocation)
        #else
        #expect(UIPasteboard.general.changeCount > startCount, sourceLocation: sourceLocation)
        let patterns = try await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])
        #expect(patterns.contains(\.probableWebURL), sourceLocation: sourceLocation)
        #endif
    }
}

/// Runs `body` with an empty clipboard and gives the Reader's clipboard back afterwards. UC-001's tests use the
/// clipboard while they hold `FeedPublisherStub`; every window of this suite holds the stub too (`withLibrary`), so
/// the two never use the clipboard at the same time.
@MainActor
private func withClipboard(_ body: () async throws -> Void) async throws {
    #if os(macOS)
    let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
    }
    NSPasteboard.general.clearContents()
    defer {
        NSPasteboard.general.clearContents()
        let items = saved.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }
    #else
    // The simulator's pasteboard is not the Reader's.
    UIPasteboard.general.items = []
    Clipboard.startCount = UIPasteboard.general.changeCount
    defer { UIPasteboard.general.items = [] }
    #endif
    try await body()
}

// MARK: - Window

/// Writes a fresh library that holds `feeds` and `articles` to a temporary folder, as the file FeedStore keeps, and
/// opens a store on it. No feed is refreshed, but the subscription list loads the feeds' favicons, so the test holds
/// `FeedPublisherStub` without answers: no request leaves the machine, and none reaches another suite's stub.
@MainActor
private func withLibrary(
    feeds: [Feed],
    articles: [StoredArticle],
    _ body: @MainActor (FeedStore, URL) async throws -> Void
) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "UC004-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path())
        try? FileManager.default.removeItem(at: dir)
    }
    let libraryURL = dir.appending(path: "library.json")
    let now = Date.now
    let library: [String: Any] = [
        "feeds": try JSONSerialization.jsonObject(with: JSONEncoder().encode(feeds)),
        "articles": articles.map { $0.json(now: now) },
    ]
    try JSONSerialization.data(withJSONObject: library).write(to: libraryURL)
    let store = FeedStore(fileURL: libraryURL)
    try #require(store.feeds.map(\.id) == feeds.map(\.id))
    try #require(store.articles.count == articles.count)
    try await FeedPublisherStub.withAnswers([:]) {
        try await body(store, libraryURL)
    }
}

/// Opens the main window over the library `withLibrary` writes.
@MainActor
private func withReader(
    feeds: [Feed] = [alpha, beta],
    articles: [StoredArticle] = standardArticles,
    _ body: @MainActor (Reader) async throws -> Void
) async throws {
    try await withLibrary(feeds: feeds, articles: articles) { store, libraryURL in
        let view = ContentView()
        let reader = Reader(view: view, store: store, libraryURL: libraryURL, opened: OpenedURLs())
        try await ViewHosting.host(view.environment(store).frame(width: 1000, height: 600)) {
            try await body(reader)
        }
    }
}

/// Shows the article titled `title` in the article view on its own, as the window shows it once the Reader opened
/// the article, and hands over the web view that displays it. On iPhone the main window shows the article view only
/// after pushing it, which the shared test window does not do reliably while other suites host their views.
@MainActor
private func withArticleView(
    feeds: [Feed],
    articles: [StoredArticle],
    showing title: String,
    _ body: @MainActor (WKWebView) async throws -> Void
) async throws {
    try await withLibrary(feeds: feeds, articles: articles) { store, _ in
        let article = try #require(store.articles.first { $0.title == title })
        let view = ArticleDetailView(article: article)
        try await ViewHosting.host(NavigationStack { view }.environment(store)) {
            var webView: WKWebView?
            let deadline = ContinuousClock.now + .seconds(3)
            while webView == nil, ContinuousClock.now < deadline {
                let representable = try view.inspect().find(ArticleWebView.self).actualView()
                #if os(macOS)
                webView = try? representable.nsView()
                #else
                webView = try? representable.uiView()
                #endif
                if webView == nil { try await Task.sleep(for: .milliseconds(100)) }
            }
            try await body(try #require(webView, "The article view shows no web view"))
        }
    }
}
