import RSSReaderKit
import SwiftUI

struct SidebarView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var selection: SidebarItem?
    /// Called before a feed is removed, so the article view can let go of the feed's articles.
    var willUnsubscribe: (UUID) -> Void = { _ in }
    @State private var unsubscribeError: String?
    internal let inspection = Inspection<Self>() // UI test hook (ViewInspector)

    var body: some View {
        let counts = store.unreadCountsByFeed()
        // UC-004 step 1: the smart lists and the subscribed feeds with their unread counts.
        List(selection: $selection) {
            Section("Smart Feeds") {
                // UC-004 BR-006: Unread shows the total of the feeds' unread counts.
                Label("Unread", systemImage: "largecircle.fill.circle")
                    .badge(counts.values.reduce(0, +))
                    .tag(SidebarItem.unread)
                Label("All Articles", systemImage: "tray.full")
                    .tag(SidebarItem.all)
                Label("Starred", systemImage: "star")
                    .tag(SidebarItem.starred)
            }
            Section("Feeds") {
                ForEach(store.feeds) { feed in
                    // UC-004 BR-006: each feed shows its number of unread articles.
                    FeedRow(feed: feed)
                        .badge(counts[feed.id] ?? 0)
                        .tag(SidebarItem.feed(feed.id))
                        .contextMenu { contextMenu(for: feed) }
                }
            }
        }
        .listStyle(.sidebar)
        #if os(iOS)
        .navigationTitle("RSS Reader")
        #endif
        .toolbar {
            ToolbarItem {
                Button { store.isAddingFeed = true } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add Feed (⌘N)")
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { isImporting = true } label: {
                        Label("Import OPML…", systemImage: "square.and.arrow.down")
                    }
                    Button { isExporting = true } label: {
                        Label("Export OPML…", systemImage: "square.and.arrow.up")
                    }
                    // UC-007 precondition: the library holds at least one feed.
                    .disabled(!SubscriptionExport(store: store).canExport)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            #endif
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
        .alert("Unsubscribe Failed", isPresented: Binding { unsubscribeError != nil } set: {
            if !$0 { unsubscribeError = nil }
        }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unsubscribeError ?? "")
        }
        #if os(iOS)
        // UC-003 BR-001: the Reader refreshes by pulling down the list.
        .refreshable { await store.refreshAll() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Platform.opmlType, .xml]) { result in
            importSubscriptions(result)
        }
        // UC-007 step 2: asks where to save the file, proposing "Subscriptions.opml".
        .fileExporter(
            isPresented: $isExporting,
            document: SubscriptionExport(store: store).document,
            contentType: Platform.opmlType,
            defaultFilename: "Subscriptions.opml"
        ) { result in
            exportFinished(result)
        }
        .alert("OPML Error", isPresented: Binding { opmlError != nil } set: { if !$0 { opmlError = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(opmlError ?? "")
        }
        #endif
    }

    #if os(iOS)
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var opmlError: String?

    /// UC-006 steps 3 to 7: imports the file the Reader selected; `nil` means the selection was cancelled.
    /// A1, A4: a failed import's message is displayed in the OPML Error alert.
    @discardableResult
    func importSubscriptions(_ selection: Result<URL, Error>?) -> SubscriptionImport.Outcome {
        let outcome = SubscriptionImport(store: store).run(selection)
        if let message = outcome.message { opmlError = message }
        return outcome
    }

    /// UC-007 step 4: the file exporter wrote the file, or could not.
    /// A1: a failed export displays its message in the OPML Error alert. A2: a cancelled one displays nothing.
    @discardableResult
    func exportFinished(_ result: Result<URL, Error>) -> SubscriptionExport.Outcome {
        let outcome = SubscriptionExport(store: store).finish(result)
        if let message = outcome.message { opmlError = message }
        return outcome
    }
    #endif

    @ViewBuilder
    private func contextMenu(for feed: Feed) -> some View {
        if let site = feed.siteURL {
            Button("Open Website") { openURL(site) }
        }
        Button("Copy Feed URL") { Platform.copyToPasteboard(feed.url.absoluteString) }
        Divider()
        // UC-002 BR-001: unsubscribing is not confirmed beforehand.
        Button("Unsubscribe", role: .destructive) { unsubscribe(feed) }
    }

    private func unsubscribe(_ feed: Feed) {
        // UC-002 A1: the removed feed's list gives way to Unread.
        if selection == .feed(feed.id) { selection = .unread }
        willUnsubscribe(feed.id)
        do {
            try store.removeFeed(id: feed.id)
        } catch {
            // UC-002 BR-002: the feed stays subscribed; the display keeps its new state.
            unsubscribeError = error.localizedDescription
        }
    }
}

private struct FeedRow: View {
    let feed: Feed

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(feed.title).lineLimit(1)
                    // UC-003 A2: the problem of the latest refresh is shown with the feed.
                    if let error = feed.lastError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(error)
                            .accessibilityLabel(error)
                    }
                }
                #if os(iOS)
                // iPhone and iPad show no tooltip, so the problem is written under the title.
                if let error = feed.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                #endif
            }
        } icon: {
            AsyncImage(url: faviconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                }
            }
            .frame(width: 16, height: 16)
        }
    }

    private var faviconURL: URL? {
        let site = feed.siteURL ?? feed.url
        guard let host = site.host() else { return nil }
        return URL(string: "\(site.scheme ?? "https")://\(host)/favicon.ico")
    }
}
