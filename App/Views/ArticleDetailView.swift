import RSSReaderKit
import SwiftUI
import WebKit

struct ArticleDetailView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    let article: Article

    var body: some View {
        ArticleWebView(
            html: ArticleHTML.render(article, feedTitle: store.feed(withID: article.feedID)?.title),
            baseURL: article.link
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button { store.toggleRead(article.id) } label: {
                    Label(article.isRead ? "Mark as Unread" : "Mark as Read",
                          systemImage: article.isRead ? "circle" : "largecircle.fill.circle")
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .help("Toggle Read (⇧⌘U)")

                Button { store.toggleStar(article.id) } label: {
                    Label(article.isStarred ? "Unstar" : "Star",
                          systemImage: article.isStarred ? "star.fill" : "star")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help("Toggle Star (⇧⌘L)")

                if let link = article.link {
                    #if os(iOS)
                    ShareLink(item: link)
                    #endif
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

/// Renders article HTML with JavaScript disabled; clicked links open in the default browser.
struct ArticleWebView: ViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
                return .cancel
            }
            return .allow
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
