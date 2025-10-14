//
//  DocumentMigration.swift
//  Index
//
//  Created by Matt on 10/13/2025.
//

import Foundation
import SwiftData
import Observation

/// Service to migrate legacy database-stored documents to file-based storage
@Observable
class DocumentMigration {
    var isMigrating: Bool = false
    var migrationProgress: Double = 0.0
    var processedDocuments: Int = 0
    var totalDocuments: Int = 0

    /// Check if migration is needed and perform it
    func checkAndMigrate(modelContext: ModelContext) async {
        print("🔍 Checking for documents needing migration...")

        do {
            // Find all documents that are not file-backed (legacy documents)
            let descriptor = FetchDescriptor<Document>(
                predicate: #Predicate { doc in
                    doc.isFileBacked == false
                }
            )

            let legacyDocuments = try modelContext.fetch(descriptor)

            guard !legacyDocuments.isEmpty else {
                print("✅ No documents need migration")
                return
            }

            print("📦 Found \(legacyDocuments.count) documents to migrate")

            await MainActor.run {
                isMigrating = true
                totalDocuments = legacyDocuments.count
                processedDocuments = 0
                migrationProgress = 0.0
            }

            // Migrate each document
            for (index, document) in legacyDocuments.enumerated() {
                do {
                    try await migrateDocument(document, modelContext: modelContext)

                    await MainActor.run {
                        processedDocuments = index + 1
                        migrationProgress = Double(index + 1) / Double(totalDocuments)
                    }

                } catch {
                    print("❌ Failed to migrate document \(document.title): \(error)")
                }
            }

            await MainActor.run {
                isMigrating = false
            }

            print("✅ Migration complete: \(legacyDocuments.count) documents migrated")

        } catch {
            print("❌ Migration check failed: \(error)")
            await MainActor.run {
                isMigrating = false
            }
        }
    }

    // MARK: - Private Migration Methods

    private func migrateDocument(_ document: Document, modelContext: ModelContext) async throws {
        print("   📝 Migrating: \(document.title)")

        // Skip if document is already file-backed
        guard !document.isFileBacked else {
            print("      ⚠️ Already migrated, skipping")
            return
        }

        // Get document content from database
        let content = document.content

        // Skip empty documents
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("      ⚠️ Empty document, skipping")
            return
        }

        // Get folder info
        guard let folder = document.folder else {
            print("      ⚠️ No folder assigned, skipping")
            return
        }

        let folderName = folder.iCloudPath ?? folder.name

        // Generate filename from title (sanitize for filesystem)
        let sanitizedTitle = sanitizeFilename(document.title)
        let fileName = "\(sanitizedTitle).md"

        // Create file in iCloud Drive
        do {
            let folderURL = try await FileStorageManager.shared.getFolderURL(folderName: folderName)
            let fileURL = folderURL.appendingPathComponent(fileName)

            // Write content to file
            try await FileStorageManager.shared.writeFile(content: content, to: fileURL)

            // Update document model
            document.fileURL = fileURL
            document.fileName = fileName
            document.isFileBacked = true
            document.content = ""  // Clear database content to save space

            try modelContext.save()

            print("      ✅ Migrated to: \(fileName)")

        } catch {
            print("      ❌ Migration failed: \(error)")
            throw error
        }
    }

    /// Sanitize filename by removing or replacing invalid characters
    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name

        // Replace invalid characters with underscore
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")

        // Trim whitespace and dots from edges
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Limit length to 200 characters
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        // Default to "Untitled" if empty
        if sanitized.isEmpty {
            sanitized = "Untitled"
        }

        return sanitized
    }
}
