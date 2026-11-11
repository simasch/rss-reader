import Combine
import SwiftUI

/// Test hook for ViewInspector: lets the UI tests inspect a view's `@State` while it is hosted.
/// Has no effect in the app; see ViewInspector's guide, "Views using @State", approach #2.
internal final class Inspection<V>: @unchecked Sendable {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}
