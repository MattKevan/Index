//
//  MarkdownPattern.swift
//  Index
//
//  Created by Claude on 11/10/2025.
//

import Foundation
import SwiftUI

/// Defines patterns for detecting markdown syntax in text
enum MarkdownPattern: CaseIterable {
    case bold              // **text** or __text__
    case italic            // *text* or _text_
    case strikethrough     // ~~text~~
    case inlineCode        // `code`
    case header1           // # text (at line start)
    case header2           // ## text (at line start)
    case header3           // ### text (at line start)
    case header4           // #### text (at line start)
    case header5           // ##### text (at line start)
    case header6           // ###### text (at line start)
    case bulletList        // - item or * item (at line start)
    case numberedList      // 1. item (at line start)
    case link              // [text](url)
    case blockquote        // > text (at line start)

    /// The regex pattern for detecting this markdown syntax
    var regex: String {
        switch self {
        case .bold:
            // Match **text** or __text__ (non-greedy, no nested formatting)
            return "\\*\\*([^*]+?)\\*\\*|__([^_]+?)__"
        case .italic:
            // Match *text* or _text_ (but not ** or __)
            return "(?<!\\*)\\*(?!\\*)([^*]+?)\\*(?!\\*)|(?<!_)_(?!_)([^_]+?)_(?!_)"
        case .strikethrough:
            return "~~([^~]+?)~~"
        case .inlineCode:
            return "`([^`]+?)`"
        case .header1:
            return "^# (.+)$"
        case .header2:
            return "^## (.+)$"
        case .header3:
            return "^### (.+)$"
        case .header4:
            return "^#### (.+)$"
        case .header5:
            return "^##### (.+)$"
        case .header6:
            return "^###### (.+)$"
        case .bulletList:
            return "^[*-] (.+)$"
        case .numberedList:
            return "^\\d+\\. (.+)$"
        case .link:
            return "\\[([^\\]]+?)\\]\\(([^)]+?)\\)"
        case .blockquote:
            return "^> (.+)$"
        }
    }

    /// Options for regex matching
    var regexOptions: NSRegularExpression.Options {
        switch self {
        case .header1, .header2, .header3, .header4, .header5, .header6,
             .bulletList, .numberedList, .blockquote:
            return [.anchorsMatchLines]
        default:
            return []
        }
    }

    /// The color to apply to this pattern (for syntax highlighting)
    var color: Color {
        switch self {
        case .bold:
            return .primary
        case .italic:
            return .primary
        case .strikethrough:
            return .secondary
        case .inlineCode:
            return .purple
        case .header1, .header2, .header3, .header4, .header5, .header6:
            return .primary
        case .bulletList, .numberedList:
            return .primary
        case .link:
            return .blue
        case .blockquote:
            return .secondary
        }
    }

    /// Whether this pattern should remove the markdown syntax when formatting
    var shouldRemoveSyntax: Bool {
        switch self {
        case .bold, .italic, .strikethrough, .inlineCode:
            return true // Remove ** __ * _ ~~ `
        case .header1, .header2, .header3, .header4, .header5, .header6:
            return true // Remove # ## ###
        case .bulletList, .numberedList:
            return false // Keep list markers for now
        case .link:
            return true // Convert [text](url) to just clickable text
        case .blockquote:
            return false // Keep > marker
        }
    }

    /// The header level (if this is a header pattern)
    var headerLevel: Int? {
        switch self {
        case .header1: return 1
        case .header2: return 2
        case .header3: return 3
        case .header4: return 4
        case .header5: return 5
        case .header6: return 6
        default: return nil
        }
    }

    /// Check if text matches this pattern at the start
    func matches(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: self.regex, options: regexOptions) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Find all matches of this pattern in the text
    func findMatches(in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: self.regex, options: regexOptions) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
    }
}

/// Result of pattern matching
struct MarkdownMatch {
    let pattern: MarkdownPattern
    let range: Range<String.Index>
    let capturedText: String  // The text without markdown syntax
    let fullMatch: String     // The full match including syntax
}
