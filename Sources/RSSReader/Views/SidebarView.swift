import SwiftUI

struct SidebarView: View {
    @Environment(FeedStore.self) private var store
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
        .toolbar {
            ToolbarItem {
                Button { store.isAddingFeed = true } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add Feed (⌘N)")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for feed: Feed) -> some View {
        if let site = feed.siteURL {
            Button("Open Website") { NSWorkspace.shared.open(site) }
        }
        Button("Copy Feed URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(feed.url.absoluteString, forType: .string)
        }
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
