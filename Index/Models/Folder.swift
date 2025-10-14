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

    // iCloud Drive path component (relative to Index root folder)
    // For folder named "Notes", iCloudPath would be "Notes"
    var iCloudPath: String?

    @Relationship(deleteRule: .cascade, inverse: \Document.folder)
    var documents: [Document]

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.documents = []
        // iCloudPath will match folder name by default
        self.iCloudPath = name
    }

    // MARK: - iCloud Integration

    /// Get the full iCloud Drive URL for this folder
    func getICloudURL() async throws -> URL {
        guard let folderName = iCloudPath else {
            // Fallback to folder name if iCloudPath not set
            return try await FileStorageManager.shared.getFolderURL(folderName: name)
        }
        return try await FileStorageManager.shared.getFolderURL(folderName: folderName)
    }

    /// Sync folder name change to iCloud Drive
    func syncNameToiCloud(oldName: String) async throws {
        guard let iCloudPath = iCloudPath else { return }

        // If iCloud path differs from old name, rename the folder
        if iCloudPath == oldName && oldName != name {
            try await FileStorageManager.shared.renameFolder(oldName: oldName, newName: name)
            self.iCloudPath = name
        }
    }
}
