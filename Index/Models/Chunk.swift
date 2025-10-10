//
//  Chunk.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftData
import Foundation

@Model
final class Chunk {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var content: String
    var chunkIndex: Int
    var startOffset: Int
    var endOffset: Int
    var embeddingID: String? // Reference to VecturaKit

    init(documentID: UUID, content: String, chunkIndex: Int, startOffset: Int, endOffset: Int) {
        self.id = UUID()
        self.documentID = documentID
        self.content = content
        self.chunkIndex = chunkIndex
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}
