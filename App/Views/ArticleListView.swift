import RSSReaderKit
import SwiftUI

struct ArticleListView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    let sidebarSelection: SidebarItem?
    @Binding var selectedArticleID: Article.ID?
    let keptArticleIDs: Set<Article.ID>

    var body: some View {
        // Keep articles read in this visit visible in "Unread", so ↑/↓ can go back to them.
        let articles = store.articles(in: sidebarSelection, keeping: keptArticleIDs)
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
                        #if os(iOS)
                        .swipeActions(edge: .leading) {
                            Button { store.toggleRead(article.id) } label: {
                                Label(article.isRead ? "Unread" : "Read",
                                      systemImage: article.isRead ? "circle" : "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleStar(article.id) } label: {
                                Label(article.isStarred ? "Unstar" : "Star",
                                      systemImage: article.isStarred ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        #endif
                }
                #if os(iOS)
                .listStyle(.plain)
                // UC-003 BR-001: the Reader refreshes by pulling down the list.
                .refreshable { await store.refreshAll() }
                // macOS lists move the selection with the arrow keys natively; on iPadOS they only
                // move the focus highlight, so step through the articles explicitly.
                .onKeyPress(.downArrow) { moveSelection(by: 1, in: articles) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, in: articles) }
                #endif
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

                // UC-003 BR-001: the Reader refreshes from the toolbar at any time.
                Button { Task { await store.refreshAll() } } label: {
                    // UC-003 step 2: the toolbar shows that a refresh is running.
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                // UC-003 BR-002: the refresh action is disabled while a refresh is running.
                .disabled(store.isRefreshing)
                .help(Self.refreshHelp)
            }
        }
    }

    // UC-003 BR-001: the keyboard shortcut ⌘R exists on the Mac only, so only the Mac names it.
    #if os(macOS)
    static let refreshHelp = "Refresh All (⌘R)"
    #else
    static let refreshHelp = "Refresh All"
    #endif

    private var title: String {
        switch sidebarSelection {
        case .unread: "Unread"
        case .starred: "Starred"
        case .all, nil: "All Articles"
        case .feed(let id): store.feed(withID: id)?.title ?? "Feed"
        }
    }

    private func moveSelection(by offset: Int, in articles: [Article]) -> KeyPress.Result {
        guard !articles.isEmpty else { return .ignored }
        let current = selectedArticleID.flatMap { id in articles.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), articles.count - 1) } ?? (offset > 0 ? 0 : articles.count - 1)
        selectedArticleID = articles[next].id
        return .handled
    }

    @ViewBuilder
    private func contextMenu(for article: Article) -> some View {
        Button(article.isRead ? "Mark as Unread" : "Mark as Read") { store.toggleRead(article.id) }
        Button(article.isStarred ? "Unstar" : "Star") { store.toggleStar(article.id) }
        if let link = article.link {
            Divider()
            Button("Open in Browser") { openURL(link) }
            Button("Copy Link") { Platform.copyToPasteboard(link.absoluteString) }
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
