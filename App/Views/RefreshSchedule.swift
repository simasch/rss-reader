import RSSReaderKit
import SwiftUI

/// Runs the Scheduler's refresh for the window it is attached to: from the start on the Mac, and on iPhone and iPad
/// only while the app is in the foreground.
struct RefreshSchedule: ViewModifier {
    let store: FeedStore
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            // UC-003 BR-001: refresh at start, then every 30 minutes while the app runs.
            .onAppear { store.resumeScheduledRefresh() }
        #else
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    // UC-003 BR-001: a refresh that fell due in the background follows right away.
                    store.resumeScheduledRefresh()
                case .background:
                    // UC-003 BR-001: no refresh runs in the background on iPhone and iPad.
                    store.pauseScheduledRefresh()
                    // iOS may suspend or kill the app at any time once it leaves the foreground.
                    store.save()
                default:
                    break
                }
            }
        #endif
    }
}

extension View {
    /// Attaches the Scheduler's refresh (UC-003) to the app's window.
    func refreshSchedule(_ store: FeedStore) -> some View {
        modifier(RefreshSchedule(store: store))
    }
}
