import Foundation
import RSSReaderKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ViewInspector
#if os(macOS)
import AppKit
#endif

/// UC-007 Export Subscriptions, tested against the real FeedStore and a temporary library file.
///
/// The Reader starts an export with Export OPML… in the subscription list's toolbar menu on iPhone and iPad, and in
/// the File menu on the Mac. On iPhone and iPad the tests choose the entry and check the file exporter it presents
/// (step 2), cancel it (A2), and hand the subscription list the outcome the exporter reports (step 4, A1). On the Mac
/// the tests check the save panel the Export OPML… command presents (step 2), and hand `SubscriptionExport.run(_:)`
/// what the panel returns: the confirmed location (steps 3 and 4), no location for a cancelled panel (A2), and a
/// location that cannot be written, whose outcome the command shows in an alert (A1). Choosing the command and its
/// precondition are not tested on the Mac, an accepted limitation: a `CommandGroup` keeps its buttons in a closure
/// reflection cannot open, and the command runs the panel modally.
///
/// What is written to the file (step 4, BR-001, BR-002) is tested the way each platform writes it: on the Mac through
/// `SubscriptionExport.run(_:)` with the chosen location; on iPhone and iPad by writing the bytes of the document the
/// subscription list hands the file exporter (`SubscriptionExport.document`), since SwiftUI's exporter keeps the
/// document behind a closure whose result type is private to SwiftUI.
@MainActor
@Suite("UC-007 Export Subscriptions", .serialized)
struct UC007ExportSubscriptionsTest {

    // MARK: - Main success scenario

    @Test("Main success scenario: every subscription is written with its title, feed address, and website; the library is unchanged")
    func mainSuccessScenario() async throws {
        try await withExporter(feeds: [alpha, bravo, charlie], articles: articles) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)
            let feedsBefore = exporter.store.feeds
            let target = exporter.folder.appending(path: "Subscriptions.opml")

            try await exporter.export(to: target)

