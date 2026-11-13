#if os(macOS)
import AppKit
import RSSReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// The Mac's menu commands for feeds.
struct FeedCommands: Commands {
    let store: FeedStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Feed…") { store.isAddingFeed = true }
                .keyboardShortcut("n")
        }
        CommandGroup(replacing: .importExport) {
            Button("Import OPML…", action: importOPML)
            Button("Export OPML…", action: exportOPML)
        }
        CommandMenu("Feeds") {
            // UC-003 BR-001: on the Mac the Reader can also refresh from the menu.
            Button("Refresh All") { Task { await store.refreshAll() } }
                .keyboardShortcut("r")
                // UC-003 BR-002: the refresh action is disabled while a refresh is running.
                .disabled(store.isRefreshing)
        }
    }

    /// UC-006 step 2: the panel that asks for the subscription file.
    static func makeImportPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Platform.opmlType, .xml]
        return panel
    }

    private func importOPML() {
        let panel = Self.makeImportPanel()
        // UC-006 A3: a cancelled panel selects no file.
        let selection = panel.runModal() == .OK ? panel.url.map { Result<URL, Error>.success($0) } : nil
        // UC-006 A1, A4: the message is displayed in an alert.
        if case .failed(let error) = SubscriptionImport(store: store).run(selection) {
            NSAlert(error: error).runModal()
        }
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Subscriptions.opml"
        panel.allowedContentTypes = [Platform.opmlType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportOPML(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
#endif
