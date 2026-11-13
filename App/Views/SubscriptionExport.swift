import Foundation
import RSSReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// UC-007: what happens around the file the Reader saves the subscriptions to. Shared by the Mac's Export OPML…
/// command, which writes the file itself, and the file exporter on iPhone and iPad, which writes `document`; they
/// only differ in how they ask for the location and how they display the message.
@MainActor
struct SubscriptionExport {
    /// How an export ended.
    enum Outcome {
        /// UC-007 A2: the Reader cancelled the save dialog.
        case cancelled
        /// UC-007 step 4: the file was written.
        case exported
        /// UC-007 A1: the file could not be written; `error` is the message to display.
        case failed(Error)

        /// The message the Reader is shown, if any.
        var message: String? {
            if case .failed(let error) = self { error.localizedDescription } else { nil }
        }
    }

    let store: FeedStore

    /// UC-007 precondition: the subscriptions can be exported only while the library holds at least one feed.
    var canExport: Bool { !store.feeds.isEmpty }

    /// UC-007 step 4: the document the file exporter on iPhone and iPad writes to the chosen location.
    var document: OPMLDocument { OPMLDocument(text: OPML.export(store.feeds)) }

    /// UC-007 steps 3 and 4 on the Mac: writes the subscriptions to the chosen location; `nil` means the Reader
    /// cancelled the save dialog.
    @discardableResult
    func run(_ location: URL?) -> Outcome {
        // UC-007 A2: a cancelled dialog writes nothing.
        guard let location else { return .cancelled }
        do {
            // UC-007 step 4, A1: `exportOPML` writes every subscription, or throws and leaves no partial file.
            try store.exportOPML(to: location)
            return .exported
        } catch {
            return .failed(error)
        }
    }

    /// UC-007 step 4 on iPhone and iPad: how the file exporter's outcome ends the use case.
    func finish(_ result: Result<URL, Error>) -> Outcome {
        switch result {
        case .success:
            return .exported
        case .failure(let error as CocoaError) where error.code == .userCancelled:
            // UC-007 A2: a cancellation the exporter reports as an error displays no message.
            return .cancelled
        case .failure(let error):
            print("Failed to export subscriptions: \(error)")
            // UC-007 A1: one message, whatever kept the file from being written.
            return .failed(FeedError.exportFailed)
        }
    }
}

/// UC-007 step 4: the exported OPML text as a document for SwiftUI's file exporter.
struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [Platform.opmlType] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
