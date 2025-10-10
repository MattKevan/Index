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

    @Relationship
    var document: Document?

    init(content: String, versionType: VersionType, prompt: String? = nil) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.versionType = versionType
        self.prompt = prompt
    }
}

enum VersionType: String, Codable {
    case original
    case aiRewritten
    case aiSummary
}
