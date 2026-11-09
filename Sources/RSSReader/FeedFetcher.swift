import Foundation

enum FetchResult: Sendable {
    case notModified
    case updated(ParsedFeed, etag: String?, lastModified: String?)
}

enum FeedFetcher {
    static let userAgent = "RSSReader/0.1 (Macintosh; macOS)"

    /// Fetches a feed using conditional GET so unchanged feeds cost a 304 instead of a full download.
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
    static func discover(_ url: URL) async throws -> (url: URL, feed: ParsedFeed) {
        let (data, response) = try await get(url)
        let base = response.url ?? url
        if let parsed = try? FeedParser.parse(data, baseURL: base) {
            return (base, parsed)
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
            let lower = tag.lowercased()
            guard lower.contains("alternate"),
                  lower.contains("application/rss+xml") || lower.contains("application/atom+xml"),
                  let href = attribute("href", in: tag) else { return nil }
            return URL(string: href, relativeTo: baseURL)?.absoluteURL
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(name)\\s*=\\s*([\"'])(.*?)\\1", options: .caseInsensitive
        ),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
            let r = Range(match.range(at: 2), in: tag) else { return nil }
        return String(tag[r]).replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func get(
        _ url: URL, etag: String? = nil, lastModified: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
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