            // Step 4, success postcondition: the file holds every subscription of the library.
            let file = try ExportedFile(contentsOf: target)
            #expect(file.outlines.map(\.xmlUrl) == [alphaURL.absoluteString, bravoURL.absoluteString, charlieURL.absoluteString])
            #expect(file.outlines.map(\.text) == ["Alpha", "Bravo", "Charlie"])
            #expect(file.outlines.map(\.title) == ["Alpha", "Bravo", "Charlie"])
            #expect(file.outlines.map(\.htmlUrl) == ["https://alpha.example/", nil, "https://charlie.example/"])
            // Success postcondition: the library is unchanged.
            #expect(exporter.store.feeds == feedsBefore)
            #expect(exporter.store.articles.count == articles.count)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
            #if os(iOS)
            #expect(try await exporter.alertMessages().isEmpty)
            #endif
        }
    }

    #if os(iOS)
    @Test("Step 1, step 2: the Reader chooses Export OPML… in the subscription list's menu, and the system asks where to save, proposing \"Subscriptions.opml\"")
    func readerChoosesExportAndIsAskedWhereToSave() async throws {
        try await withExporter(feeds: [alpha]) { exporter in
            #expect(try await exporter.saveDialog() == nil)

            try await exporter.chooseExport()

            let dialog = try #require(try await exporter.saveDialog())
            #expect(dialog.defaultFilename == "Subscriptions.opml")
            // The unhosted test bundle declares no OPML type, so the type is recognized by its file name extension.
            #expect(dialog.allowedContentTypes.contains { $0.tags[.filenameExtension]?.contains("opml") == true })
        }
    }

    @Test("Step 1: Export OPML… can be chosen only while the library holds at least one feed (precondition)",
          arguments: [0, 1])
    func exportNeedsAFeed(feedCount: Int) async throws {
        try await withExporter(feeds: Array([alpha].prefix(feedCount))) { exporter in
            let disabled = try await exporter.isExportDisabled()
            #expect(disabled == (feedCount == 0))
        }
    }
    #else
    @Test("Step 2: the Export OPML… command asks where to save the file, proposing \"Subscriptions.opml\"")
    func exportCommandAsksWhereToSave() {
        let panel = FeedCommands.makeExportPanel()

        #expect(panel.nameFieldStringValue == "Subscriptions.opml")
        // The unhosted test bundle declares no OPML type, so the type is recognized by its file name extension.
        #expect(panel.allowedContentTypes.contains { $0.tags[.filenameExtension]?.contains("opml") == true })
    }
    #endif

    // MARK: - A1 File cannot be written

    @Test("A1: a file that cannot be written shows the message, leaves no partial file, keeps a file of the same name, and leaves the library unchanged",
          arguments: UnwritableLocation.allCases)
    func unwritableLocationShowsMessage(location: UnwritableLocation) async throws {
        try await withExporter(feeds: [alpha, bravo]) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)
            let feedsBefore = exporter.store.feeds
            let target = try location.prepare(in: exporter.folder)
            defer { location.restore(in: exporter.folder) }
            let folderBefore = location.contents(of: target)

            #if os(macOS)
            // Steps 3 and 4 as the Export OPML… command runs them with the location the Reader confirmed.
            let outcome = SubscriptionExport(store: exporter.store).run(target)
            guard case .failed(let error) = outcome else {
                Issue.record("The export ended with \(outcome) instead of failing")
                return
            }
            #expect(outcome.message == "The subscriptions could not be exported.")
            #else
            let error = try #require(throws: (any Error).self) { try exporter.store.exportOPML(to: target) }
            #endif

            // A1 step 1: the same message, whatever kept the file from being written.
            #expect(error.localizedDescription == "The subscriptions could not be exported.")
            #if os(macOS)
            // The Export OPML… command shows the error in an alert.
            #expect(NSAlert(error: error).messageText == "The subscriptions could not be exported.")
            #endif
            // Failure postcondition: no partly written file, and the file that already had the name is unchanged.
            #expect(location.contents(of: target) == folderBefore)
            if case .readOnlyFolder = location {
                #expect(try String(contentsOf: target, encoding: .utf8) == UnwritableLocation.earlierExport)
            }
            // Failure postcondition: the library is unchanged.
            #expect(exporter.store.feeds == feedsBefore)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
        }
    }

    #if os(iOS)
    @Test("A1: when the file exporter reports that it could not write the file, the message is displayed, whatever the cause",
          arguments: ExportFailure.allCases)
    func exporterFailureShowsMessage(failure: ExportFailure) async throws {
        try await withExporter(feeds: [alpha]) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)
            let feedsBefore = exporter.store.feeds

            try await exporter.chooseExport()
            try await exporter.exportFinished(.failure(failure.error))

            #expect(try await exporter.alertMessages() == ["The subscriptions could not be exported."])
            #expect(exporter.store.feeds == feedsBefore)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
        }
    }

    // MARK: - A2 Reader cancels

    @Test("A2: cancelling the save dialog ends the use case without a message and leaves the library unchanged")
    func cancellingWritesNothing() async throws {
        try await withExporter(feeds: [alpha]) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)
            let folderBefore = try FileManager.default.contentsOfDirectory(atPath: exporter.folder.path())

            try await exporter.chooseExport()
            try await exporter.cancelSaveDialog()

            #expect(try await exporter.alertMessages().isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: exporter.folder.path()) == folderBefore)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
        }
    }

    @Test("A2: a cancellation the file exporter reports as its outcome displays no message")
    func reportedCancellationShowsNoMessage() async throws {
        try await withExporter(feeds: [alpha]) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)

            try await exporter.chooseExport()
            try await exporter.exportFinished(.failure(CocoaError(.userCancelled)))

            #expect(try await exporter.alertMessages().isEmpty)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
        }
    }
    #else
    // MARK: - A2 Reader cancels

    @Test("A2: cancelling the Export OPML… command's save panel ends the use case without a message, writes nothing, and leaves the library unchanged")
    func cancellingThePanelWritesNothing() async throws {
        try await withExporter(feeds: [alpha]) { exporter in
            let libraryBefore = try Data(contentsOf: exporter.libraryURL)
            let feedsBefore = exporter.store.feeds
            let folderBefore = try FileManager.default.contentsOfDirectory(atPath: exporter.folder.path())

            // A cancelled panel hands the command no location.
            let outcome = SubscriptionExport(store: exporter.store).run(nil)

            guard case .cancelled = outcome else {
                Issue.record("The export ended with \(outcome) instead of being cancelled")
                return
            }
            #expect(outcome.message == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: exporter.folder.path()) == folderBefore)
            #expect(exporter.store.feeds == feedsBefore)
            #expect(try Data(contentsOf: exporter.libraryURL) == libraryBefore)
        }
    }
    #endif

    // MARK: - BR-001 Export format

    @Test("BR-001: an OPML 2.0 subscription list without folders; each entry carries the title as text and title, the feed address, and the website when the feed names one")
    func exportFormat() async throws {
        let special = Feed(title: #"Delta & <Friends> "quoted" 'too'"#, url: URL(string: "https://delta.example/feed.xml?a=1&b=2")!,
                           siteURL: URL(string: "https://delta.example/?lang=en&x=y")!)
        try await withExporter(feeds: [alpha, bravo, special]) { exporter in
            let target = exporter.folder.appending(path: "Subscriptions.opml")

            try await exporter.export(to: target)

            let file = try ExportedFile(contentsOf: target)
            #expect(file.rootElement == "opml")
            #expect(file.version == "2.0")
            #expect(file.hasHead)
            // Without folders: every entry sits directly in the body, none inside another.
            #expect(file.outlines.allSatisfy { $0.depth == 0 })
            #expect(file.outlines.count == 3)
            // The title as both its text and its title, the feed address, and the website — special characters included.
            let entry = try #require(file.outlines.first { $0.xmlUrl == "https://delta.example/feed.xml?a=1&b=2" })
            #expect(entry.text == #"Delta & <Friends> "quoted" 'too'"#)
            #expect(entry.title == #"Delta & <Friends> "quoted" 'too'"#)
            #expect(entry.htmlUrl == "https://delta.example/?lang=en&x=y")
            // A feed that names no website has no website entry.
            let bravoEntry = try #require(file.outlines.first { $0.xmlUrl == bravoURL.absoluteString })
            #expect(bravoEntry.htmlUrl == nil)
        }
    }

    @Test("BR-001: articles and their read or starred states are not exported")
    func articlesAreNotExported() async throws {
        try await withExporter(feeds: [alpha, bravo], articles: articles) { exporter in
            let target = exporter.folder.appending(path: "Subscriptions.opml")

            try await exporter.export(to: target)

            let file = try ExportedFile(contentsOf: target)
            // The body holds only the subscription entries, which carry nothing but their title and addresses.
            #expect(file.bodyElements == ["outline", "outline"])
            #expect(file.outlines.allSatisfy { Set($0.attributes.keys).isSubset(of: ["type", "text", "title", "xmlUrl", "htmlUrl"]) })
            let text = try String(contentsOf: target, encoding: .utf8)
            for article in articleRows {
                #expect(!text.contains(article.title))
                #expect(!text.contains(article.link))
            }
            #expect(!text.localizedCaseInsensitiveContains("starred"))
            #expect(!text.localizedCaseInsensitiveContains("isRead"))
        }
    }

    // MARK: - BR-002 Export order

    @Test("BR-002: entries are written in the subscription order, alphabetically by title ignoring case (UC-001 BR-005)")
    func entriesFollowSubscriptionOrder() async throws {
        try await withExporter(feeds: []) { exporter in
            // The subscriptions enter the library the way the app adds them, in an order that is not the subscription order.
            let subscribe = exporter.folder.appending(path: "subscribe.opml")
            try """
            <?xml version="1.0"?><opml version="2.0"><body>
            <outline text="Delta" xmlUrl="https://delta.example/feed.xml"/>
            <outline text="charlie" xmlUrl="https://charlie.example/feed.xml"/>
            <outline text="alpha" xmlUrl="https://alpha.example/feed.xml"/>
            <outline text="Bravo" xmlUrl="https://bravo.example/feed.xml"/>
            </body></opml>
            """.write(to: subscribe, atomically: true, encoding: .utf8)
            try exporter.store.importOPML(from: subscribe)
            let target = exporter.folder.appending(path: "Subscriptions.opml")

            try await exporter.export(to: target)

            #expect(try ExportedFile(contentsOf: target).outlines.map(\.title) == ["alpha", "Bravo", "charlie", "Delta"])
        }
    }
}

