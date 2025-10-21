//
//  Document.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftData
import Foundation
import SwiftUI
import CryptoKit

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String

    // Document type (optional for backward compatibility with existing documents)
    // Defaults to markdown for legacy documents without this field
    var documentType: DocumentType?

    // File-based storage properties
    var fileURL: URL?       // Extracted/working text file (markdown format for all types)
    var fileName: String?
    var isFileBacked: Bool = false  // true = content in file, false = content in database (legacy)

    // Imported document properties (for PDF/EPUB/DOCX)
    var originalFileURL: URL?     // Original imported file (PDF/EPUB/DOCX)
    var originalFileName: String? // Original file name with extension

    // Computed property to get document type with fallback
    var effectiveDocumentType: DocumentType {
        return documentType ?? .markdown
    }

    // Legacy: Store content as Markdown string for backward compatibility
    // For file-backed documents, this will be empty/ignored
    var content: String

    // AI-generated one-sentence summary for document list preview
    var summary: String?

    // Hash of content when last rendered (for cache invalidation)
    var contentHash: String?

    var createdAt: Date
    var modifiedAt: Date
    var isProcessed: Bool
    var processingStatus: ProcessingStatus

    @Relationship
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \DocumentVersion.document)
    var versions: [DocumentVersion]

    init(title: String, content: String = "", folder: Folder? = nil) {
        self.id = UUID()
        self.title = title
        self.documentType = .markdown
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isProcessed = false
        self.processingStatus = .pending
        self.folder = folder
        self.versions = []
        self.isFileBacked = false
    }

    /// Initialize with file-based storage (for markdown documents)
    init(title: String, fileURL: URL, fileName: String, folder: Folder? = nil) {
        self.id = UUID()
        self.title = title
        self.documentType = .markdown
        self.fileURL = fileURL
        self.fileName = fileName
        self.isFileBacked = true
        self.content = ""  // Empty for file-backed documents
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isProcessed = false
        self.processingStatus = .pending
        self.folder = folder
        self.versions = []
    }

    /// Initialize with imported document (PDF/EPUB/DOCX)
    /// - Parameters:
    ///   - title: Document title
    ///   - documentType: Type of imported document
    ///   - originalFileURL: URL to original imported file
    ///   - originalFileName: Name of original file with extension
    ///   - extractedTextURL: URL to extracted text file (markdown format)
    ///   - extractedTextFileName: Name of extracted text file
    ///   - folder: Parent folder
    init(title: String,
         documentType: DocumentType,
         originalFileURL: URL,
         originalFileName: String,
         extractedTextURL: URL,
         extractedTextFileName: String,
         folder: Folder? = nil) {
        self.id = UUID()
        self.title = title
        self.documentType = documentType
        self.originalFileURL = originalFileURL
        self.originalFileName = originalFileName
        self.fileURL = extractedTextURL
        self.fileName = extractedTextFileName
        self.isFileBacked = true
        self.content = ""  // Empty for file-backed documents
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isProcessed = false
        self.processingStatus = .pending
        self.folder = folder
        self.versions = []
    }

    // MARK: - File Operations

    /// Load content from file (for file-backed documents)
    func loadContent() async throws -> String {
        guard isFileBacked, let fileURL = fileURL else {
            // Legacy document - return database content
            return content
        }

        return try await FileStorageManager.shared.readFile(at: fileURL)
    }

    /// Save content to file (for file-backed documents)
    func saveContent(_ newContent: String) async throws {
        guard isFileBacked, let fileURL = fileURL else {
            // Legacy document - update database content directly
            content = newContent
            return
        }

        try await FileStorageManager.shared.writeFile(content: newContent, to: fileURL)
    }

    /// Get content synchronously (for immediate access, may be stale for file-backed documents)
    func getContentSync() -> String {
        if isFileBacked {
            // File-backed: content property is empty, need async load
            // Return empty string - caller should use async loadContent() instead
            return ""
        } else {
            // Legacy: return database content
            return content
        }
    }

    // MARK: - Plain Text

    /// Get plain text content (strips Markdown formatting for embeddings)
    var plainTextContent: String {
        // For file-backed documents, this will be empty
        // Callers should use async version if needed
        let rawContent = getContentSync()

        // Strip common Markdown syntax for cleaner embeddings
        var plainText = rawContent

        // Remove heading markers
        plainText = plainText.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)

        // Remove bold/italic markers
        plainText = plainText.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"__(.+?)__"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"_(.+?)_"#, with: "$1", options: .regularExpression)

        // Remove inline code markers
        plainText = plainText.replacingOccurrences(of: #"`(.+?)`"#, with: "$1", options: .regularExpression)

        // Remove link syntax but keep text
        plainText = plainText.replacingOccurrences(of: #"\[(.+?)\]\(.+?\)"#, with: "$1", options: .regularExpression)

        // Remove image syntax
        plainText = plainText.replacingOccurrences(of: #"!\[.*?\]\(.+?\)"#, with: "", options: .regularExpression)

        // Remove list markers
        plainText = plainText.replacingOccurrences(of: #"^[\*\-\+]\s+"#, with: "", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)

        // Remove blockquote markers
        plainText = plainText.replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)

        return plainText
    }

    /// Calculate SHA256 hash of content for cache invalidation
    func calculateContentHash() -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Check if cached render is still valid
    var isCacheValid: Bool {
        guard let cachedHash = contentHash else { return false }
        return cachedHash == calculateContentHash()
    }
}

// MARK: - Document Types

enum DocumentType: String, Codable {
    case markdown   // Native markdown documents (default)
    case pdf        // Imported PDF files
    case epub       // Imported EPUB e-books
    case docx       // Imported Microsoft Word documents
    case plainText  // Plain text files
}

enum ProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}
