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

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Platform.opmlType, .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if try store.importOPML(from: url) > 0 {
                Task { await store.refreshAll(requestedByImport: true) }
            }
        } catch {
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