// MARK: - Test data

private let alphaURL = URL(string: "https://alpha.example/feed.xml")!
private let bravoURL = URL(string: "https://bravo.example/feed.xml")!
private let charlieURL = URL(string: "https://charlie.example/feed.xml")!

private let alpha = Feed(title: "Alpha", url: alphaURL, siteURL: URL(string: "https://alpha.example/"))
private let bravo = Feed(title: "Bravo", url: bravoURL)
private let charlie = Feed(title: "Charlie", url: charlieURL, siteURL: URL(string: "https://charlie.example/"))

/// Articles of Alpha and Bravo: one unread, one read, one read and starred.
private struct ArticleRow { var title: String; var link: String; var feed: Feed; var isRead: Bool; var isStarred: Bool }
private let articleRows = [
    ArticleRow(title: "Unread Quasar", link: "https://alpha.example/quasar", feed: alpha, isRead: false, isStarred: false),
    ArticleRow(title: "Read Nebula", link: "https://alpha.example/nebula", feed: alpha, isRead: true, isStarred: false),
    ArticleRow(title: "Starred Pulsar", link: "https://bravo.example/pulsar", feed: bravo, isRead: true, isStarred: true),
]
private var articles: [[String: Any]] {
    articleRows.enumerated().map { index, row in
        [
            "id": "article-\(index)", "feedID": row.feed.id.uuidString, "title": row.title, "link": row.link,
            "contentHTML": "<p>\(row.title)</p>", "snippet": row.title, "fetched": 800_000_000.0 + Double(index),
            "isRead": row.isRead, "isStarred": row.isStarred,
        ]
    }
}

