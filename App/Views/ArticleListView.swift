import RSSReaderKit
import SwiftUI

struct ArticleListView: View {
    @Environment(FeedStore.self) private var store
    let sidebarSelection: SidebarItem?
    @Binding var selectedArticleID: Article.ID?
    @Binding var keptArticleIDs: Set<Article.ID>

    var body: some View {
        // Keep articles read in this visit visible in "Unread", so ↑/↓ can go back to them.
        let articles = store.articles(in: sidebarSelection, keeping: keptArticleIDs)
        Group {
            if store.feeds.isEmpty {
                // UC-004 A1: an empty library offers to add a feed (UC-001).
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    Text("Add a feed or website URL to get started.")
                } actions: {
                    Button("Add Feed…") { store.isAddingFeed = true }
                }
            } else if articles.isEmpty {
                // UC-004 A2: an empty list says so, worded for Unread or any other list.
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "checkmark.circle",
                    description: Text(sidebarSelection == .unread ? "You're all caught up." : "Nothing here yet.")
                )
            } else {
                // UC-004 step 3: feed, date, title, snippet, read state, and star of each article.
                List(articles, selection: $selectedArticleID) { article in
                    ArticleRow(article: article, feedTitle: store.feed(withID: article.feedID)?.title)
                        .contextMenu { contextMenu(for: article) }
                        #if os(iOS)
                        .swipeActions(edge: .leading) {
                            Button { toggleRead(article) } label: {
                                Label(article.isRead ? "Unread" : "Read",
                                      systemImage: article.isRead ? "circle" : "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            // UC-005 A1: star or unstar an article of the list.
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
                // UC-005 A2: mark every unread article of the displayed list as read.
                Button {
                    store.markAllRead(in: sidebarSelection)
                    // UC-005 BR-004: Mark all as read empties Unread, opened articles included (also A3).
                    if sidebarSelection == .unread { keptArticleIDs = [] }
                } label: {
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

    /// UC-005 step 2: toggles the read state of an article of the list.
    private func toggleRead(_ article: Article) {
        // UC-005 BR-004: an article marked by hand no longer stays in Unread as a displayed one.
        keptArticleIDs.remove(article.id)
        store.toggleRead(article.id)
    }

    private func moveSelection(by offset: Int, in articles: [Article]) -> KeyPress.Result {
        guard !articles.isEmpty else { return .ignored }
        if let id = selectedArticleID, !articles.contains(where: { $0.id == id }) {
            // UC-005 BR-006: a displayed article that left the list steps to its former neighbours.
            if let next = store.neighbour(of: id, offset: offset, in: sidebarSelection, keeping: keptArticleIDs) {
                selectedArticleID = next
            }
            return .handled
        }
        let current = selectedArticleID.flatMap { id in articles.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), articles.count - 1) } ?? (offset > 0 ? 0 : articles.count - 1)
        selectedArticleID = articles[next].id
        return .handled
    }

    @ViewBuilder
    private func contextMenu(for article: Article) -> some View {
        // UC-005 step 1: the Reader chooses an article in the list.
        Button(article.isRead ? "Mark as Unread" : "Mark as Read") { toggleRead(article) }
        // UC-005 A1: star or unstar an article of the list.
        Button(article.isStarred ? "Unstar" : "Star") { store.toggleStar(article.id) }
        // UC-004 BR-007: sharing and copying the link only with a link, on every platform.
        if let link = article.link {
            Divider()
            // UC-004 A4: share an article of the list or copy its link.
            ShareLink(item: link)
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
