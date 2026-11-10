import RSSReaderKit
import SwiftUI

struct SidebarView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var selection: SidebarItem?

    var body: some View {
        let counts = store.unreadCountsByFeed()
        List(selection: $selection) {
            Section("Smart Feeds") {
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
                    .disabled(store.feeds.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            #endif
        }
        #if os(iOS)
        .refreshable { await store.refreshAll() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Platform.opmlType, .xml]) { result in
            do {
                if try store.importOPML(from: result.get()) > 0 {
                    Task { await store.refreshAll() }
                }
            } catch {
                opmlError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: OPMLDocument(text: OPML.export(store.feeds)),
            contentType: Platform.opmlType,
            defaultFilename: "Subscriptions.opml"
        ) { result in
            if case .failure(let error) = result { opmlError = error.localizedDescription }
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
    #endif

    @ViewBuilder
    private func contextMenu(for feed: Feed) -> some View {
        if let site = feed.siteURL {
            Button("Open Website") { openURL(site) }
        }
        Button("Copy Feed URL") { Platform.copyToPasteboard(feed.url.absoluteString) }
        Divider()
        Button("Unsubscribe", role: .destructive) {
            if selection == .feed(feed.id) { selection = .unread }
            store.removeFeed(id: feed.id)
        }
    }
}

private struct FeedRow: View {
    let feed: Feed

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(feed.title).lineLimit(1)
                if let error = feed.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(error)
                }
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

#if os(iOS)
import UniformTypeIdentifiers

/// Wraps exported OPML text for SwiftUI's file exporter.
private struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [Platform.opmlType] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
#endif
