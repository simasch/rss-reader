import Foundation
import RSSReaderKit

/// UC-006 steps 3 to 7: what happens with the file the Reader selected to import. Shared by the Mac's
/// Import OPML… command and the file importer on iPhone and iPad, which only differ in how they ask for the file
/// and how they display the message.
@MainActor
struct SubscriptionImport {
    /// How an import ended.
    enum Outcome {
        /// UC-006 A3: the Reader cancelled the file selection.
        case cancelled
        /// UC-006 A2: the file added no feed; the library is unchanged and no refresh is started.
        case noNewFeeds
        /// UC-006 steps 5 to 7: `count` feeds were added and saved, and the refresh of all feeds was requested.
        case imported(count: Int, refresh: Task<Void, Never>)
        /// UC-006 A1 and A4: the import failed and added no feed; `error` is the message to display.
        case failed(Error)

        /// The message the Reader is shown, if any.
        var message: String? {
            if case .failed(let error) = self { error.localizedDescription } else { nil }
        }
    }

    let store: FeedStore

    /// Imports the selected file; `nil` means the Reader cancelled the selection.
    @discardableResult
    func run(_ selection: Result<URL, Error>?) -> Outcome {
        guard let selection else { return .cancelled }
        do {
            // UC-006 steps 4 to 6, A1, A4: `importOPML` reads, adds, and saves, or throws and adds nothing.
            let added = try store.importOPML(from: selection.get())
            // UC-006 A2: nothing new is added, so nothing is refreshed.
            guard added > 0 else { return .noNewFeeds }
            // UC-006 step 7: refresh all feeds, or queue behind the running refresh (UC-003 BR-002).
            let refresh = Task { await store.refreshAll(requestedByImport: true) }
            return .imported(count: added, refresh: refresh)
        } catch {
            // UC-006 BR-006: an import that cannot be saved starts no refresh.
            return .failed(error)
        }
    }
}
