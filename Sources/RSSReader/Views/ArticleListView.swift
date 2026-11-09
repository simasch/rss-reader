import SwiftUI

struct ArticleListView: View {
    @Environment(FeedStore.self) private var store
    let sidebarSelection: SidebarItem?
    @Binding var selectedArticleID: Article.ID?

    var body: some View {
        // Keep the selected article visible in "Unread" even after it has been marked read.
        let articles = store.articles(in: sidebarSelection, keeping: selectedArticleID)
        Group {
            if store.feeds.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    Text("Add a feed or website URL to get started.")
                } actions: {
                    Button("Add Feed…") { store.isAddingFeed = true }
                }
            } else if articles.isEmpty {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "checkmark.circle",
                    description: Text(sidebarSelection == .unread ? "You're all caught up." : "Nothing here yet.")
                )
            } else {
                List(articles, selection: $selectedArticleID) { article in
                    ArticleRow(article: article, feedTitle: store.feed(withID: article.feedID)?.title)
                        .contextMenu { contextMenu(for: article) }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Button { store.markAllRead(in: sidebarSelection) } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("k")
                .help("Mark All as Read (⌘K)")

                Button { Task { await store.refreshAll() } } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing)
                .help("Refresh All (⌘R)")
            }
        }
    }

    private var title: String {
        switch sidebarSelection {
        case .unread: "Unread"
        case .starred: "Starred"
        case .all, nil: "All Articles"
        case .feed(let id): store.feed(withID: id)?.title ?? "Feed"
        }
    }

    @ViewBuilder
    private func contextMenu(for article: Article) -> some View {
        Button(article.isRead ? "Mark as Unread" : "Mark as Read") { store.toggleRead(article.id) }
        Button(article.isStarred ? "Unstar" : "Star") { store.toggleStar(article.id) }
        if let link = article.link {
            Divider()
            Button("Open in Browser") { NSWorkspace.shared.open(link) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
            }
        }
    }
}

private struct ArticleRow: View {
    let article: Article
    let feedTitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(article.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(feedTitle ?? "")
                        .lineLimit(1)
                    Spacer()
                    if article.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    Text(article.sortDate, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .lineLimit(2)

                if !article.snippet.isEmpty {
                    Text(article.snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
