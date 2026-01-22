import SwiftUI

extension String {
    /// Convert markdown string to AttributedString
    /// Supports **bold**, *italic*, `code`, and other standard markdown
    func attributedMarkdown() -> AttributedString {
        do {
            // SwiftUI natively supports markdown in AttributedString (iOS 15+)
            return try AttributedString(markdown: self, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            // Fallback to plain text if markdown parsing fails
            print("⚠️ Failed to parse markdown: \(error)")
            return AttributedString(self)
        }
    }

    /// Check if string contains markdown syntax
    var containsMarkdown: Bool {
        let markdownPatterns = [
            "**", "*", "__", "_",  // Bold/italic
            "`",                     // Code
            "[", "]", "(",  ")",    // Links
            "#", "-", "*",          // Headers/lists
            "```"                   // Code blocks
        ]

        return markdownPatterns.contains { self.contains($0) }
    }
}
