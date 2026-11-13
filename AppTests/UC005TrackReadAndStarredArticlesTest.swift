import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import ViewInspector
#if os(macOS)
import AppKit
#endif

/// UC-005 Track Read and Starred Articles, tested through the app's main window (sidebar, article list, article view)
/// against the real FeedStore and a temporary library file that `withReader` writes. The Reader toggles the read state
/// and the star of an article with the entries of its row's menu in the list (on iPhone and iPad also with the row's
/// swipe actions) or with the buttons of the displayed article's toolbar, and marks a whole list as read with the
/// list's Mark All as Read button. What the library saved is read back from the library file.
@MainActor
@Suite("UC-005 Track Read and Starred Articles", .serialized, .timeLimit(.minutes(1)))
struct UC005TrackReadAndStarredArticlesTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: the Reader toggles the read state of an article in the list; the list, the unread counts, and the library follow")
    func mainSuccessScenario() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            #expect(try await reader.row("Quasar").showsUnread)

            // Steps 1 to 3: the Reader chooses Quasar in the list and toggles its read state; unread becomes read.
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            #expect(reader.article("Quasar").isRead)

            // Step 4: the list and the unread counts follow.
            #expect(try await !reader.row("Quasar").showsUnread)
            #expect(try await reader.feedBadges() == ["Alpha": 2, "Beta": 1])
            #expect(try await reader.unreadBadge() == 3)

            // Step 5: the change is saved.
            try await reader.waitUntilSaved { $0("Quasar")?.isRead == true }

            // Success postcondition: no other article changed its state.
            reader.expectUnchanged(except: ["Quasar"])
        }
    }

    @Test("Step 3: an article that was read is marked as unread, and the list, the unread counts, and the library follow")
    func readArticleBecomesUnread() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)

            try await reader.tapRowMenuButton("Mark as Unread", ofArticle: "Comet")

            #expect(!reader.article("Comet").isRead)
            #expect(try await reader.row("Comet").showsUnread)
            #expect(try await reader.feedBadges() == ["Alpha": 3, "Beta": 2])
            #expect(try await reader.unreadBadge() == 5)
            try await reader.waitUntilSaved { $0("Comet")?.isRead == false }
            reader.expectUnchanged(except: ["Comet"])
        }
    }

    @Test("Step 1: the Reader toggles the read state of the displayed article, back and forth")
    func displayedArticleTogglesRead() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Quasar")
            #expect(reader.article("Quasar").isRead)

            try await reader.tapArticleButton("Mark as Unread")
            #expect(!reader.article("Quasar").isRead)
            #expect(try await reader.row("Quasar").showsUnread)
            #expect(try await reader.unreadBadge() == 4)

            try await reader.tapArticleButton("Mark as Read")
            #expect(reader.article("Quasar").isRead)
            #expect(try await !reader.row("Quasar").showsUnread)
            #expect(try await reader.unreadBadge() == 3)
            try await reader.waitUntilSaved { $0("Quasar")?.isRead == true }
        }
    }

    #if os(iOS)
    @Test("Step 1: on iPhone and iPad the Reader toggles the read state and the star of an article with the row's swipe actions")
    func swipeActionsToggleReadAndStar() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)

            try await reader.tapSwipeAction("Read", ofArticle: "Quasar")
            #expect(reader.article("Quasar").isRead)
            #expect(try await reader.unreadBadge() == 3)

            try await reader.tapSwipeAction("Unread", ofArticle: "Quasar")
            #expect(!reader.article("Quasar").isRead)

            try await reader.tapSwipeAction("Star", ofArticle: "Quasar")
            #expect(reader.article("Quasar").isStarred)
            #expect(try await reader.row("Quasar").starred)

            try await reader.tapSwipeAction("Unstar", ofArticle: "Quasar")
            #expect(!reader.article("Quasar").isStarred)
            try await reader.waitUntilSaved { $0("Quasar")?.isStarred == false && $0("Quasar")?.isRead == false }
        }
    }
    #endif

    // MARK: - A1 Toggle Star

    @Test("A1: the Reader stars an article in the list; its row shows the star, the Starred list holds it, and the star is saved")
    func starArticleInList() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            #expect(try await !reader.row("Quasar").starred)

            try await reader.tapRowMenuButton("Star", ofArticle: "Quasar")

            #expect(reader.article("Quasar").isStarred)
            #expect(try await reader.row("Quasar").starred)
            try await reader.selectList(.starred)
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse"])
            try await reader.waitUntilSaved { $0("Quasar")?.isStarred == true }
            // The read state stays as it was.
            #expect(!reader.article("Quasar").isRead)
            reader.expectUnchanged(except: ["Quasar"])
        }
    }

    @Test("A1: the Reader removes the star of the displayed article; the article view and the list show no star, and it is saved")
    func unstarDisplayedArticle() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.openArticle("Eclipse")
            #expect(try await reader.articleToolbarButtons().contains("Unstar"))

            try await reader.tapArticleButton("Unstar")

            #expect(!reader.article("Eclipse").isStarred)
            let buttons = try await reader.articleToolbarButtons()
            #expect(buttons.contains("Star") && !buttons.contains("Unstar"))
            #expect(try await !reader.row("Eclipse").starred)
            try await reader.waitUntilSaved { $0("Eclipse")?.isStarred == false }

            try await reader.tapArticleButton("Star")
            #expect(reader.article("Eclipse").isStarred)
            #expect(try await reader.articleToolbarButtons().contains("Unstar"))
            #expect(try await reader.row("Eclipse").starred)
            try await reader.waitUntilSaved { $0("Eclipse")?.isStarred == true }
        }
    }

    // MARK: - A2 Mark All as Read

    @Test("A2: the Reader marks all articles of a feed as read; its unread articles are read, the counts follow, and it is saved")
    func markAllOfFeedAsRead() async throws {
        try await withReader { reader in
            try await reader.selectList(.feed(reader.feedID("Alpha")))

            try await reader.tapMarkAllAsRead()

            #expect(reader.article("Eclipse").isRead && reader.article("Nebula").isRead)
            let rows = try await reader.state().rows
            #expect(rows.map(\.title) == ["Comet", "Eclipse", "Nebula"])
            #expect(rows.allSatisfy { !$0.showsUnread })
            #expect(try await reader.feedBadges() == ["Alpha": 0, "Beta": 2])
            #expect(try await reader.unreadBadge() == 2)
            try await reader.waitUntilSaved { $0("Eclipse")?.isRead == true && $0("Nebula")?.isRead == true }
            reader.expectUnchanged(except: ["Eclipse", "Nebula"])
        }
    }

    // MARK: - A3 Nothing to Mark

    @Test("A3: Mark All as Read in a list without unread articles leaves the library unchanged")
    func nothingToMarkInFeed() async throws {
        let articles = [
            StoredArticle(feed: alpha, key: "comet", title: "Comet", minutesAgo: 10, read: true),
            StoredArticle(feed: alpha, key: "eclipse", title: "Eclipse", minutesAgo: 20, read: true, starred: true),
            StoredArticle(feed: beta, key: "quasar", title: "Quasar", minutesAgo: 15),
        ]
        try await withReader(articles: articles) { reader in
            try await reader.selectList(.feed(reader.feedID("Alpha")))
            let before = reader.store.articles
            let file = try reader.libraryFile()

            try await reader.tapMarkAllAsRead()

            #expect(reader.store.articles == before)
            #expect(try await reader.state().listedTitles == ["Comet", "Eclipse"])
            #expect(try await reader.unreadBadge() == 1)
            // Nothing is saved: the library file stays as it was, also after the 2 seconds of BR-002.
            try await Task.sleep(for: .milliseconds(2500))
            #expect(try reader.libraryFile() == file)
        }
    }

    @Test("A3: in Unread without unread articles, Mark All as Read changes nothing, and the articles read by displaying them leave the list")
    func nothingToMarkInUnread() async throws {
        try await withReader { reader in
            for title in ["Quasar", "Eclipse", "Pulsar", "Nebula"] {
                try await reader.openArticle(title)
            }
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Pulsar", "Nebula"])
            let before = reader.store.articles

            try await reader.tapMarkAllAsRead()

            #expect(reader.store.articles == before)
            #expect(try await reader.state().listedTitles.isEmpty)
        }
    }

    // MARK: - A4 Saving Fails

    @Test("A4: when the library cannot be saved the changes stay in effect, the Reader is not told, and the next save stores them")
    func unsavedChangesGoWithNextSave() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            reader.makeLibraryUnwritable()
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            try await reader.tapRowMenuButton("Star", ofArticle: "Pulsar")
            // Past the 2 seconds of BR-002, so the save has been tried and failed.
            try await Task.sleep(for: .milliseconds(2500))

            #expect(reader.article("Quasar").isRead)
            #expect(reader.article("Pulsar").isStarred)
            #expect(try await !reader.row("Quasar").showsUnread)
            #expect(try await reader.row("Pulsar").starred)
            #expect(reader.reloadedArticle("Quasar")?.isRead == false)
            #expect(reader.reloadedArticle("Pulsar")?.isStarred == false)
            #expect(try await reader.showsAlert() == false)
            // Failure postcondition: no article outside the chosen ones changes its state.
            reader.expectUnchanged(except: ["Quasar", "Pulsar"])

            reader.makeLibraryWritable()
            try await reader.tapRowMenuButton("Star", ofArticle: "Nebula")
            try await reader.waitUntilSaved { $0("Nebula")?.isStarred == true }
            #expect(reader.reloadedArticle("Quasar")?.isRead == true)
            #expect(reader.reloadedArticle("Pulsar")?.isStarred == true)
            reader.expectUnchanged(except: ["Quasar", "Pulsar", "Nebula"], inLibrary: true)
        }
    }

    // MARK: - BR-001 Mark All Is Limited to the List

    @Test("BR-001: Mark All as Read marks only the unread articles of the displayed list", arguments: [
        ("Alpha", ["Eclipse", "Nebula"]),
        ("Starred", ["Eclipse"]),
        ("Unread", ["Quasar", "Eclipse", "Pulsar", "Nebula"]),
        ("All Articles", ["Quasar", "Eclipse", "Pulsar", "Nebula"]),
    ])
    func markAllIsLimitedToList(list: String, marked: [String]) async throws {
        try await withReader { reader in
            let item: SidebarItem = switch list {
            case "Unread": .unread
            case "All Articles": .all
            case "Starred": .starred
            default: .feed(reader.feedID(list))
            }
            try await reader.selectList(item)

            try await reader.tapMarkAllAsRead()

            for title in marked {
                #expect(reader.article(title).isRead, "\(title)")
            }
            reader.expectUnchanged(except: Set(marked))
            try await reader.waitUntilSaved { article in marked.allSatisfy { article($0)?.isRead == true } }
            reader.expectUnchanged(except: Set(marked), inLibrary: true)
        }
    }

    // MARK: - BR-002 Saving State Changes

    @Test("BR-002: read and starred changes are saved at most 2 seconds after the last change")
    func changesAreSavedWithinTwoSeconds() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            try await Task.sleep(for: .seconds(1))
            try await reader.tapRowMenuButton("Star", ofArticle: "Pulsar")
            let lastChange = ContinuousClock.now

            try await reader.waitUntilSaved { $0("Quasar")?.isRead == true && $0("Pulsar")?.isStarred == true }
            #expect(ContinuousClock.now - lastChange <= .milliseconds(2500))
        }
    }

    #if os(macOS)
    @Test("BR-002: pending read and starred changes are saved when the app quits")
    func changesAreSavedOnQuit() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            try await reader.tapRowMenuButton("Star", ofArticle: "Pulsar")

            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)

            // At once, well before the 2 seconds after the last change.
            #expect(reader.reloadedArticle("Quasar")?.isRead == true)
            #expect(reader.reloadedArticle("Pulsar")?.isStarred == true)
        }
    }

    @Test("BR-002: on the Mac, pending read and starred changes are saved when the app moves to the background (OQ-007)")
    func changesAreSavedWhenAppResignsActive() async throws {
        try await withReader { reader in
            try await reader.selectList(.all)
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            try await reader.tapRowMenuButton("Star", ofArticle: "Pulsar")
            #expect(reader.reloadedArticle("Quasar")?.isRead == false)

            // Another app becomes active or the app is hidden: either way the app resigns active.
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)

            // At once, well before the 2 seconds after the last change.
            #expect(reader.reloadedArticle("Quasar")?.isRead == true)
            #expect(reader.reloadedArticle("Pulsar")?.isStarred == true)
        }
    }
    #else
    @Test("BR-002: pending read and starred changes are saved when the app moves to the background")
    func changesAreSavedInBackground() async throws {
        try await withScheduledReader { reader, scene in
            try await reader.selectList(.all)
            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")
            try await reader.tapRowMenuButton("Star", ofArticle: "Pulsar")
            #expect(reader.reloadedArticle("Quasar")?.isRead == false)

            scene.phase = .background
            try await Task.sleep(for: .milliseconds(100))

            // At once, well before the 2 seconds after the last change.
            #expect(reader.reloadedArticle("Quasar")?.isRead == true)
            #expect(reader.reloadedArticle("Pulsar")?.isStarred == true)
        }
    }
    #endif

    // MARK: - BR-003 Starred Articles Are Kept

    @Test("BR-003: an article the Reader starred does not expire on refresh, while an unstarred one does (UC-003 BR-008)")
    func starredArticleDoesNotExpire() async throws {
        let monthAgo = 31.0 * 24 * 60
        let articles = [
            StoredArticle(feed: alpha, key: "keeper", title: "Keeper", minutesAgo: monthAgo, fetchedMinutesAgo: monthAgo, read: true),
            StoredArticle(feed: alpha, key: "goner", title: "Goner", minutesAgo: monthAgo, fetchedMinutesAgo: monthAgo, read: true),
        ]
        let answers: [URL: FeedPublisherStub.Answer] = [
            alpha.url: .document(Documents.rss(title: "Alpha", items: [("fresh", "Fresh")])),
        ]
        try await withReader(feeds: [alpha], articles: articles, answers: answers) { reader in
            try await reader.selectList(.all)
            try await reader.tapRowMenuButton("Star", ofArticle: "Keeper")

            try await reader.refreshFromToolbar()

            #expect(reader.store.articles.contains { $0.title == "Keeper" && $0.isStarred })
            #expect(!reader.store.articles.contains { $0.title == "Goner" })
            #expect(reader.store.articles.contains { $0.title == "Fresh" })
        }
    }

    @Test("BR-003: a starred article is removed when its feed is unsubscribed (UC-002 BR-001)")
    func starredArticleLeavesWithItsFeed() async throws {
        try await withReader { reader in
            #expect(reader.article("Eclipse").isStarred)

            try await reader.unsubscribe("Alpha")

            #expect(!reader.store.articles.contains { $0.title == "Eclipse" })
            try await reader.selectList(.starred)
            #expect(try await reader.state().listedTitles.isEmpty)
            #expect(reader.reloadedArticle("Eclipse") == nil)
        }
    }

    // MARK: - BR-004 The List Follows a Change at Once

    @Test("BR-004: an article marked as read in Unread leaves the list at once; articles read by displaying them stay")
    func markedReadLeavesUnread() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")

            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Pulsar")

            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Nebula"])
        }
    }

    @Test("BR-004: an article unstarred in Starred leaves the list at once")
    func unstarredLeavesStarred() async throws {
        try await withReader { reader in
            try await reader.selectList(.starred)
            #expect(try await reader.state().listedTitles == ["Eclipse"])

            try await reader.tapRowMenuButton("Unstar", ofArticle: "Eclipse")

            #expect(try await reader.state().listedTitles.isEmpty)
        }
    }

    @Test("BR-004: Mark All as Read in Unread empties the list, articles read by displaying them included")
    func markAllEmptiesUnread() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            try await reader.openArticle("Eclipse")
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Pulsar", "Nebula"])

            try await reader.tapMarkAllAsRead()

            #expect(try await reader.state().listedTitles.isEmpty)
        }
    }

    @Test("BR-004: an article displayed before in the visit leaves Unread at once when the Reader marks it as read with the toggle")
    func displayedBeforeLeavesUnreadOnToggle() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            try await reader.openArticle("Eclipse")
            try await reader.tapRowMenuButton("Mark as Unread", ofArticle: "Quasar")
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Pulsar", "Nebula"])

            try await reader.tapRowMenuButton("Mark as Read", ofArticle: "Quasar")

            #expect(try await reader.state().listedTitles == ["Eclipse", "Pulsar", "Nebula"])
        }
    }

    @Test("BR-004: the displayed article leaves Unread at once when the Reader marks it as read with the toggle")
    func displayedArticleLeavesUnreadOnToggle() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            try await reader.tapArticleButton("Mark as Unread")
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse", "Pulsar", "Nebula"])

            try await reader.tapArticleButton("Mark as Read")

            #expect(try await reader.state().listedTitles == ["Eclipse", "Pulsar", "Nebula"])
        }
    }

    @Test("BR-004: an article displayed before in the visit and marked as unread leaves Unread when Mark All as Read marks it")
    func displayedBeforeLeavesUnreadOnMarkAll() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")
            try await reader.tapArticleButton("Mark as Unread")

            try await reader.tapMarkAllAsRead()

            #expect(reader.article("Quasar").isRead)
            #expect(try await reader.state().listedTitles.isEmpty)
        }
    }

    // MARK: - BR-005 Unread Stays Unread While Displayed

    @Test("BR-005: an article marked as unread while displayed stays unread, and is read again only when displayed anew")
    func unreadStaysUnreadWhileDisplayed() async throws {
        try await withReader { reader in
            try await reader.openArticle("Quasar")

            try await reader.tapArticleButton("Mark as Unread")
            // Past the save of BR-002, so the article is not marked as read again behind the Reader's back.
            try await Task.sleep(for: .milliseconds(2500))

            #expect(try await reader.displayedTitle() == "Quasar")
            #expect(!reader.article("Quasar").isRead)
            #expect(try await reader.row("Quasar").showsUnread)
            #expect(reader.reloadedArticle("Quasar")?.isRead == false)

            try await reader.openArticle("Eclipse")
            #expect(!reader.article("Quasar").isRead)
            try await reader.openArticle("Quasar")
            #expect(reader.article("Quasar").isRead)
        }
    }

    // MARK: - BR-006 The Displayed Article Stays When It Leaves the List

    @Test("BR-006: the displayed article that leaves Unread stays displayed, and Previous and Next go to its former neighbours",
          arguments: [("Previous Article", "Quasar"), ("Next Article", "Pulsar")])
    func displayedArticleStaysWhenLeavingUnread(button: String, expected: String) async throws {
        try await withReader { reader in
            try await reader.openArticle("Eclipse")
            try await reader.tapArticleButton("Mark as Unread")
            try await reader.tapArticleButton("Mark as Read")
            #expect(try await reader.state().listedTitles == ["Quasar", "Pulsar", "Nebula"])
            #expect(try await reader.displayedTitle() == "Eclipse")

            try await reader.tapArticleButton(button)

            #expect(try await reader.displayedTitle() == expected)
        }
    }

    @Test("BR-006: the displayed article that leaves Starred stays displayed until the Reader moves on, and Next goes to its former neighbour")
    func displayedArticleStaysWhenLeavingStarred() async throws {
        var articles = standardArticles
        articles[3].starred = true  // Quasar
        try await withReader(articles: articles) { reader in
            try await reader.selectList(.starred)
            #expect(try await reader.state().listedTitles == ["Quasar", "Eclipse"])
            try await reader.openArticle("Quasar")

            try await reader.tapArticleButton("Unstar")

            #expect(try await reader.state().listedTitles == ["Eclipse"])
            #expect(try await reader.displayedTitle() == "Quasar")
            #expect(try await reader.articleButtonIsDisabled("Previous Article"))

            try await reader.tapArticleButton("Next Article")
            #expect(try await reader.displayedTitle() == "Eclipse")
        }
    }

    #if os(iOS)
    @Test("BR-006: on iPad, ↑ and ↓ in the list go to the former neighbours of the displayed article that left Unread",
          arguments: [(KeyEquivalent.upArrow, "Quasar"), (KeyEquivalent.downArrow, "Pulsar")])
    func arrowKeysFromArticleThatLeftUnread(key: KeyEquivalent, expected: String) async throws {
        try await withReader { reader in
            try await reader.openArticle("Eclipse")
            try await reader.tapArticleButton("Mark as Unread")
            try await reader.tapArticleButton("Mark as Read")
            #expect(try await reader.state().listedTitles == ["Quasar", "Pulsar", "Nebula"])
            #expect(try await reader.displayedTitle() == "Eclipse")

            try await reader.pressKeyInList(key)

            #expect(try await reader.displayedTitle() == expected)
        }
    }

    @Test("BR-006: on iPad, ↓ in the list goes to the former neighbour of the displayed article that left Starred, and ↑ without one keeps it displayed")
    func arrowKeysFromArticleThatLeftStarred() async throws {
        var articles = standardArticles
        articles[3].starred = true  // Quasar
        try await withReader(articles: articles) { reader in
            try await reader.selectList(.starred)
            try await reader.openArticle("Quasar")
            try await reader.tapArticleButton("Unstar")
            #expect(try await reader.state().listedTitles == ["Eclipse"])

            try await reader.pressKeyInList(.upArrow)
            #expect(try await reader.displayedTitle() == "Quasar")

            try await reader.pressKeyInList(.downArrow)
            #expect(try await reader.displayedTitle() == "Eclipse")
        }
    }
    #endif
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
    /// Minutes since publication; nil for an article without a publication date.
    var minutesAgo: Double?
    var fetchedMinutesAgo: Double = 60
    var read = false
    var starred = false

    func json(now: Date) -> [String: Any] {
        var value: [String: Any] = [
            "id": "\(feed.id.uuidString)|\(key)", "feedID": feed.id.uuidString, "title": title,
            "contentHTML": "<p>\(title) body</p>", "snippet": "\(title) snippet",
            "fetched": now.addingTimeInterval(-fetchedMinutesAgo * 60).timeIntervalSinceReferenceDate,
            "isRead": read, "isStarred": starred,
        ]
        if let link { value["link"] = link }
        if let minutesAgo { value["published"] = now.addingTimeInterval(-minutesAgo * 60).timeIntervalSinceReferenceDate }
        return value
    }
}