/// Locations at which the file cannot be written (A1).
enum UnwritableLocation: CaseIterable, CustomTestStringConvertible, Sendable {
    /// A folder that accepts no writes and already holds a file with the chosen name.
    case readOnlyFolder
    /// A folder that does not exist.
    case missingFolder

    static let earlierExport = "<opml version=\"2.0\"><body><outline text=\"Earlier\" xmlUrl=\"https://earlier.example/feed.xml\"/></body></opml>"

    var testDescription: String {
        switch self {
        case .readOnlyFolder: "a read-only folder that already holds Subscriptions.opml"
        case .missingFolder: "a folder that does not exist"
        }
    }

    /// Prepares the location and returns the file the Reader chose.
    func prepare(in folder: URL) throws -> URL {
        switch self {
        case .readOnlyFolder:
            let target = folder.appending(path: "read-only").appending(path: "Subscriptions.opml")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.earlierExport.write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.deletingLastPathComponent().path())
            return target
        case .missingFolder:
            return folder.appending(path: "missing").appending(path: "Subscriptions.opml")
        }
    }

    /// The names in the chosen file's folder, or nil when the folder does not exist.
    func contents(of target: URL) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path()).sorted()
    }

    func restore(in folder: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "read-only").path())
    }
}

#if os(iOS)
/// Causes the file exporter reports for a file it could not write (A1).
enum ExportFailure: CaseIterable, CustomTestStringConvertible, Sendable {
    case noPermission
    case diskFull
    case unknown

