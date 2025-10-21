//
//  DocumentVersion.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftData
import Foundation

@Model
final class DocumentVersion {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var versionType: VersionType
    var prompt: String? // For AI-generated versions

    // Transformation-specific fields
    var transformationPrompt: String? // The transformation template/instructions
    var contentHash: String? // Hash of source content when this was created
    var createdFromHash: String? // For cache invalidation

    @Relationship
    var document: Document?

    init(content: String, versionType: VersionType, prompt: String? = nil, transformationPrompt: String? = nil, contentHash: String? = nil) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.versionType = versionType
        self.prompt = prompt
        self.transformationPrompt = transformationPrompt
        self.contentHash = contentHash
        self.createdFromHash = contentHash
    }
}

enum VersionType: String, Codable {
    case original
    case aiRewritten
    case aiSummary

    // Document transformation types
    case executiveSummary
    case article
    case flashcards
    case studyNotes
    case customTransformation
}
