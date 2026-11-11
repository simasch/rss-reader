# Stack

**For the agent:** read before writing code. This file is the AI Unified Process record of the technical layers,
independent of how the team documents its architecture. The Layers table says which layer skill builds and tests
each technical layer: `/use-case-implement` runs the Skill column bottom-up, `/use-case-test` runs the Test skill
column from the integration layer up, and `/use-case-coverage` searches for the markers in the last table.

**Last updated:** 2026-11-11

## Layers

| Layer       | Technology                                                       | Skill | Test skill | Location                                                              |
|-------------|------------------------------------------------------------------|-------|------------|-----------------------------------------------------------------------|
| Migration   | –                                                                | –     | –          | –                                                                     |
| Persistence | JSON file via `Codable` (`library.json` in the app container)    | –     | –          | `RSSReaderKit/Sources/RSSReaderKit/FeedStore.swift` (load/save)       |
| Client      | `URLSession` (HTTP, conditional GET, feed discovery)             | –     | –          | `RSSReaderKit/Sources/RSSReaderKit/FeedFetcher.swift`                 |
| Service     | Swift 6, `@Observable` `FeedStore`, `XMLParser` (feeds, OPML)    | –     | –          | `RSSReaderKit/Sources/RSSReaderKit/`                                  |
| API         | –                                                                | –     | –          | –                                                                     |
| UI          | SwiftUI (macOS 14+, iOS/iPadOS 17+); tests: Swift Testing + ViewInspector, in process | –     | –          | `App/Views/`; tests in `AppTests/`                                    |
| E2E         | –                                                                | –     | –          | –                                                                     |

**Integration layer:**

| Use case offered through | Tested in | Test skill |
|--------------------------|-----------|------------|
| UI                       | UI        | –          |
| Service                  | Service   | –          |

A layer the project does not have is marked `–` in every column (a UI layer in a REST service). The Integration
layer table keeps only the rows of the entry layers the project has — a REST service drops the UI row — and its
Test skill column names what the Layers table names for that layer (`–` while the skill is not installed). A use
case is tested in the first row its `**Layers:**` line names, or in the first row when it has no such line. That layer's tests run in process against the real database
and exercise every layer below it, so `/use-case-test` runs its test skill and the ones above it and writes no tests
of their own for the layers below unless a run names them (`/use-case-test UC-001 persistence`).

No layer skill covers Swift, so every layer is built and tested by `/use-case-implement` and `/use-case-test` from
their own knowledge. The UI row is the integration layer by the team's decision: SwiftUI views are tested in
process against the real `FeedStore` (with a temporary library file and a stubbed Feed Publisher), not with the
backend mocked. The tests use Swift Testing, like the existing `RSSReaderKitTests`, and ViewInspector to drive the
views; a view whose `@State` a test must reach carries ViewInspector's two-line `Inspection` hook (`App/Inspection.swift`).
They run in the `RSSReaderTests` target, which compiles the views it needs from `App/` instead of hosting the app, so
no test touches the Reader's own library. The Feed Publisher is replaced by a `URLProtocol` stub.

UI tests run on macOS and on an iOS simulator: each platform's layout of a view is tested on its own platform.
Behaviour that exists on one platform only (the Mac's clipboard prefill) is tested there.

## External systems

| System         | Contract                                                                                   | Location                                              |
|----------------|--------------------------------------------------------------------------------------------|-------------------------------------------------------|
| Feed Publisher | Public feed formats: RSS 2.0, RSS 1.0 (RDF), Atom (RFC 4287); HTML `<link rel="alternate">` for discovery | `RSSReaderKit/Sources/RSSReaderKit/FeedFetcher.swift` |

The systems our system calls, by the name the use cases write on their `**Secondary Actors:**` line: the Client
layer builds an adapter for each one from its contract (OpenAPI or AsyncAPI; `–` while there is none). A secondary
actor without a row is a person or a role. Without a Client layer the section is dropped.

## Module layout

- `RSSReaderKit/` — local Swift package (product `RSSReaderKit`, module `RSSReaderKit`) with the platform-independent
  core: models, persistence, client, service. Tests in `RSSReaderKit/Tests/RSSReaderKitTests/` (Swift Testing).
- `App/` — the multiplatform app target of `RSSReader.xcodeproj` (macOS, iOS, iPadOS): SwiftUI views in
  `App/Views/`, platform differences with `#if os(...)`.
- `AppTests/` — the `RSSReaderTests` unit test target of `RSSReader.xcodeproj`: the UI tests, one suite per use case
  (`UC<nnn><Name>Test.swift`), and the Feed Publisher stub. Not hosted by the app; it compiles the views it tests
  from `App/` (membership exceptions on the `App` folder) and links `RSSReaderKit` and ViewInspector.
- Dependencies: none in the app; ViewInspector (Swift package, 0.10.x) in the test target only.

## Commands

| Purpose            | Command                                                                                      |
|--------------------|----------------------------------------------------------------------------------------------|
| Build              | `Scripts/build-app.sh` (macOS); `xcodebuild -project RSSReader.xcodeproj -scheme RSSReader -destination 'generic/platform=iOS Simulator' build` (iOS) |
| Unit tests         | `cd RSSReaderKit && swift test`                                                              |
| Integration tests  | `xcodebuild test -project RSSReader.xcodeproj -scheme RSSReader -destination 'platform=macOS,arch=arm64'` (macOS); `xcodebuild test -project RSSReader.xcodeproj -scheme RSSReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RSSReaderTests` (iOS) |
| End-to-end tests   | –                                                                                            |

## Markers

Each layer skill keeps its own rows here: on every run it checks that the rows for its layer match its marker
reference and corrects them. Do not edit the rows by hand; rerun the layer skill instead.

| Layer | Skill | Kind | Marker to grep for |
|-------|-------|------|--------------------|
| All   | –     | Code | `// UC-XXX BR-YYY:` directly above the method, query condition, or validator that enforces the rule |
| UI    | –     | Test | One suite per use case, `struct UC<nnn><Name>Test` in `AppTests/UC<nnn><Name>Test.swift`, annotated `@Suite("UC-XXX <use case name>")`; each `@Test` display name starts with the scenario it covers: `Main success scenario`, `Step N`, `A<n>`, `BR-YYY` |