    var testDescription: String {
        switch self {
        case .noPermission: "no permission to write"
        case .diskFull: "no space left"
        case .unknown: "an unknown error"
        }
    }

    var error: any Error {
        switch self {
        case .noPermission: CocoaError(.fileWriteNoPermission)
        case .diskFull: CocoaError(.fileWriteOutOfSpace)
        case .unknown: URLError(.unknown)
        }
    }
}
#endif

/// An exported file as an XML parser reads it.
private struct ExportedFile {
    struct Outline {
        var attributes: [String: String]
        /// The number of outlines it sits in.
        var depth: Int
        var text: String? { attributes["text"] }
        var title: String? { attributes["title"] }
        var xmlUrl: String? { attributes["xmlUrl"] }
        var htmlUrl: String? { attributes["htmlUrl"] }
    }

    var rootElement: String?
    var version: String?
    var hasHead = false
    /// The elements directly inside the body.
    var bodyElements: [String] = []
    var outlines: [Outline] = []

    init(contentsOf url: URL) throws {
        let delegate = Delegate()
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.delegate = delegate
        try #require(parser.parse(), "The exported file is not well-formed XML: \(String(describing: parser.parserError))")
        self = delegate.file
    }

    private init() {}

    private final class Delegate: NSObject, XMLParserDelegate {
        var file = ExportedFile()
        private var path: [String] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if path.isEmpty {
                file.rootElement = name
                file.version = attributes["version"]
            }
            if path == ["opml"], name == "head" { file.hasHead = true }
            if path == ["opml", "body"] { file.bodyElements.append(name) }
            if name == "outline" {
                file.outlines.append(Outline(attributes: attributes, depth: path.filter { $0 == "outline" }.count))
            }
            path.append(name)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            path.removeLast()
        }
    }
}

// MARK: - Test harness

/// What the file exporter of the subscription list offers while it is presented.
private struct SaveDialog {
    var defaultFilename: String?
    var allowedContentTypes: [UTType]
    var onCancellation: () -> Void
}

/// Exports one library; on iPhone and iPad the subscription list is shown over it.
@MainActor
private struct Exporter {
    let store: FeedStore
    let libraryURL: URL
    let folder: URL

    /// Steps 3 and 4: the Reader confirms `target`, and the subscriptions are written to it the way the platform
    /// writes them.
    func export(to target: URL) async throws {
        #if os(macOS)
        // The Export OPML… command hands the location its save panel returns to `SubscriptionExport.run(_:)`.
        let outcome = SubscriptionExport(store: store).run(target)
        guard case .exported = outcome else {
            Issue.record("The export ended with \(outcome) instead of writing the file")
            return
        }
        #else
        // The file exporter writes the bytes of the document the subscription list hands it, and reports the
        // location back to the subscription list.
        let document = SubscriptionExport(store: store).document
        try Data(document.text.utf8).write(to: target, options: .atomic)
        try await exportFinished(.success(target))
        #endif
    }

    #if os(iOS)
    let sidebar: SidebarView

    /// Step 1: the Reader chooses Export OPML… in the subscription list's toolbar menu.
    func chooseExport() async throws {
        try await sidebar.inspection.inspect { view in
            try exportEntry(in: view).tap()
        }
        try await settle()
    }

    /// Whether the Export OPML… entry of the toolbar menu is disabled.
    func isExportDisabled() async throws -> Bool {
        let box = ResultBox(false)
        try await sidebar.inspection.inspect { view in
            box.value = try exportEntry(in: view).isDisabled()
        }
        return box.value
    }

    private func exportEntry(in view: InspectableView<ViewType.View<SidebarView>>) throws -> InspectableView<ViewType.Button> {
        let buttons = try view.find(ViewType.Toolbar.self).findAll(ViewType.Button.self)
        return try #require(buttons.first { (try? $0.labelView().find(text: "Export OPML…")) != nil })
    }

