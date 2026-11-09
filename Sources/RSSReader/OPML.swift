import Foundation

/// OPML import/export. Folders are flattened on import.
enum OPML {
    struct Entry: Sendable {
        var title: String
        var url: URL
        var siteURL: URL?
    }

    static func parse(_ data: Data) throws -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? FeedError.parse("Invalid OPML")
        }
        return delegate.entries
    }

    static func export(_ feeds: [Feed]) -> String {
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

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            guard elementName.lowercased() == "outline",
                  let raw = attributes["xmlUrl"] ?? attributes["xmlurl"],
                  let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else { return }
            let title = attributes["title"] ?? attributes["text"] ?? url.host() ?? raw
            entries.append(Entry(title: title, url: url, siteURL: attributes["htmlUrl"].flatMap(URL.init(string:))))
        }
    }
}
