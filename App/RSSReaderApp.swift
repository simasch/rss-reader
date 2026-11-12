import RSSReaderKit
import SwiftUI

@main
struct RSSReaderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var store = FeedStore()

    var body: some Scene {
        #if os(macOS)
        Window("RSS Reader", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 500)
                .refreshSchedule(store)
        }
        .commands { FeedCommands(store: store) }
        #else
        WindowGroup {
            ContentView()
                .environment(store)
                .refreshSchedule(store)
        }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
