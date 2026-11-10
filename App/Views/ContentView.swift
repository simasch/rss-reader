import RSSReaderKit
import SwiftUI

struct ContentView: View {
    @Environment(FeedStore.self) private var store
    @State private var sidebarSelection: SidebarItem? = .unread
    @State private var selectedArticleID: Article.ID?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ArticleListView(sidebarSelection: sidebarSelection, selectedArticleID: $selectedArticleID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let id = selectedArticleID, let article = store.article(withID: id) {
                ArticleDetailView(article: article)
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "doc.richtext")
            }
        }
        .onChange(of: sidebarSelection) { selectedArticleID = nil }
        .onChange(of: selectedArticleID) { _, id in
            if let id { store.setRead(true, articleID: id) }
        }
        .sheet(isPresented: $store.isAddingFeed) {
            AddFeedSheet()
        }
    }
}
