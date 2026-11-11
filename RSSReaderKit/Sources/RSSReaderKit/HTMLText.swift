import Foundation

public enum HTMLText {
    private static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
        ("&apos;", "'"), ("&#8217;", "\u{2019}"), ("&#8216;", "\u{2018}"), ("&#8220;", "\u{201C}"),
        ("&#8221;", "\u{201D}"), ("&hellip;", "\u{2026}"), ("&#8230;", "\u{2026}"),
        ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
        ("&amp;", "&"), // must come last
    ]

    /// Strips tags and decodes common entities, for list snippets and titles. The result has at most
    /// `limit` characters; a shortened text ends in "…" (OQ-001).
    public static func plainText(_ html: String, limit: Int = 280) -> String {
        var s = html
            .replacingOccurrences(of: "<(script|style)[\\s\\S]*?</\\1>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in entities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > limit else { return s }
        return String(s.prefix(max(limit - 1, 0))).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
