//
//  MarkdownTheme.swift
//  Index
//
//  Created by Claude on 12/10/2025.
//

import SwiftUI
import MarkdownUI

extension Theme {
    /// Custom theme for Index app matching TypographyStyle
    static let indexTheme: Theme = {
        let typography = TypographyStyle.default

        return Theme()
            // Base text styling
            .text {
                FontSize(16)
                ForegroundColor(.primary)
                BackgroundColor(.clear)
            }
            // Headings
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(32)
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(24)
                        FontWeight(.bold)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(20)
                        FontWeight(.semibold)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(18)
                        FontWeight(.semibold)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(16)
                        FontWeight(.semibold)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(14)
                        FontWeight(.semibold)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            // Paragraphs with line spacing
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))  // ~1.8x line height
                    .padding(.bottom, typography.paragraphSpacing)
            }
            // Code blocks
            .codeBlock { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(14)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(typography.codeBackgroundColor)
                    )
                    .padding(.bottom, 16)
            }
            // Inline code
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(14)
                BackgroundColor(typography.codeBackgroundColor.opacity(0.8))
            }
            // Blockquotes
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 4)

                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(typography.blockquoteTextColor)
                        }
                }
                .padding(.leading, 8)
                .padding(.vertical, 8)
            }
            // Lists with proper indentation
            .list { configuration in
                configuration.label
                    .padding(.leading, typography.listIndentation)
            }
            .listItem { configuration in
                configuration.label
                    .padding(.bottom, 4)
            }
            // Links
            .link {
                ForegroundColor(.accentColor)
                UnderlineStyle(.single)
            }
            // Strong emphasis (bold)
            .strong {
                FontWeight(.bold)
            }
            // Emphasis (italic)
            .emphasis {
                FontStyle(.italic)
            }
            // Tables
            .table { configuration in
                configuration.label
                    .padding(.bottom, 16)
            }
            .tableCell { configuration in
                configuration.label
                    .padding(8)
            }
            // Thematic breaks (horizontal rules)
            .thematicBreak {
                Divider()
                    .padding(.vertical, 16)
            }
    }()
}
