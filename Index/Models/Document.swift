//
//  Document.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftData
import Foundation

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
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
}

enum ProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}