/// Alpha: Comet (read), Eclipse (starred), Nebula. Beta: Quasar, Pulsar (no publication date, fetched 30 minutes ago).
/// Newest first: Comet 10, Quasar 15, Eclipse 20, Pulsar 30, Nebula 40 minutes ago. Unread: Quasar, Eclipse, Pulsar,
/// Nebula.
private let standardArticles: [StoredArticle] = [
    StoredArticle(feed: alpha, key: "comet", title: "Comet", link: "https://alpha.example/comet", minutesAgo: 10, read: true),
    StoredArticle(feed: alpha, key: "eclipse", title: "Eclipse", link: "https://alpha.example/eclipse", minutesAgo: 20, starred: true),
    StoredArticle(feed: alpha, key: "nebula", title: "Nebula", minutesAgo: 40),
    StoredArticle(feed: beta, key: "quasar", title: "Quasar", link: "https://beta.example/quasar", minutesAgo: 15),
    StoredArticle(feed: beta, key: "pulsar", title: "Pulsar", link: "https://beta.example/pulsar",
                  minutesAgo: nil, fetchedMinutesAgo: 30),
]

// MARK: - Test harness

/// One listed article as its row shows it.
private struct Row {
    var title: String?
    var starred: Bool
    /// The colour of the row's read-state mark.
    var readMark: Color?

