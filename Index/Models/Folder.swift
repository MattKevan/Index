//
//  Folder.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftData
import Foundation

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \Document.folder)
    var documents: [Document]

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.documents = []
    }
}
