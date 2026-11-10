import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Small wrappers over the few AppKit/UIKit APIs the shared code needs.
enum Platform {
    static func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    static var opmlType: UTType {
        UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
    }
}
