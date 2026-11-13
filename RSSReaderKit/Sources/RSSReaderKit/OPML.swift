import Foundation

/// OPML import/export. Folders are flattened on import.
public enum OPML {
    /// A feed entry of an OPML file, with its title and addresses as they will be imported.
    struct Entry: Sendable {
        var title: String
        var url: URL
        var siteURL: URL?
    }

    // UC-006 BR-001: an OPML subscription list; every outline with a feed address, in any folder.
    static func parse(_ data: Data) throws -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.isOPML else {
            throw FeedError.notOPML
        }
        return delegate.entries
    }

    // UC-006 BR-003: title, else text, else host; plain text of at most 200 characters.
    static func importedTitle(title: String?, text: String?, feedURL: URL) -> String {
        let candidates = [title, text].compactMap { $0 }.map { HTMLText.plainText($0, limit: 200) }
        return candidates.first { !$0.isEmpty } ?? feedURL.host() ?? feedURL.absoluteString
    }

    /// The OPML text of a subscription list, with the feeds in the order given.
    // UC-007 BR-001: OPML 2.0 without folders; title as text and title, feed address, website.
    // UC-007 BR-002: entries in the order of `feeds`, which is the subscription order.
    public static func export(_ feeds: [Feed]) -> String {
        let e = HTMLText.escape
        let outlines = feeds.map { feed in
            var line = "    <outline type=\"rss\" text=\"\(e(feed.title))\" title=\"\(e(feed.title))\" xmlUrl=\"\(e(feed.url.absoluteString))\""
            if let site = feed.siteURL { line += " htmlUrl=\"\(e(site.absoluteString))\"" }
            return line + "/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>RSS Reader Subscriptions</title></head>
          <body>
        \(outlines)
          </body>
        </opml>

        """
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        var isOPML = false
        private var isRoot = true

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            if isRoot {
                isRoot = false
                isOPML = elementName.lowercased() == "opml"
            }
            // Folders are outlines without a feed address; their children are read like any other.
            guard elementName.lowercased() == "outline",
                  let raw = attributes["xmlUrl"] ?? attributes["xmlurl"],
                  // UC-006 BR-005: addresses follow the subscribe rules; an invalid one skips its entry.
                  let url = try? FeedStore.normalizedAddress(raw) else { return }
            let site = (attributes["htmlUrl"] ?? attributes["htmlurl"]).flatMap { try? FeedStore.normalizedAddress($0) }
            entries.append(Entry(
                title: OPML.importedTitle(title: attributes["title"], text: attributes["text"], feedURL: url),
                url: url,
                siteURL: site
            ))
        }
    }
}
