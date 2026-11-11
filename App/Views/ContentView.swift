import RSSReaderKit
import SwiftUI

struct ContentView: View {
    @Environment(FeedStore.self) private var store
    @State private var sidebarSelection: SidebarItem? = .unread
    @State private var selectedArticleID: Article.ID?
    /// Articles opened since the current list was shown; they stay in "Unread" until the list changes.
    @State private var keptArticleIDs: Set<Article.ID> = []

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ArticleListView(
                sidebarSelection: sidebarSelection,
                selectedArticleID: $selectedArticleID,
                keptArticleIDs: keptArticleIDs
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let id = selectedArticleID, let article = store.article(withID: id) {
                ArticleDetailView(article: article)
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "doc.richtext")
            }
        }
        .onChange(of: sidebarSelection) {
            selectedArticleID = nil
            keptArticleIDs = []
        }
        .onChange(of: selectedArticleID) { _, id in
            guard let id else { return }
            keptArticleIDs.insert(id)
            store.setRead(true, articleID: id)
        }
        .sheet(isPresented: $store.isAddingFeed) {
            AddFeedSheet()
        }
    }
}
