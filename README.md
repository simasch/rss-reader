# RSS Reader

A small native RSS/Atom reader for macOS, iPhone and iPad, written in Swift and SwiftUI. No third-party dependencies.

## Features

- Three-pane layout: smart feeds (Unread, All, Starred) and subscriptions, article list, article view
  (on iPhone the same columns become a drill-down)
- Add a feed by its URL **or** by a website URL (the feed is discovered from `<link rel="alternate">`)
- Parses RSS 2.0, RSS 1.0 (RDF) and Atom, including `content:encoded` and Atom XHTML content
- Read/unread and starred state, unread badges, mark all as read
- Refreshes on launch and every 30 minutes, using conditional GET (`ETag` / `Last-Modified`)
- OPML import/export (File menu on macOS, ⋯ menu in the sidebar on iOS); folders are flattened on import
- Articles render with JavaScript disabled; links open in your default browser
- iOS: pull to refresh, swipe right to toggle read, swipe left to star, long-press for more, share sheet
- Library stored as JSON in the app's sandbox container, under
  `Library/Application Support/RSSReader/library.json`
  (on macOS: `~/Library/Containers/local.rssreader/Data/Library/Application Support/RSSReader/`)

## Build and run

Requires Xcode (Swift 6). The app runs on macOS 14+ and iOS/iPadOS 17+.

Open `RSSReader.xcodeproj`, pick *My Mac*, a simulator or a device as the destination, and press ⌘R.
⌘U runs the tests. One multiplatform target builds both the Mac and the iOS app.

From the terminal:

```sh
Scripts/build-app.sh                       # build "build/RSS Reader.app" (macOS, Release)
open "build/RSS Reader.app"

xcodebuild -project RSSReader.xcodeproj -scheme RSSReader \
  -destination 'generic/platform=iOS Simulator' build    # iOS build

cd RSSReaderKit && swift test              # core tests, no Xcode project needed
```

To run on a physical iPhone or to distribute, choose your team under *Signing & Capabilities* and
change the bundle identifier (`local.rssreader`) to one you own. Without a team, the Mac app is
signed to run locally.

The Mac app is sandboxed (outgoing network connections and user-selected files only). On its first
launch, `App/container-migration.plist` moves a library left by earlier, unsandboxed builds from
`~/Library/Application Support/RSSReader` into the container.

The app icons in `App/Assets.xcassets` (rounded macOS sizes and a full-bleed iOS icon) are drawn by
`Scripts/make-icon.swift`; run `swift Scripts/make-icon.swift` to regenerate them after editing.

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
RSSReader.xcodeproj        Multiplatform app target (macOS, iOS, iPadOS), shared scheme
App/                       App target sources: SwiftUI, with #if os(...) for platform differences
  RSSReaderApp.swift       App entry, macOS menu commands, auto-refresh, iOS save-on-background
  Platform.swift           Pasteboard and OPML type helpers
  Views/                   Sidebar, article list, article view, add-feed sheet
  Assets.xcassets          App icons
  Info.plist               App Transport Security exception for plain-HTTP feeds
  container-migration.plist  macOS: moves the pre-sandbox library into the container
RSSReaderKit/              Local Swift package with the platform-independent core
  Sources/RSSReaderKit/
    Models.swift           Feed, Article, SidebarItem, FeedError
    FeedParser.swift       XMLParser-based RSS/Atom parser, date parsing
    FeedFetcher.swift      HTTP fetching, conditional GET, feed discovery
    FeedStore.swift        Observable state, merging, persistence
    OPML.swift             OPML import/export
    HTMLText.swift         Tag stripping and escaping helpers
  Tests/RSSReaderKitTests/
Scripts/
  build-app.sh             Release build of the Mac app
  make-icon.swift          Draws the app icons
```

## Ideas for next steps

Folders, search, JSON Feed support, full-text extraction for excerpt-only feeds,
iCloud or Feedbin/Feedly sync, notifications for new articles.
