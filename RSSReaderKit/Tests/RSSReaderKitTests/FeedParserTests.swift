import Foundation
import Testing
@testable import RSSReaderKit

private let base = URL(string: "https://example.com/feed.xml")!

@Suite struct FeedParserTests {
    @Test func parsesRSS2() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom"
             xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <title>Example Blog</title>
            <link>https://example.com/</link>
            <atom:link href="https://example.com/feed.xml" rel="self"/>
            <image><title>Logo title must be ignored</title></image>
            <item>
              <title>Hello &amp; welcome</title>
              <link>/posts/hello</link>
              <guid isPermaLink="false">post-1</guid>
              <pubDate>Tue, 03 Nov 2026 10:15:00 GMT</pubDate>
              <dc:creator>Jane</dc:creator>
              <description><![CDATA[<p>Short summary</p>]]></description>
              <content:encoded><![CDATA[<p>Full <b>content</b></p>]]></content:encoded>
              <media:title>Media title must be ignored</media:title>
            </item>
            <item>
              <title>Second</title>
              <link>https://example.com/posts/second</link>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedParser.parse(Data(xml.utf8), baseURL: base)
        #expect(feed.title == "Example Blog")
        #expect(feed.siteURL == URL(string: "https://example.com/"))
        #expect(feed.items.count == 2)

        let first = feed.items[0]
        #expect(first.title == "Hello & welcome")
        #expect(first.link == URL(string: "https://example.com/posts/hello"))
        #expect(first.guid == "post-1")
        #expect(first.author == "Jane")
        #expect(first.summary == "<p>Short summary</p>")
        #expect(first.content == "<p>Full <b>content</b></p>")
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-11-03T10:15:00Z"))
        #expect(feed.items[1].guid == nil)
    }

    @Test func parsesAtomWithXHTMLContent() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Example</title>
          <link href="https://example.org/"/>
          <link rel="self" href="https://example.org/atom.xml"/>
          <entry>
            <title>Atom entry</title>
            <link rel="alternate" href="https://example.org/2026/entry"/>
            <link rel="enclosure" href="https://example.org/audio.mp3"/>
            <id>urn:uuid:1225c695</id>
            <updated>2026-11-01T12:00:00Z</updated>
            <published>2026-10-31T08:30:00.123Z</published>
            <author><name>John</name></author>
            <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Hi <em>there</em> &amp; you</p></div></content>
          </entry>
        </feed>
        """
        let feed = try FeedParser.parse(Data(xml.utf8), baseURL: base)
        #expect(feed.title == "Atom Example")
        #expect(feed.siteURL == URL(string: "https://example.org/"))

        let entry = try #require(feed.items.first)
        #expect(entry.title == "Atom entry")
        #expect(entry.link == URL(string: "https://example.org/2026/entry"))
        #expect(entry.guid == "urn:uuid:1225c695")
        #expect(entry.author == "John")
        #expect(entry.content == "<div><p>Hi <em>there</em> &amp; you</p></div>")
        // <published> wins over <updated>
        let expected = try #require(DateParser.parse("2026-10-31T08:30:00.123Z"))
        #expect(entry.date == expected)
    }

    @Test func rejectsNonFeedDocuments() {
        #expect(throws: FeedError.self) {
            try FeedParser.parse(Data("<html><body>Hi</body></html>".utf8), baseURL: base)
        }
    }
}

@Suite struct DateParserTests {
    @Test(arguments: [
        "Tue, 03 Nov 2026 10:15:00 GMT",
        "Tue, 3 Nov 2026 10:15:00 +0000",
        "Wed, 03 Nov 2026 10:15:00 GMT", // wrong weekday is tolerated
        "03 Nov 2026 11:15:00 +0100",
        "2026-11-03T10:15:00Z",
        "2026-11-03T11:15:00+01:00",
    ])
    func parsesCommonFormats(_ input: String) {
        #expect(DateParser.parse(input) == ISO8601DateFormatter().date(from: "2026-11-03T10:15:00Z"))
    }

    @Test func returnsNilForGarbage() {
        #expect(DateParser.parse("yesterday-ish") == nil)
    }
}

@Suite struct DiscoveryAndTextTests {
    @Test func findsFeedLinksInHTML() {
        let html = """
        <html><head>
          <link rel="stylesheet" href="/style.css">
          <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml?a=1&amp;b=2">
          <link href='https://example.com/atom.xml' type='application/atom+xml' rel='alternate'>
        </head></html>
        """
        let links = FeedFetcher.feedLinks(inHTML: html, baseURL: URL(string: "https://example.com/blog/")!)
        #expect(links == [
            URL(string: "https://example.com/feed.xml?a=1&b=2")!,
            URL(string: "https://example.com/atom.xml")!,
        ])
    }

    @Test func plainTextStripsTagsAndEntities() {
        #expect(HTMLText.plainText("<p>Fish &amp; chips</p>\n<script>evil()</script><b>tonight</b>") == "Fish & chips tonight")
        #expect(HTMLText.plainText("&amp;lt;b&amp;gt;") == "&lt;b&gt;")
        // UC-001 BR-004 (OQ-001): a shortened text, ellipsis included, stays within the limit.
        #expect(HTMLText.plainText("abcdef", limit: 3) == "ab\u{2026}")
    }

    @Test func opmlRoundTrip() throws {
        let feeds = [
            Feed(title: "A & B", url: URL(string: "https://a.example/feed")!, siteURL: URL(string: "https://a.example")!),
            Feed(title: "C", url: URL(string: "https://c.example/rss")!),
        ]
        let entries = try OPML.parse(Data(OPML.export(feeds).utf8))
        #expect(entries.map(\.title) == ["A & B", "C"])
        #expect(entries.map(\.url) == feeds.map(\.url))
        #expect(entries[0].siteURL == URL(string: "https://a.example"))
    }
}

@Suite @MainActor struct FeedStoreTests {
    private func makeStore() -> (FeedStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "RSSReaderTests-\(UUID().uuidString)")
        let file = dir.appending(path: "library.json")
        return (FeedStore(fileURL: file), file)
    }

    @Test func importsOPMLAndPersists() throws {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let opml = file.deletingLastPathComponent().appending(path: "subs.opml")
        try FileManager.default.createDirectory(at: opml.deletingLastPathComponent(), withIntermediateDirectories: true)
        try OPML.export([
            Feed(title: "Zeta", url: URL(string: "https://z.example/feed")!),
            Feed(title: "alpha", url: URL(string: "https://a.example/feed")!),
        ]).write(to: opml, atomically: true, encoding: .utf8)

        #expect(try store.importOPML(from: opml) == 2)
        #expect(try store.importOPML(from: opml) == 0) // no duplicates
        #expect(store.feeds.map(\.title) == ["alpha", "Zeta"])

        let reloaded = FeedStore(fileURL: file)
        #expect(reloaded.feeds.map(\.url) == store.feeds.map(\.url))
    }
}