    /// The file exporter the subscription list presents, or nil while none is presented.
    func saveDialog() async throws -> SaveDialog? {
        let box = ResultBox<SaveDialog?>(nil)
        try await sidebar.inspection.inspect { view in
            box.value = fileExport(in: try view.actualView().body)
        }
        return box.value
    }

    /// A2: the Reader cancels the save dialog.
    func cancelSaveDialog() async throws {
        let dialog = try #require(try await saveDialog(), "No file exporter is presented")
        dialog.onCancellation()
        try await settle()
    }

    /// Step 4 as the file exporter reports it to the subscription list: the file was written, or it was not.
    func exportFinished(_ result: Result<URL, Error>) async throws {
        try await sidebar.inspection.inspect { view in
            try view.actualView().exportFinished(result)
        }
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

    /// Lets SwiftUI apply the state changes of the last action.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
    #endif
}

#if os(iOS)
/// SwiftUI's file exporter is a `FileDialogConfiguration` modifier whose presentation storage holds a
/// `FileExportOperation` while the exporter is presented (iOS 27). ViewInspector does not know the modifier, so the
/// operation is searched in the view's body by reflection.
@MainActor
private func fileExport(in body: Any) -> SaveDialog? {
    func export(in value: Any, depth: Int) -> Any? {
        guard depth < 40 else { return nil }
        if String(describing: type(of: value)) == "FileExportOperation" { return value }
        for child in Mirror(reflecting: value).children {
            if let found = export(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
    func fields(of value: Any) -> [String: Any] {
        Dictionary(Mirror(reflecting: value).children.compactMap { child in child.label.map { ($0, child.value) } },
                   uniquingKeysWith: { first, _ in first })
    }
    guard let operation = export(in: body, depth: 0) else { return nil }
    // FileExportOperation.mode is an enum whose `export` case holds the settings.
    guard let mode = fields(of: operation)["mode"],
          let settings = Mirror(reflecting: mode).children.first?.value else {
        Issue.record("The file exporter's operation has an unexpected shape: \(fields(of: operation).keys.sorted())")
        return nil
    }
    let values = fields(of: settings)
    guard let types = values["_allowedContentTypes"] as? [UTType],
          let filename = values["defaultFilename"] as? String?,
          let cancellation = values["onCancellation"] as? () -> Void else {
        Issue.record("The file exporter's settings have an unexpected shape: \(values.keys.sorted())")
        return nil
    }
    // The completion is left alone: called outside a real presentation, SwiftUI's wrapper around it crashes.
    return SaveDialog(defaultFilename: filename, allowedContentTypes: types, onCancellation: cancellation)
}
#endif

private final class ResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// A fresh library in a temporary folder holding `feeds` and `articles`, saved to the library file. On iPhone and
/// iPad the subscription list is hosted over it.
@MainActor
private func withExporter(
    feeds: [Feed],
    articles: [[String: Any]] = [],
    _ body: @MainActor (Exporter) async throws -> Void
) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "UC007-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let libraryURL = folder.appending(path: "library.json")
    let library: [String: Any] = [
        "feeds": try JSONSerialization.jsonObject(with: JSONEncoder().encode(feeds)),
        "articles": articles,
    ]
    try JSONSerialization.data(withJSONObject: library).write(to: libraryURL)
    let store = FeedStore(fileURL: libraryURL)
    try #require(store.feeds.map(\.url) == feeds.map(\.url))
    try #require(store.articles.count == articles.count)

    // The subscription list loads favicons; the stub answers them, held for the whole test as every suite does.
    try await FeedPublisherStub.withAnswers([:]) {
        #if os(iOS)
        let sidebar = SidebarView(selection: .constant(.unread))
        let exporter = Exporter(store: store, libraryURL: libraryURL, folder: folder, sidebar: sidebar)
        try await ViewHosting.host(NavigationStack { sidebar }.environment(store)) {
            try await body(exporter)
        }
        #else
        try await body(Exporter(store: store, libraryURL: libraryURL, folder: folder))
        #endif
    }
}