    /// The row marks the article as unread.
    var showsUnread: Bool { readMark != nil && readMark != .clear }
}

/// What the main window shows: the selected list and its rows.
private struct WindowState {
    var list: SidebarItem?
    var rows: [Row] = []

    var listedTitles: [String] { rows.compactMap(\.title) }
}

/// Drives one hosted main window.
@MainActor
private struct Reader {
    let view: ContentView
    let store: FeedStore
    let libraryURL: URL
    /// The articles as the library held them when the window opened.
    let initial: [Article]

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

    func libraryFile() throws -> Data {
        try Data(contentsOf: libraryURL)
    }

    /// Every article except `titles` keeps the read and starred state it had when the window opened, in memory or, with
    /// `inLibrary`, in the library file.
    func expectUnchanged(except titles: Set<String>, inLibrary: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) {
        let current = inLibrary ? FeedStore(fileURL: libraryURL).articles : store.articles
        for before in initial where !titles.contains(before.title) {
            let now = current.first { $0.id == before.id }
            #expect(now?.isRead == before.isRead, "\(before.title) read", sourceLocation: sourceLocation)
            #expect(now?.isStarred == before.isStarred, "\(before.title) starred", sourceLocation: sourceLocation)
        }
    }

    /// Waits until the library file satisfies `condition` — at most the 2 seconds of BR-002 plus the time the test
    /// needs to read the file back.
    func waitUntilSaved(_ condition: ((String) -> Article?) -> Bool) async throws {
        try await waitUntil(timeout: .milliseconds(2500)) {
            let saved = FeedStore(fileURL: libraryURL).articles
            return condition { title in saved.first { $0.title == title } }
        }
    }

