//
//  DocumentImporter.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Actor-isolated service for importing documents of various types
actor DocumentImporter {
    static let shared = DocumentImporter()

    private let fileStorage = FileStorageManager.shared
    private let pdfExtractor = PDFTextExtractor.shared
    private let epubExtractor = EPUBTextExtractor.shared

    private init() {}

    // MARK: - Import Methods

    /// Import a document file that's already in iCloud (used by FileSync)
    /// - Parameters:
    ///   - iCloudURL: URL of the file already in iCloud
    ///   - folder: Target folder for the document
    ///   - context: SwiftData model context
    /// - Returns: Created Document model
    /// - Throws: ImportError if import fails
    func importExistingFile(from iCloudURL: URL, toFolder folder: Folder, context: ModelContext) async throws -> Document {
        // Detect document type
        let documentType = try detectDocumentType(for: iCloudURL)

        guard documentType == .pdf || documentType == .epub else {
            throw ImportError.unsupportedFileType(message: "Only PDF and EPUB files are currently supported. DOCX support coming soon.")
        }

        // Generate unique title from filename
        let title = iCloudURL.deletingPathExtension().lastPathComponent

        print("📥 Processing existing \(documentType.rawValue.uppercased()) in iCloud: \(title)")

        // File is already in iCloud, just use it as-is
        let originalFileName = iCloudURL.lastPathComponent
        let originalFileURL = iCloudURL

        // Extract text and metadata based on document type
        let extractedText: String
        var metadata: EPUBMetadata? = nil

        switch documentType {
        case .pdf:
            extractedText = try await pdfExtractor.extractText(from: iCloudURL)
        case .epub:
            let result = try await epubExtractor.extractTextAndMetadata(from: iCloudURL)
            extractedText = result.text
            metadata = result.metadata
            print("📚 EPUB Metadata:")
            if let title = metadata?.title { print("   Title: \(title)") }
            if let author = metadata?.author { print("   Author: \(author)") }
            if let publisher = metadata?.publisher { print("   Publisher: \(publisher)") }
            if let description = metadata?.description { print("   Description: \(description.prefix(100))...") }
        case .docx:
            throw ImportError.unsupportedFileType(message: "DOCX support coming in Phase 2")
        case .markdown, .plainText:
            throw ImportError.unsupportedFileType(message: "Use the 'New Document' button for markdown files")
        }

        // Create extracted text file in iCloud
        let extractedFileName = "\(title).md"
        let extractedTextURL = try await createExtractedTextFile(
            content: extractedText,
            fileName: extractedFileName,
            folderName: folder.name
        )

        print("✅ Created extracted text file: \(extractedTextURL.path)")

        // Create Document model
        let document = Document(
            title: title,
            documentType: documentType,
            originalFileURL: originalFileURL,
            originalFileName: originalFileName,
            extractedTextURL: extractedTextURL,
            extractedTextFileName: extractedFileName,
            folder: folder
        )

        // Set metadata fields if available
        if let metadata = metadata {
            document.author = metadata.author
            document.publisher = metadata.publisher
            document.language = metadata.language

            // Use EPUB description as initial summary if available (strip HTML)
            if let description = metadata.description {
                let cleanSummary = stripHTMLTags(from: description)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !cleanSummary.isEmpty {
                    document.summary = cleanSummary
                    print("✅ Using EPUB description as summary: \(cleanSummary.prefix(100))...")
                }
            }
        }

        // Add to context
        context.insert(document)

        // Save context
        try context.save()

        print("✅ Document processed successfully: \(title)")

        return document
    }

    /// Import a document file into the specified folder
    /// - Parameters:
    ///   - sourceURL: URL of the file to import
    ///   - folder: Target folder for the document
    ///   - context: SwiftData model context
    /// - Returns: Created Document model
    /// - Throws: ImportError if import fails
    func importDocument(from sourceURL: URL, toFolder folder: Folder, context: ModelContext) async throws -> Document {
        // Detect document type
        let documentType = try detectDocumentType(for: sourceURL)

        guard documentType == .pdf || documentType == .epub else {
            throw ImportError.unsupportedFileType(message: "Only PDF and EPUB files are currently supported. DOCX support coming soon.")
        }

        // Generate unique title from filename
        let title = sourceURL.deletingPathExtension().lastPathComponent

        print("📥 Importing \(documentType.rawValue.uppercased()): \(title)")

        // Copy original file to iCloud
        let originalFileName = sourceURL.lastPathComponent
        let originalFileURL = try await fileStorage.copyFileToiCloud(
            from: sourceURL,
            toFolder: folder.name,
            fileName: originalFileName
        )

        print("✅ Copied original file to iCloud: \(originalFileURL.path)")

        // Extract text and metadata based on document type
        let extractedText: String
        var metadata: EPUBMetadata? = nil

        switch documentType {
        case .pdf:
            extractedText = try await pdfExtractor.extractText(from: sourceURL)
        case .epub:
            let result = try await epubExtractor.extractTextAndMetadata(from: sourceURL)
            extractedText = result.text
            metadata = result.metadata
            print("📚 EPUB Metadata:")
            if let title = metadata?.title { print("   Title: \(title)") }
            if let author = metadata?.author { print("   Author: \(author)") }
            if let publisher = metadata?.publisher { print("   Publisher: \(publisher)") }
            if let description = metadata?.description { print("   Description: \(description.prefix(100))...") }
        case .docx:
            throw ImportError.unsupportedFileType(message: "DOCX support coming in Phase 2")
        case .markdown, .plainText:
            throw ImportError.unsupportedFileType(message: "Use the 'New Document' button for markdown files")
        }

        // Create extracted text file in iCloud
        let extractedFileName = "\(title).md"
        let extractedTextURL = try await createExtractedTextFile(
            content: extractedText,
            fileName: extractedFileName,
            folderName: folder.name
        )

        print("✅ Created extracted text file: \(extractedTextURL.path)")

        // Create Document model
        let document = Document(
            title: title,
            documentType: documentType,
            originalFileURL: originalFileURL,
            originalFileName: originalFileName,
            extractedTextURL: extractedTextURL,
            extractedTextFileName: extractedFileName,
            folder: folder
        )

        // Set metadata fields if available
        if let metadata = metadata {
            document.author = metadata.author
            document.publisher = metadata.publisher
            document.language = metadata.language

            // Use EPUB description as initial summary if available (strip HTML)
            if let description = metadata.description {
                let cleanSummary = stripHTMLTags(from: description)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !cleanSummary.isEmpty {
                    document.summary = cleanSummary
                    print("✅ Using EPUB description as summary: \(cleanSummary.prefix(100))...")
                }
            }
        }

        // Add to context
        context.insert(document)

        // Save context
        try context.save()

        print("✅ Document imported successfully: \(title)")

        return document
    }

    /// Import multiple documents in batch
    /// - Parameters:
    ///   - sourceURLs: Array of file URLs to import
    ///   - folder: Target folder for all documents
    ///   - context: SwiftData model context
    /// - Returns: Array of created documents and any errors
    func importDocuments(from sourceURLs: [URL], toFolder folder: Folder, context: ModelContext) async -> (documents: [Document], errors: [(URL, Error)]) {
        var documents: [Document] = []
        var errors: [(URL, Error)] = []

        for sourceURL in sourceURLs {
            do {
                let document = try await importDocument(from: sourceURL, toFolder: folder, context: context)
                documents.append(document)
            } catch {
                errors.append((sourceURL, error))
                print("❌ Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return (documents, errors)
    }

    // MARK: - File Type Detection

    /// Detect document type from file URL using UTType
    /// - Parameter url: File URL to analyze
    /// - Returns: Detected DocumentType
    /// - Throws: ImportError if file type cannot be determined
    private func detectDocumentType(for url: URL) throws -> DocumentType {
        // Get UTType from file extension
        let fileExtension = url.pathExtension.lowercased()

        // Check by extension first (more reliable)
        switch fileExtension {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "docx":
            return .docx
        case "md", "markdown":
            return .markdown
        case "txt":
            return .plainText
        default:
            break
        }

        // Fallback to UTType checking
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            throw ImportError.unknownFileType
        }

        if contentType.conforms(to: .pdf) {
            return .pdf
        } else if contentType.identifier == "org.idpf.epub-container" || contentType.identifier == "public.epub" {
            return .epub
        } else if contentType.conforms(to: UTType(filenameExtension: "docx") ?? .data) {
            return .docx
        } else if contentType.conforms(to: .plainText) {
            return .plainText
        } else {
            throw ImportError.unsupportedFileType(message: "File type not supported: \(contentType.identifier)")
        }
    }

    // MARK: - Text Extraction

    /// Create extracted text file in iCloud
    /// - Parameters:
    ///   - content: Extracted text content
    ///   - fileName: Name for the extracted text file
    ///   - folderName: iCloud folder name
    /// - Returns: URL to the created file
    private func createExtractedTextFile(content: String, fileName: String, folderName: String) async throws -> URL {
        let folderURL = try await fileStorage.getFolderURL(folderName: folderName)
        let fileURL = folderURL.appendingPathComponent(fileName)

        // Write content to file
        try await fileStorage.writeFile(content: content, to: fileURL)

        return fileURL
    }

    // MARK: - Validation

    /// Check if a file can be imported
    /// - Parameter url: File URL to check
    /// - Returns: True if file can be imported
    func canImport(url: URL) async -> Bool {
        do {
            let documentType = try detectDocumentType(for: url)
            // Currently only PDF is supported
            return documentType == .pdf
        } catch {
            return false
        }
    }

    /// Get supported file types for file picker
    /// - Returns: Array of UTTypes that can be imported
    static func supportedUTTypes() -> [UTType] {
        return [
            .pdf,
            UTType(filenameExtension: "epub") ?? .data,
            // Future support:
            // UTType(filenameExtension: "docx") ?? .data
        ]
    }

    /// Get human-readable list of supported formats
    /// - Returns: String describing supported formats
    static func supportedFormatsDescription() -> String {
        return "PDF and EPUB documents"
        // Future: "PDF, EPUB, and DOCX documents"
    }

    // MARK: - Helpers

    /// Strip HTML tags from text
    /// - Parameter html: HTML text
    /// - Returns: Plain text with HTML tags removed
    private func stripHTMLTags(from html: String) -> String {
        var text = html

        // Remove all HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Decode common HTML entities
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
            "&hellip;": "…"
        ]

        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Replace multiple whitespaces/newlines with single space
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Types

enum ImportError: Error, LocalizedError {
    case unknownFileType
    case unsupportedFileType(message: String)
    case extractionFailed(message: String)
    case fileAccessDenied
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .unknownFileType:
            return "Could not determine the file type."
        case .unsupportedFileType(let message):
            return message
        case .extractionFailed(let message):
            return "Text extraction failed: \(message)"
        case .fileAccessDenied:
            return "Permission denied to access the file."
        case .iCloudUnavailable:
            return "iCloud Drive is not available."
        }
    }
}
