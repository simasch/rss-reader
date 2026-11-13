import RSSReaderKit
import SwiftUI

struct ContentView: View {
    @Environment(FeedStore.self) private var store
    // UC-004 step 1: the app opens with Unread selected.
    @State private var sidebarSelection: SidebarItem? = .unread
    @State private var selectedArticleID: Article.ID?
    /// Articles opened since the current list was shown; they stay in "Unread" until the list changes.
    @State private var keptArticleIDs: Set<Article.ID> = []
    internal let inspection = Inspection<Self>() // UI test hook (ViewInspector)

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, willUnsubscribe: releaseArticles(ofFeed:))
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ArticleListView(
                sidebarSelection: sidebarSelection,
                selectedArticleID: $selectedArticleID,
                keptArticleIDs: $keptArticleIDs
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let id = selectedArticleID, let article = store.article(withID: id) {
                // UC-004 step 6: the displayed article steps to its neighbours in the list.
                ArticleDetailView(
                    article: article,
                    previousArticleID: neighbour(of: id, offset: -1),
                    nextArticleID: neighbour(of: id, offset: 1),
                    select: { selectedArticleID = $0 },
                    // UC-005 BR-004: an article marked by hand leaves Unread at once when marked read.
                    willToggleRead: { keptArticleIDs.remove($0) }
                )
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "doc.richtext")
            }
        }
        // UC-004 A6: another list clears the selection and forgets the articles read in the visit.
        .onChange(of: sidebarSelection) {
            selectedArticleID = nil
            keptArticleIDs = []
        }
        // UC-004 BR-003: displaying an article marks it as read.
        // UC-005 BR-005: one marked unread while displayed stays unread until displayed anew.
        .onChange(of: selectedArticleID) { _, id in
            guard let id else { return }
            // UC-004 BR-004: the article stays in Unread until another list is selected.
            keptArticleIDs.insert(id)
            store.setRead(true, articleID: id)
        }
        .sheet(isPresented: $store.isAddingFeed) {
            AddFeedSheet()
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    /// The article `offset` places before or after the given one in the displayed list, if any.
    // UC-005 BR-006: also for a displayed article that has left the list.
    private func neighbour(of id: Article.ID, offset: Int) -> Article.ID? {
        store.neighbour(of: id, offset: offset, in: sidebarSelection, keeping: keptArticleIDs)
    }

    /// UC-002 A2: drops the feed's articles from the selection and from the read articles kept in
    /// Unread, so they stay gone even when the unsubscribe fails and the feed comes back (BR-002).
    private func releaseArticles(ofFeed feedID: UUID) {
        if let id = selectedArticleID, store.article(withID: id)?.feedID == feedID {
            selectedArticleID = nil
        }
        keptArticleIDs = keptArticleIDs.filter { store.article(withID: $0)?.feedID != feedID }
    }
}
