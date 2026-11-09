import SwiftUI
import UniformTypeIdentifiers

@main
struct RSSReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = FeedStore()

    private static let refreshInterval: Duration = .seconds(30 * 60)

    var body: some Scene {
        Window("RSS Reader", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 500)
                .task { await autoRefresh() }
        }
        .commands { FeedCommands(store: store) }
    }

    private func autoRefresh() async {
        while !Task.isCancelled {
            await store.refreshAll()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct FeedCommands: Commands {
    let store: FeedStore

    private var opmlType: UTType {
        UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
    }

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
            Button("Refresh All") { Task { await store.refreshAll() } }
                .keyboardShortcut("r")
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [opmlType, .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if try store.importOPML(from: url) > 0 {
                Task { await store.refreshAll() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Subscriptions.opml"
        panel.allowedContentTypes = [opmlType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportOPML(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