    /// Inspects the live window. The store is put into the inspected hierarchy again, so the child views ViewInspector
    /// builds find it in their environment, as they do in the app.
    private func inspect(_ body: @escaping @MainActor @Sendable (InspectableView<ViewType.ClassifiedView>) async throws -> Void) async throws {
        let store = store
        try await view.inspection.inspect { view in
            try await body(try view.actualView().environment(store).inspect())
        }
    }

    // MARK: Sidebar

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

    /// The Reader chooses Unsubscribe in the feed's menu in the subscription list (UC-002).
    func unsubscribe(_ title: String) async throws {
        let index = try #require(store.feeds.firstIndex { $0.title == title })
        try await inspect { view in
            let rows = try view.find(SidebarView.self).find(ViewType.ForEach.self)
            let menu = Self.menuContent(ofRow: Array(rows)[index])
            let entry = try #require(menuButtons(in: menu).first {
                (try? $0.inspect().button().labelView().text().string()) == "Unsubscribe"
            })
            try entry.inspect().button().tap()
        }
        try await settle()
    }

    // MARK: Article list

    func state() async throws -> WindowState {
        let box = ResultBox(WindowState())
        try await inspect { view in
            let list = try view.find(ArticleListView.self)
            var state = WindowState(list: try list.actualView().sidebarSelection)
            if let rows = try? list.find(ViewType.ForEach.self) {
                state.rows = try rows.map(Self.row)
            }
            box.value = state
        }
        return box.value
    }

    /// The listed row of the article titled `title`.
    func row(_ title: String) async throws -> Row {
        try #require(try await state().rows.first { $0.title == title }, "\(title) is not listed")
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
            title: texts.indices.contains(2) ? texts[2] : nil,
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

    /// A2: the Reader chooses Mark All as Read in the article list's toolbar.
    func tapMarkAllAsRead() async throws {
        try await inspect { view in
            let toolbar = try view.find(ArticleListView.self).find(ViewType.Toolbar.self)
            let button = try #require(toolbar.findAll(ViewType.Button.self).first {
                (try? $0.labelView().find(ViewType.Text.self).string()) == "Mark All as Read"
            })
            try button.tap()
        }
        try await settle()
    }

    /// UC-003: the Reader taps Refresh in the article list's toolbar and waits until the refresh has finished.
    func refreshFromToolbar() async throws {
        try await inspect { view in
            let toolbar = try view.find(ArticleListView.self).find(ViewType.Toolbar.self)
            let button = try #require(toolbar.findAll(ViewType.Button.self).first {
                (try? $0.labelView().find(text: "Refresh")) != nil
            })
            try button.tap()
        }
        let feedURLs = Set(store.feeds.map(\.url))
        try await waitUntil { FeedPublisherStub.receivedRequests.contains { $0.url.map(feedURLs.contains) == true } }
        try await waitUntil { !store.isRefreshing }
        try await settle()
    }

    /// The Reader chooses an entry of a list row's menu.
    func tapRowMenuButton(_ entry: String, ofArticle title: String) async throws {
        try await inspect { view in
            let row = try Self.listRow(ofArticle: title, in: view)
            let button = try #require(menuButtons(in: Self.menuContent(ofRow: row)).first {
                (try? $0.inspect().button().labelView().text().string()) == entry
            }, "The menu of \(title) has no entry \(entry)")
            try button.inspect().button().tap()
        }
        try await settle()
    }

    #if os(iOS)
    /// The Reader swipes a list row and chooses the action titled `action`. ViewInspector cannot search swipe actions,
    /// so the action's button is taken from the row by reflection.
    func tapSwipeAction(_ action: String, ofArticle title: String) async throws {
        try await inspect { view in
            let row = try Self.listRow(ofArticle: title, in: view)
            let buttons = values(in: row) { String(describing: type(of: $0)).hasPrefix("Button<Label<") }
            let button = try #require(buttons.compactMap { $0 as? any View }.first {
                (try? $0.inspect().button().labelView().find(ViewType.Text.self).string()) == action
            }, "The row of \(title) has no swipe action \(action)")
            try button.inspect().button().tap()
        }
        try await settle()
    }

    /// The Reader presses a key on the hardware keyboard while the article list has the focus (iPad). ViewInspector
    /// cannot send key presses, so the list's `onKeyPress` handler for `key` is taken from its modifiers by reflection
    /// and called with a key press built from the same fields as SwiftUI's `KeyPress`.
    func pressKeyInList(_ key: KeyEquivalent) async throws {
        try await inspect { view in
            let list = try view.find(ArticleListView.self).find(ViewType.List.self)
            let modifiers = Mirror(reflecting: list).descendant("content", "medium", "viewModifiers") as? [Any] ?? []
            let handler = try #require(modifiers.lazy.compactMap { modifier -> ((KeyPress) -> KeyPress.Result)? in
                guard let handler = Mirror(reflecting: modifier).descendant("modifier", "handler"),
                      let keys = Mirror(reflecting: handler).descendant("subject", "keys") as? Set<KeyEquivalent>,
                      keys.contains(key) else { return nil }
                return Mirror(reflecting: handler).descendant("action") as? (KeyPress) -> KeyPress.Result
            }.first, "The article list does not handle the key")
            _ = handler(try makeKeyPress(key))
        }
        try await settle()
    }
    #endif

    private static func listRow(ofArticle title: String, in view: InspectableView<ViewType.ClassifiedView>) throws -> InspectableView<ViewType.ClassifiedView> {
        let rows = try view.find(ArticleListView.self).find(ViewType.ForEach.self)
        return try #require(rows.first { (try? Self.row($0).title) == title }, "\(title) is not listed")
    }

    /// The content of a row's context menu. ViewInspector cannot search a context menu, so its content is taken from
    /// the row's modifiers by reflection.
    private static func menuContent(ofRow row: InspectableView<ViewType.ClassifiedView>) -> [Any] {
        let modifiers = Mirror(reflecting: row).descendant("content", "medium", "viewModifiers") as? [Any] ?? []
        return modifiers.compactMap { Mirror(reflecting: $0).descendant("modifier", "menuView") }
    }

    // MARK: Article view

    /// The title of the displayed article; nil when none is displayed.
    func displayedTitle() async throws -> String? {
        let box = ResultBox<String?>(nil)
        try await inspect { view in
            box.value = (try? view.find(ArticleDetailView.self).actualView().article.title)
        }
        return box.value
    }

    private static func articleToolbarButtons(in view: InspectableView<ViewType.ClassifiedView>) throws -> [InspectableView<ViewType.Button>] {
        Array(try view.find(ArticleDetailView.self).find(ArticleWebView.self).toolbar().findAll(ViewType.Button.self))
    }

    private static func title(of button: InspectableView<ViewType.Button>) -> String? {
        try? button.labelView().find(ViewType.Text.self).string()
    }

    /// The titles of the buttons of the article view's toolbar.
    func articleToolbarButtons() async throws -> [String] {
        let box = ResultBox<[String]>([])
        try await inspect { view in
            box.value = try Self.articleToolbarButtons(in: view).compactMap(Self.title)
        }
        return box.value
    }

    func articleButtonIsDisabled(_ title: String) async throws -> Bool {
        let box = ResultBox(false)
        try await inspect { view in
            let button = try #require(try Self.articleToolbarButtons(in: view).first { Self.title(of: $0) == title })
            box.value = button.isDisabled()
        }
        return box.value
    }

    /// The Reader chooses a button of the article view's toolbar.
    func tapArticleButton(_ title: String) async throws {
        try await inspect { view in
            let button = try #require(try Self.articleToolbarButtons(in: view).first { Self.title(of: $0) == title },
                                      "The article view has no button \(title)")
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
/// context menus, or swipe actions, so the tests take what those views hold by reflection.
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

#if os(iOS)
/// The stored properties of SwiftUI's `KeyPress`, in their declared order, which has no public initializer.
private struct KeyPressFields {
    let phase: KeyPress.Phases
    let key: KeyEquivalent
    let characters: String
    let modifiers: EventModifiers
}

/// A key-down press of `key` without modifiers, for calling an `onKeyPress` handler directly.
private func makeKeyPress(_ key: KeyEquivalent) throws -> KeyPress {
    try #require(MemoryLayout<KeyPressFields>.size == MemoryLayout<KeyPress>.size,
                 "SwiftUI's KeyPress no longer has the layout the test builds")
    let fields = KeyPressFields(phase: .down, key: key, characters: String(key.character), modifiers: [])
    return unsafeBitCast(fields, to: KeyPress.self)
}
#endif

