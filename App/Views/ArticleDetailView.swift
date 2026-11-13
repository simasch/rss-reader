import RSSReaderKit
import SwiftUI
import WebKit

struct ArticleDetailView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    let article: Article
    var previousArticleID: Article.ID?
    var nextArticleID: Article.ID?
    var select: (Article.ID) -> Void = { _ in }
    /// Called before the Reader toggles the read state by hand, so the article no longer stays in Unread
    /// as one opened by displaying it (UC-005 BR-004).
    var willToggleRead: (Article.ID) -> Void = { _ in }

    var body: some View {
        // UC-004 step 5: feed, author, publication date, title, and content.
        ArticleWebView(
            html: ArticleHTML.render(article, feedTitle: store.feed(withID: article.feedID)?.title),
            baseURL: article.link,
            open: { openURL($0) }
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        #endif
        .toolbar {
            ToolbarItemGroup {
                // UC-004 step 6: move to the previous or next article of the list.
                Button { previousArticleID.map(select) } label: {
                    Label("Previous Article", systemImage: "chevron.up")
                }
                .disabled(previousArticleID == nil)
                .help("Previous Article")

                Button { nextArticleID.map(select) } label: {
                    Label("Next Article", systemImage: "chevron.down")
                }
                .disabled(nextArticleID == nil)
                .help("Next Article")
            }
            ToolbarItemGroup {
                // UC-005 step 2: toggle the read state of the displayed article.
                Button {
                    willToggleRead(article.id)
                    store.toggleRead(article.id)
                } label: {
                    Label(article.isRead ? "Mark as Unread" : "Mark as Read",
                          systemImage: article.isRead ? "circle" : "largecircle.fill.circle")
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .help("Toggle Read (⇧⌘U)")

                // UC-005 A1: star or unstar the displayed article.
                Button { store.toggleStar(article.id) } label: {
                    Label(article.isStarred ? "Unstar" : "Star",
                          systemImage: article.isStarred ? "star.fill" : "star")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help("Toggle Star (⇧⌘L)")

                // UC-004 BR-007: open, share, and copy only with a link; share and copy everywhere.
                if let link = article.link {
                    // UC-004 A5: share the displayed article's link or copy it to the clipboard.
                    ShareLink(item: link)
                    Button { Platform.copyToPasteboard(link.absoluteString) } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    .help("Copy Link")

                    // UC-004 A3: open the displayed article's web page in the default browser.
                    Button { openURL(link) } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .keyboardShortcut("b")
                    .help("Open in Browser (⌘B)")
                }
            }
        }
    }
}

#if os(macOS)
private typealias ViewRepresentable = NSViewRepresentable
#else
private typealias ViewRepresentable = UIViewRepresentable
#endif

/// Renders article HTML with JavaScript disabled; clicked links go to `open`, the default browser.
struct ArticleWebView: ViewRepresentable {
    let html: String
    let baseURL: URL?
    var open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(open: open) }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // UC-004 BR-005: the content's scripts do not run.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        context.coordinator.open = open
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var open: (URL) -> Void

        init(open: @escaping (URL) -> Void) {
            self.open = open
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            policy(for: navigationAction.navigationType, url: navigationAction.request.url)
        }

        // UC-004 BR-005: links in the content open in the default browser, not in the app (A3).
        func policy(for navigationType: WKNavigationType, url: URL?) -> WKNavigationActionPolicy {
            guard navigationType == .linkActivated, let url else { return .allow }
            open(url)
            return .cancel
        }
    }
}

enum ArticleHTML {
    static func render(_ article: Article, feedTitle: String?) -> String {
        let e = HTMLText.escape
        var meta: [String] = []
        if let feedTitle { meta.append(e(feedTitle)) }
        if let author = article.author { meta.append(e(author)) }
        if let date = article.published { meta.append(e(date.formatted(date: .long, time: .shortened))) }
        let title = article.link.map { "<a href=\"\(e($0.absoluteString))\">\(e(article.title))</a>" }
            ?? e(article.title)

        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="script-src 'none'">
        <style>\(css)</style>
        </head><body>
        <header><div class="meta">\(meta.joined(separator: " · "))</div><h1>\(title)</h1></header>
        <article>\(article.contentHTML)</article>
        </body></html>
        """
    }

    #if os(macOS)
    private static let fontSize = "15px"
    #else
    private static let fontSize = "17px"
    #endif

    private static let css = """
    :root { color-scheme: light dark; }
    body { font-family: -apple-system, sans-serif; font-size: \(fontSize); line-height: 1.6;
           max-width: 46em; margin: 2em auto; padding: 0 1.25em; -webkit-text-size-adjust: 100%;
           overflow-wrap: break-word; }
    h1 { font-size: 1.7em; line-height: 1.25; margin: .2em 0 1em; }
    h1 a { color: inherit; text-decoration: none; }
    .meta { color: gray; font-size: .9em; }
    img, video, iframe { max-width: 100%; height: auto; }
    pre { overflow-x: auto; padding: .8em; background: rgba(128,128,128,.12); border-radius: 6px; }
    code { font-family: ui-monospace, Menlo, monospace; font-size: .9em; }
    blockquote { border-left: 3px solid rgba(128,128,128,.4); margin-left: 0; padding-left: 1em; color: gray; }
    """
}
