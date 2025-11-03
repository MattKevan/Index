//
//  EPUBTextExtractor.swift
//  Index
//
//  Created by Claude on 11/03/2025.
//

import Foundation
import EPUBKit

/// Metadata extracted from EPUB files
struct EPUBMetadata {
    var title: String?
    var author: String?
    var description: String?
    var publisher: String?
    var language: String?

    var formattedSummary: String? {
        var parts: [String] = []

        if let author = author {
            parts.append("Author: \(author)")
        }

        if let description = description {
            parts.append(description)
        }

        if let publisher = publisher {
            parts.append("Publisher: \(publisher)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

/// Actor-isolated service for extracting text from EPUB documents
/// Uses EPUBKit for parsing and native Swift for text extraction
actor EPUBTextExtractor {
    static let shared = EPUBTextExtractor()

    private init() {}

    // MARK: - Text Extraction

    /// Extract text and metadata from an EPUB file
    /// - Parameter url: URL to the EPUB file
    /// - Returns: Tuple of (extracted text, metadata)
    /// - Throws: EPUBExtractionError if extraction fails
    func extractTextAndMetadata(from url: URL) async throws -> (text: String, metadata: EPUBMetadata) {
        let text = try await extractText(from: url)
        let metadata = try await extractMetadata(from: url)
        return (text, metadata)
    }

    /// Extract text from an EPUB file using EPUBKit
    /// - Parameter url: URL to the EPUB file
    /// - Returns: Extracted text in markdown format with chapter separators
    /// - Throws: EPUBExtractionError if extraction fails
    func extractText(from url: URL) async throws -> String {
        print("📖 Parsing EPUB with EPUBKit: \(url.lastPathComponent)")

        // Parse EPUB using EPUBKit
        guard let document = EPUBDocument(url: url) else {
            print("❌ EPUBKit failed to parse document")
            throw EPUBExtractionError.invalidEPUB
        }

        print("✅ EPUBKit parsed document: \(document.title ?? "Untitled")")
        print("   Author: \(document.author ?? "Unknown")")
        print("   Spine items: \(document.spine.items.count)")

        // Extract text from spine items in order
        var extractedText = ""
        var successfulChapters = 0

        for (index, spineItem) in document.spine.items.enumerated() {
            // Get the manifest item for this spine item
            guard let manifestItem = document.manifest.items.first(where: { $0.id == spineItem.idref }) else {
                print("⚠️ Chapter \(index + 1): No manifest item for spine idref '\(spineItem.idref)'")
                continue
            }

            // Read the chapter file
            guard let chapterData = document.data(for: manifestItem),
                  let chapterHTML = String(data: chapterData, encoding: .utf8) else {
                print("⚠️ Chapter \(index + 1): Failed to read data for \(manifestItem.href)")
                continue
            }

            // Convert HTML to markdown
            let chapterText = cleanHTML(chapterHTML)

            if !chapterText.isEmpty {
                if successfulChapters > 0 {
                    extractedText += "\n\n---\n\n"
                }
                extractedText += "## Chapter \(index + 1)\n\n"
                extractedText += chapterText
                extractedText += "\n"
                successfulChapters += 1
                print("   ✓ Chapter \(index + 1): Extracted \(chapterText.count) characters")
            }
        }

        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EPUBExtractionError.noTextFound(message: "EPUB appears to have no readable text content.")
        }

        print("✅ Extracted text from \(successfulChapters)/\(document.spine.items.count) chapters")
        return extractedText
    }

    // MARK: - HTML Cleaning

    /// Clean HTML markup and convert to plain text
    private func cleanHTML(_ html: String) -> String {
        var text = html

        // Remove DOCTYPE and XML declarations
        text = text.replacingOccurrences(
            of: #"<!DOCTYPE[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<\?xml[^>]*\?>"#,
            with: "",
            options: .regularExpression
        )

        // Remove script and style tags with content
        text = text.replacingOccurrences(
            of: #"<script[^>]*>.*?</script>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<style[^>]*>.*?</style>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Convert headings to markdown
        for level in 1...6 {
            let pattern = "<h\(level)[^>]*>(.*?)</h\(level)>"
            text = text.replacingOccurrences(
                of: pattern,
                with: "\n\(String(repeating: "#", count: level)) $1\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Convert paragraph and div endings to newlines
        text = text.replacingOccurrences(
            of: #"</(p|div|h[1-6]|li)>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Convert emphasis tags to markdown
        text = text.replacingOccurrences(
            of: #"<(strong|b)[^>]*>(.*?)</\1>"#,
            with: "**$2**",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<(em|i)[^>]*>(.*?)</\1>"#,
            with: "*$2*",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Clean up excessive whitespace
        text = text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode common HTML entities
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&mdash;": "—",
            "&ndash;": "–",
            "&ldquo;": "\u{201C}",
            "&rdquo;": "\u{201D}",
            "&lsquo;": "\u{2018}",
            "&rsquo;": "\u{2019}",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric entities (&#123; or &#xAB;)
        if let decimalRegex = try? NSRegularExpression(pattern: #"&#(\d+);"#, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = decimalRegex.matches(in: result, range: range)

            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result),
                      let numberRange = Range(match.range(at: 1), in: result),
                      let code = Int(result[numberRange]),
                      let scalar = Unicode.Scalar(code) else {
                    continue
                }

                result.replaceSubrange(matchRange, with: String(Character(scalar)))
            }
        }

        return result
    }

    // MARK: - Metadata Extraction

    /// Extract metadata from EPUB file using EPUBKit
    func extractMetadata(from url: URL) async throws -> EPUBMetadata {
        // Parse EPUB using EPUBKit
        guard let document = EPUBDocument(url: url) else {
            throw EPUBExtractionError.invalidEPUB
        }

        // Extract metadata from EPUBKit document
        return EPUBMetadata(
            title: document.title,
            author: document.author,
            description: document.metadata.description,
            publisher: document.metadata.publisher,
            language: document.metadata.language
        )
    }
}

// MARK: - Data Types

enum EPUBExtractionError: Error, LocalizedError {
    case invalidEPUB
    case noContentFound
    case noTextFound(message: String)
    case chapterReadFailed
    case encodingError
    case readFailed

    var errorDescription: String? {
        switch self {
        case .invalidEPUB:
            return "The file is not a valid EPUB or is corrupted."
        case .noContentFound:
            return "The EPUB contains no chapters or content."
        case .noTextFound(let message):
            return message
        case .chapterReadFailed:
            return "Failed to read a chapter from the EPUB."
        case .encodingError:
            return "Failed to decode chapter text encoding."
        case .readFailed:
            return "Failed to read the EPUB file."
        }
    }
}

enum ExtractionQuality {
    case excellent
    case good
    case fair
    case poor
}