private func menuButtons(in menu: [Any]) -> [Button<Text>] {
    values(in: menu) { $0 is Button<Text> }.compactMap { $0 as? Button<Text> }
}

// MARK: - Window

/// Writes a fresh library that holds `feeds` and `articles` to a temporary folder, as the file FeedStore keeps, and
/// opens a store on it. The subscription list loads the feeds' favicons, so the test holds `FeedPublisherStub` with
/// `answers` for the whole test: no request leaves the machine, and none reaches another suite's stub.
@MainActor
private func withLibrary(
    feeds: [Feed],
    articles: [StoredArticle],
    answers: [URL: FeedPublisherStub.Answer],
    _ body: @MainActor (FeedStore, URL) async throws -> Void
) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "UC005-\(UUID().uuidString)")
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
    try await FeedPublisherStub.withAnswers(answers) {
        try await body(store, libraryURL)
    }
}

/// Opens the main window over the library `withLibrary` writes.
@MainActor
private func withReader(
    feeds: [Feed] = [alpha, beta],
    articles: [StoredArticle] = standardArticles,
    answers: [URL: FeedPublisherStub.Answer] = [:],
    _ body: @MainActor (Reader) async throws -> Void
) async throws {
    try await withLibrary(feeds: feeds, articles: articles, answers: answers) { store, libraryURL in
        let view = ContentView()
        let reader = Reader(view: view, store: store, libraryURL: libraryURL, initial: store.articles)
        try await ViewHosting.host(view.environment(store).frame(width: 1000, height: 600)) {
            try await body(reader)
        }
    }
}

#if os(iOS)
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

/// Opens the main window as the app does on iPhone and iPad, under a scene phase the test controls, and waits until
/// the refresh at start has finished, so its save does not stand in for the one under test.
@MainActor
private func withScheduledReader(_ body: @MainActor (Reader, ScenePhaseBox) async throws -> Void) async throws {
    try await withLibrary(feeds: [alpha, beta], articles: standardArticles, answers: [:]) { store, libraryURL in
        let view = ContentView()
        let scene = ScenePhaseBox()
        let reader = Reader(view: view, store: store, libraryURL: libraryURL, initial: store.articles)
        try await ViewHosting.host(ScheduledWindow(content: view, store: store, scene: scene)
            .environment(store).frame(width: 1000, height: 600)) {
            // Every feed gets a 404 from the stub, so the refresh has run when every feed shows its problem.
            try await reader.waitUntil { store.feeds.allSatisfy { $0.lastError != nil } && !store.isRefreshing }
            try await body(reader, scene)
        }
    }
}
#endif
