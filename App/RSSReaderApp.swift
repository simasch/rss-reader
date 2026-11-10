import RSSReaderKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct RSSReaderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var store = FeedStore()

    private static let refreshInterval: Duration = .seconds(30 * 60)

    var body: some Scene {
        #if os(macOS)
        Window("RSS Reader", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 500)
                .task { await autoRefresh() }
        }
        .commands { FeedCommands(store: store) }
        #else
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await autoRefresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS may suspend or kill the app at any time once it leaves the foreground.
            if phase == .background { store.save() }
        }
        #endif
    }

    /// Refreshes on launch and periodically. On iOS the task is suspended with the app,
    /// so the next refresh happens when the timer fires after the app returns.
    private func autoRefresh() async {
        while !Task.isCancelled {
            await store.refreshAll()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

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
            Button("Refresh All") { Task { await store.refreshAll() } }
                .keyboardShortcut("r")
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Platform.opmlType, .xml]
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
