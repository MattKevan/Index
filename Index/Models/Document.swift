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

    // Store content as Markdown string for compatibility and simplicity
    // AttributedString will be computed on-the-fly for editing
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
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isProcessed = false
        self.processingStatus = .pending
        self.folder = folder
        self.versions = []
    }

    /// Get plain text content (strips Markdown formatting for embeddings)
    var plainTextContent: String {
        // Strip common Markdown syntax for cleaner embeddings
        var plainText = content

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

enum ProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}
