# RSS Reader

A small native macOS RSS/Atom reader written in Swift and SwiftUI. No third-party dependencies.

## Features

- Three-pane layout: smart feeds (Unread, All, Starred) and subscriptions, article list, article view
- Add a feed by its URL **or** by a website URL (the feed is discovered from `<link rel="alternate">`)
- Parses RSS 2.0, RSS 1.0 (RDF) and Atom, including `content:encoded` and Atom XHTML content
- Read/unread and starred state, unread badges, mark all as read
- Refreshes on launch and every 30 minutes, using conditional GET (`ETag` / `Last-Modified`)
- OPML import/export (File menu); folders are flattened on import
- Articles render with JavaScript disabled; links open in your default browser
- Library stored as JSON in `~/Library/Application Support/RSSReader/library.json`

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```sh
swift run                    # run directly from the terminal
swift test                   # run the tests
Scripts/build-app.sh         # build "build/RSS Reader.app"
open "build/RSS Reader.app"
```

To work in Xcode, open `Package.swift`.

The app icon (`Resources/AppIcon.icns`) is drawn by `Scripts/make-icon.swift`; run
`swift Scripts/make-icon.swift` to regenerate it after editing.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | Add feed |
| ⌘R | Refresh all |
| ⌘K | Mark all in current list as read |
| ⇧⌘U | Toggle read |
| ⇧⌘L | Toggle star |
| ⌘B | Open article in browser |

## Layout

```
Sources/RSSReader/
  RSSReaderApp.swift     App entry, menu commands, auto-refresh
  Models.swift           Feed, Article, SidebarItem, FeedError
  FeedParser.swift       XMLParser-based RSS/Atom parser, date parsing
  FeedFetcher.swift      HTTP fetching, conditional GET, feed discovery
  FeedStore.swift        Observable state, merging, persistence
  OPML.swift             OPML import/export
  HTMLText.swift         Tag stripping and escaping helpers
  Views/                 SwiftUI views
```

## Ideas for next steps

Folders, search, JSON Feed support, full-text extraction for excerpt-only feeds,
iCloud or Feedbin/Feedly sync, notifications for new articles.
