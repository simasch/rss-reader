import Foundation

enum FetchResult: Sendable {
    case notModified
    case updated(ParsedFeed, etag: String?, lastModified: String?)
}

enum FeedFetcher {
    #if os(macOS)
    static let userAgent = "RSSReader/0.1 (Macintosh; macOS)"
    #else
    static let userAgent = "RSSReader/0.1 (iPhone; iOS)"
    #endif

    /// Fetches a feed using conditional GET so unchanged feeds cost a 304 instead of a full download.
    // UC-003 BR-009: the stored version is sent along, so an unchanged feed is not downloaded again.
    static func fetch(_ url: URL, etag: String? = nil, lastModified: String? = nil) async throws -> FetchResult {
        let (data, response) = try await get(url, etag: etag, lastModified: lastModified)
        if response.statusCode == 304 { return .notModified }
        let parsed = try FeedParser.parse(data, baseURL: response.url ?? url)
        return .updated(
            parsed,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    /// Accepts a feed URL or a website URL. For websites, follows `<link rel="alternate">` to the feed.
    // UC-001 BR-003: one discovery step; an advertised address that is no feed is not searched further.
    static func discover(_ url: URL) async throws -> (url: URL, feed: ParsedFeed) {
        let (data, response) = try await get(url)
        let base = response.url ?? url
        // Only a document that is no feed at all is searched for advertised feeds (A3); a damaged feed
        // reports its own problem (A5).
        do {
            return (base, try FeedParser.parse(data, baseURL: base))
        } catch FeedError.notAFeed {
            // A web page: continue with discovery below.
        }
        let html = String(decoding: data, as: UTF8.self)
        guard let feedURL = feedLinks(inHTML: html, baseURL: base).first else {
            throw FeedError.noFeedFound
        }
        let (feedData, feedResponse) = try await get(feedURL)
        let finalURL = feedResponse.url ?? feedURL
        return (finalURL, try FeedParser.parse(feedData, baseURL: finalURL))
    }

    static func feedLinks(inHTML html: String, baseURL: URL) -> [URL] {
        guard let linkTag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return linkTag.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range, in: html) else { return nil }
            let tag = String(html[r])
            // UC-001 BR-003: only links advertised as an alternate RSS or Atom version count.
            let rels = (attribute("rel", in: tag) ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            let type = (attribute("type", in: tag) ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            guard rels.contains("alternate"),
                  ["application/rss+xml", "application/atom+xml"].contains(type),
                  let href = attribute("href", in: tag) else { return nil }
            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        // Quoted or unquoted value; the name must stand alone (`rel`, not `data-rel`).
        guard let regex = try? NSRegularExpression(
            pattern: "\\s\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", options: .caseInsensitive
        ),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
            let r = (1...3).lazy.compactMap({ Range(match.range(at: $0), in: tag) }).first else { return nil }
        return String(tag[r]).replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func get(
        _ url: URL, etag: String? = nil, lastModified: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        // UC-001 BR-007, UC-003 BR-010: a Feed Publisher silent for 30 seconds counts as unreachable.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.badResponse }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            throw FeedError.http(http.statusCode)
        }
        return (data, http)
    }
}
