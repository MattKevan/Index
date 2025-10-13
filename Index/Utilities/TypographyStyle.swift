//
//  TypographyStyle.swift
//  Index
//
//  Created by Claude on 11/10/2025.
//

import Foundation
import SwiftUI

/// Typography configuration with sensible defaults for a pleasant reading and writing experience
///
/// ## Using Custom Fonts
///
/// To use custom fonts in your app:
///
/// 1. **Add font files to Xcode:**
///    - Drag .ttf or .otf font files into your Xcode project
///    - Ensure "Copy items if needed" is checked
///    - Add files to your app target
///
/// 2. **Register fonts in Info.plist:**
///    - For macOS apps, add the `ATSApplicationFontsPath` key
///    - Set the value to the folder name containing your fonts (e.g., "Fonts")
///    - Alternatively, use `UIAppFonts` array with individual font filenames for iOS
///
/// 3. **Find the PostScript name:**
///    - Open the font file in Font Book app
///    - Select the Font Info tab
///    - Copy3 the PostScript name (this is what you'll use in code)
///
/// 4. **Update TypographyStyle:**
///    ```swift
///    var bodyFont: Font = .custom("YourFontPostScriptName", size: 16)
///    var headingFonts: [Int: Font] = [
///        1: .custom("YourFontPostScriptName", size: 32).weight(.bold),
///        // ... etc
///    ]
///    ```
///
/// Custom fonts will automatically scale with Dynamic Type when using `.custom(_:size:)`.
struct TypographyStyle {
    // MARK: - Fonts

    /// Base font for body text (optimized for readability)
    /// To use a custom font, replace with: Font.custom("PostScriptName", size: 16)
    var bodyFont: Font = .system(size: 16, weight: .regular)

    /// Fonts for different heading levels
    var headingFonts: [Int: Font] = [
        1: .system(size: 32, weight: .bold),
        2: .system(size: 24, weight: .bold),
        3: .system(size: 20, weight: .semibold),
        4: .system(size: 18, weight: .semibold),
        5: .system(size: 16, weight: .semibold),
        6: .system(size: 14, weight: .semibold)
    ]

    /// Monospace font for code
    var codeFont: Font = .system(size: 14, weight: .regular, design: .monospaced)

    // MARK: - Spacing

    /// Line height multiplier (1.8 = 180% of font size, good for readability with paragraph spacing)
    /// Applied via .lineSpacing() modifier on TextEditor
    /// This increased value (from 1.6) creates better visual paragraph separation when blank lines are used
    var lineHeightMultiplier: CGFloat = 1.8

    /// Space between paragraphs (in points)
    /// NOTE: SwiftUI TextEditor with AttributedString has limited support for paragraph-level
    /// spacing attributes. Paragraph spacing is best achieved by:
    /// 1. Using blank lines between paragraphs (press Enter twice)
    /// 2. The line spacing from lineHeightMultiplier applies to all lines including blank ones
    /// This creates natural paragraph separation without complex AppKit paragraph styles
    var paragraphSpacing: CGFloat = 24

    /// Space after headings (in points)
    /// NOTE: Currently not applied due to SwiftUI TextEditor limitations
    /// Consider adding blank lines after headings manually
    var headingSpacing: CGFloat = 12

    /// Indentation for list items (in points)
    /// NOTE: Currently not applied due to SwiftUI TextEditor limitations
    var listIndentation: CGFloat = 24

    // MARK: - Layout

    /// Maximum width for text column (prevents lines from being too long)
    /// Optimal line length is 50-75 characters (~600-700pt at 16pt font)
    var maxColumnWidth: CGFloat = 700

    /// Padding around the text editor
    var editorPadding: CGFloat = 40

    // MARK: - Colors

    /// Background color for code blocks
    var codeBackgroundColor: Color = Color(white: 0.95, opacity: 1.0)

    /// Text color for blockquotes
    var blockquoteTextColor: Color = Color(white: 0.4, opacity: 1.0)

    // MARK: - Default Instance

    /// Shared default typography style
    static let `default` = TypographyStyle()

    // MARK: - Methods

    /// Apply this typography style to an AttributedString
    func apply(to attributedString: inout AttributedString) {
        // Apply base font to entire string using SwiftUI scope
        attributedString.swiftUI.font = bodyFont

        // Note: Line height and paragraph spacing are better controlled via
        // TextEditor modifiers or individual attribute application
    }

    /// Get the appropriate font for a heading level
    func font(for headingLevel: Int) -> Font {
        return headingFonts[headingLevel] ?? bodyFont
    }

    /// Calculate line spacing in points for use with .lineSpacing() modifier
    /// Based on the lineHeightMultiplier and body font size
    var lineSpacingPoints: CGFloat {
        // Extract font size from bodyFont (default 16pt)
        let baseFontSize: CGFloat = 16

        // lineHeightMultiplier of 1.6 means 160% line height
        // SwiftUI's .lineSpacing() adds extra space between lines
        // Formula: (fontSize * multiplier) - fontSize = extra spacing
        return (baseFontSize * lineHeightMultiplier) - baseFontSize
    }
}

// MARK: - AttributedString Extensions

extension AttributedString {
    /// Apply typography style to the entire attributed string
    mutating func applyTypography(_ style: TypographyStyle = .default) {
        style.apply(to: &self)
    }
}
