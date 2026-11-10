import Foundation

struct ParsedItem: Sendable {
    var guid: String?
    var title: String?
    var link: URL?
    var summary: String?
    var content: String?
    var author: String?
    var date: Date?
}

struct ParsedFeed: Sendable {
    var title: String?
    var siteURL: URL?
    var items: [ParsedItem] = []
}

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom feeds with Foundation's XMLParser.
final class FeedParser: NSObject, XMLParserDelegate {
    private static let mediaNamespace = "http://search.yahoo.com/mrss/"

    static func parse(_ data: Data, baseURL: URL) throws -> ParsedFeed {
        let delegate = FeedParser(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let succeeded = parser.parse()
        guard delegate.sawFeedRoot else { throw FeedError.notAFeed }
        // Tolerate malformed feeds as long as we got something useful before the error.
        if !succeeded && delegate.feed.items.isEmpty {
            throw FeedError.parse(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return delegate.feed
    }

    private let baseURL: URL
    private var feed = ParsedFeed()
    private var item: ParsedItem?
    private var stack: [String] = []
    private var text = ""
    private var sawFeedRoot = false

    // Atom `type="xhtml"` content arrives as nested XML elements; we re-serialize it.
    private var xhtmlRoot: String?
    private var xhtmlDepth = 0

    private init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        if xhtmlRoot != nil {
            xhtmlDepth += 1
            let attrs = attributes.map { " \($0.key)=\"\(HTMLText.escape($0.value))\"" }.joined()
            text += "<\(elementName)\(attrs)>"
            return
        }

        if stack.isEmpty, ["rss", "feed", "RDF"].contains(elementName) {
            sawFeedRoot = true
        }
        stack.append(elementName)
        text = ""

        switch elementName {
        case "item", "entry":
            item = ParsedItem()
        case "link":
            // Atom-style <link href="..." rel="alternate"/>
            guard let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate",
                  let url = resolve(href) else { break }
            if item != nil {
                if item?.link == nil { item?.link = url }
            } else if feed.siteURL == nil {
                feed.siteURL = url
            }
        case "content", "summary":
            if attributes["type"] == "xhtml", namespaceURI != Self.mediaNamespace {
                xhtmlRoot = elementName
                xhtmlDepth = 0
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if let root = xhtmlRoot {
            if xhtmlDepth > 0 {
                xhtmlDepth -= 1
                text += "</\(elementName)>"
                return
            }
            if elementName == root { xhtmlRoot = nil }
        }

        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        let grandparent = stack.count >= 3 ? stack[stack.count - 3] : ""
        defer {
            if !stack.isEmpty { stack.removeLast() }
            text = ""
        }

        if namespaceURI == Self.mediaNamespace { return }

        if elementName == "item" || elementName == "entry" {
            if let item { feed.items.append(item) }
            item = nil
            return
        }

        if item != nil {
            // Atom: <author><name>Jane</name></author>
            if elementName == "name", parent == "author", grandparent == "item" || grandparent == "entry" {
                if !value.isEmpty { item?.author = value }
                return
            }
            guard parent == "item" || parent == "entry", !value.isEmpty else { return }
            switch elementName {
            case "title": item?.title = value
            case "link": if item?.link == nil { item?.link = resolve(value) }
            case "guid", "id": item?.guid = value
            case "description", "summary": if item?.summary == nil { item?.summary = value }
            case "encoded", "content": item?.content = value
            case "creator", "author": if item?.author == nil { item?.author = value }
            case "published", "pubDate", "date", "issued": item?.date = DateParser.parse(value) ?? item?.date
            case "updated", "modified": if item?.date == nil { item?.date = DateParser.parse(value) }
            default: break
            }
        } else if parent == "channel" || parent == "feed", !value.isEmpty {
            switch elementName {
            case "title": if feed.title == nil { feed.title = value }
            case "link": if feed.siteURL == nil { feed.siteURL = resolve(value) }
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += xhtmlRoot != nil ? HTMLText.escape(string) : string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    private func resolve(_ string: String) -> URL? {
        URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL
    }
}

enum DateParser {
    nonisolated(unsafe) private static let isoFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [plain, fractional]
    }()

    /// RFC 822 variants (weekday is stripped before matching, since feeds often get it wrong).
    private static let formatters: [DateFormatter] = [
        "d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm zzz",
        "d MMM yyyy HH:mm Z",
        "d MMM yy HH:mm:ss zzz",
        "d MMM yy HH:mm:ss Z",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func parse(_ string: String) -> Date? {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in isoFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        if let comma = value.firstIndex(of: ","), value.distance(from: value.startIndex, to: comma) <= 10 {
            value = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        }
        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
