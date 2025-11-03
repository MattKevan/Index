//
//  EPUBTextExtractor.swift
//  Index
//
//  Created by Claude on 11/03/2025.
//

import Foundation

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
/// Uses native ZIP extraction and XML parsing
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

    /// Extract text from an EPUB file
    /// - Parameter url: URL to the EPUB file
    /// - Returns: Extracted text in markdown format with chapter separators
    /// - Throws: EPUBExtractionError if extraction fails
    func extractText(from url: URL) async throws -> String {
        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract EPUB (ZIP) to temp directory
        try await extractEPUB(from: url, to: tempDir)

        // Parse container.xml to find content.opf location
        let opfPath = try await parseContainer(in: tempDir)

        // Parse content.opf to get spine and manifest
        let (spine, manifest) = try await parseContentOPF(at: tempDir.appendingPathComponent(opfPath))

        // Extract text from spine items in order
        var extractedText = ""
        var successfulChapters = 0

        for (index, spineItem) in spine.enumerated() {
            guard let manifestItem = manifest[spineItem] else {
                print("⚠️ Could not find manifest item for spine item: \(spineItem)")
                continue
            }

            do {
                let chapterText = try await extractChapterText(
                    from: tempDir,
                    opfBasePath: (opfPath as NSString).deletingLastPathComponent,
                    manifestItem: manifestItem,
                    chapterNumber: index + 1
                )

                if !chapterText.isEmpty {
                    if successfulChapters > 0 {
                        extractedText += "\n\n---\n\n"
                    }
                    extractedText += chapterText
                    extractedText += "\n"
                    successfulChapters += 1
                }
            } catch {
                print("⚠️ Failed to extract chapter \(index + 1): \(error)")
            }
        }

        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EPUBExtractionError.noTextFound(message: "EPUB appears to have no readable text content.")
        }

        print("✅ Extracted text from \(successfulChapters)/\(spine.count) chapters")
        return extractedText
    }

    // MARK: - EPUB Extraction

    /// Extract EPUB ZIP archive to temporary directory
    private func extractEPUB(from epubURL: URL, to destinationURL: URL) async throws {
        print("📦 Extracting EPUB from: \(epubURL.path)")
        print("📦 Extracting to: \(destinationURL.path)")

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Use macOS native unzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", epubURL.path, "-d", destinationURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            print("❌ Unzip failed with status: \(process.terminationStatus)")
            throw EPUBExtractionError.invalidEPUB
        }

        // List extracted contents for debugging
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationURL.path) {
            print("✅ Extracted \(contents.count) items: \(contents.prefix(5))")
        }
    }

    // MARK: - XML Parsing

    /// Parse container.xml to find content.opf location
    private func parseContainer(in epubDir: URL) async throws -> String {
        let containerPath = epubDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        print("📖 Looking for container.xml at: \(containerPath.path)")

        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            print("❌ container.xml not found at path")
            throw EPUBExtractionError.noContentFound
        }

        guard let data = try? Data(contentsOf: containerPath),
              let xmlString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to read container.xml")
            throw EPUBExtractionError.noContentFound
        }

        print("📄 Container.xml content preview: \(xmlString.prefix(200))")

        // Use NSRegularExpression for more reliable parsing
        let pattern = #"full-path\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
              let pathRange = Range(match.range(at: 1), in: xmlString) else {
            print("❌ Could not find full-path attribute in container.xml")
            throw EPUBExtractionError.noContentFound
        }

        let path = String(xmlString[pathRange])
        print("✅ Found content.opf path: \(path)")
        return path
    }

    /// Parse content.opf to get spine and manifest
    private func parseContentOPF(at opfURL: URL) async throws -> (spine: [String], manifest: [String: String]) {
        print("📖 Reading content.opf at: \(opfURL.path)")

        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            print("❌ content.opf not found")
            throw EPUBExtractionError.noContentFound
        }

        guard let data = try? Data(contentsOf: opfURL),
              let xmlString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to read content.opf")
            throw EPUBExtractionError.noContentFound
        }

        print("📄 Content.opf preview: \(xmlString.prefix(300))")

        // Parse manifest items (id -> href mapping)
        var manifest: [String: String] = [:]

        // Try both id-first and href-first patterns
        let patterns = [
            #"<item[^>]+id="([^"]+)"[^>]+href="([^"]+)""#,
            #"<item[^>]+href="([^"]+)"[^>]+id="([^"]+)""#
        ]

        for (index, manifestPattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: manifestPattern, options: []) {
                let range = NSRange(xmlString.startIndex..., in: xmlString)
                regex.enumerateMatches(in: xmlString, range: range) { match, _, _ in
                    guard let match = match,
                          match.numberOfRanges == 3,
                          let firstRange = Range(match.range(at: 1), in: xmlString),
                          let secondRange = Range(match.range(at: 2), in: xmlString) else {
                        return
                    }

                    let first = String(xmlString[firstRange])
                    let second = String(xmlString[secondRange])

                    // First pattern: id, href
                    // Second pattern: href, id
                    if index == 0 {
                        manifest[first] = second
                    } else {
                        manifest[second] = first
                    }
                }
            }
            if !manifest.isEmpty { break }
        }

        print("📚 Found \(manifest.count) manifest items")

        // Parse spine itemrefs (reading order)
        var spine: [String] = []
        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#

        if let regex = try? NSRegularExpression(pattern: spinePattern, options: []) {
            let range = NSRange(xmlString.startIndex..., in: xmlString)
            regex.enumerateMatches(in: xmlString, range: range) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges == 2,
                      let idrefRange = Range(match.range(at: 1), in: xmlString) else {
                    return
                }

                let idref = String(xmlString[idrefRange])
                spine.append(idref)
            }
        }

        print("📖 Found \(spine.count) spine items: \(spine.prefix(5))")

        if spine.isEmpty || manifest.isEmpty {
            print("❌ Spine or manifest is empty")
            print("   Spine items: \(spine.count)")
            print("   Manifest items: \(manifest.count)")
            throw EPUBExtractionError.noContentFound
        }

        return (spine, manifest)
    }

    // MARK: - Chapter Extraction

    /// Extract text from a single chapter
    private func extractChapterText(
        from epubDir: URL,
        opfBasePath: String,
        manifestItem: String,
        chapterNumber: Int
    ) async throws -> String {
        // Build full path to chapter file
        var chapterPath = epubDir
        if !opfBasePath.isEmpty && opfBasePath != "." {
            chapterPath = chapterPath.appendingPathComponent(opfBasePath)
        }
        chapterPath = chapterPath.appendingPathComponent(manifestItem)

        // Read chapter HTML/XHTML
        guard let data = try? Data(contentsOf: chapterPath),
              let htmlString = String(data: data, encoding: .utf8) else {
            throw EPUBExtractionError.chapterReadFailed
        }

        // Clean HTML and convert to text
        let cleanedText = cleanHTML(htmlString)

        // Add chapter header
        return "## Chapter \(chapterNumber)\n\n\(cleanedText)"
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

    /// Extract metadata from EPUB file
    func extractMetadata(from url: URL) async throws -> EPUBMetadata {
        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract EPUB
        try await extractEPUB(from: url, to: tempDir)

        // Parse container.xml
        let opfPath = try await parseContainer(in: tempDir)

        // Read content.opf
        let opfURL = tempDir.appendingPathComponent(opfPath)
        guard let data = try? Data(contentsOf: opfURL),
              let xmlString = String(data: data, encoding: .utf8) else {
            throw EPUBExtractionError.noContentFound
        }

        // Extract metadata using regex
        func extractMetadataTag(tag: String) -> String? {
            let pattern = "<dc:\(tag)[^>]*>([^<]+)</dc:\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
               let contentRange = Range(match.range(at: 1), in: xmlString) {
                let rawValue = String(xmlString[contentRange])
                return decodeHTMLEntities(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        return EPUBMetadata(
            title: extractMetadataTag(tag: "title"),
            author: extractMetadataTag(tag: "creator"),
            description: extractMetadataTag(tag: "description"),
            publisher: extractMetadataTag(tag: "publisher"),
            language: extractMetadataTag(tag: "language")
        )
    }

    /// Extract text with detailed metadata about extraction quality
    func extractTextWithMetadata(from url: URL) async throws -> EPUBExtractionResult {
        let text = try await extractText(from: url)

        // Count chapters by counting "---" separators
        let chapterCount = text.components(separatedBy: "\n---\n").count

        return EPUBExtractionResult(
            text: text,
            chapterCount: chapterCount,
            chaptersWithText: chapterCount,
            chaptersWithoutText: 0,
            totalCharacters: text.count,
            quality: ExtractionQuality.excellent
        )
    }

    /// Get basic information about an EPUB file
    func getEPUBInfo(from url: URL) async throws -> EPUBInfo {
        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract EPUB
        try await extractEPUB(from: url, to: tempDir)

        // Parse container.xml
        let opfPath = try await parseContainer(in: tempDir)

        // Read content.opf
        let opfURL = tempDir.appendingPathComponent(opfPath)
        guard let data = try? Data(contentsOf: opfURL),
              let xmlString = String(data: data, encoding: .utf8) else {
            throw EPUBExtractionError.noContentFound
        }

        // Extract metadata using regex
        func extractMetadata(tag: String) -> String? {
            let pattern = "<dc:\(tag)[^>]*>([^<]+)</dc:\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
               let contentRange = Range(match.range(at: 1), in: xmlString) {
                return String(xmlString[contentRange])
            }
            return nil
        }

        let title = extractMetadata(tag: "title")
        let author = extractMetadata(tag: "creator")
        let publisher = extractMetadata(tag: "publisher")
        let language = extractMetadata(tag: "language")
        let identifier = extractMetadata(tag: "identifier")

        // Count spine items
        let spineCount = xmlString.components(separatedBy: "<itemref").count - 1

        return EPUBInfo(
            chapterCount: spineCount,
            title: title,
            author: author,
            publisher: publisher,
            language: language,
            identifier: identifier
        )
    }
}

// MARK: - Data Types

struct EPUBExtractionResult {
    let text: String
    let chapterCount: Int
    let chaptersWithText: Int
    let chaptersWithoutText: Int
    let totalCharacters: Int
    let quality: ExtractionQuality
}

struct EPUBInfo {
    let chapterCount: Int
    let title: String?
    let author: String?
    let publisher: String?
    let language: String?
    let identifier: String?
}

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
