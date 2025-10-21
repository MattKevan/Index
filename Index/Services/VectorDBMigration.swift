//
//  VectorDBMigration.swift
//  Index
//
//  Manages one-time migration from VecturaKit to ChromaDB
//

import Foundation
import SwiftData
import Combine

@MainActor
class VectorDBMigration: ObservableObject {
    @Published var isMigrating = false
    @Published var migrationProgress: Double = 0.0
    @Published var currentDocumentTitle = ""
    @Published var totalDocuments = 0
    @Published var processedDocuments = 0

    /// Check if migration is needed
    func migrationNeeded() -> Bool {
        // Check if old VecturaKit directory exists
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vecturaPath = documentsDir.appendingPathComponent("VecturaKit/index-vector-db")

        let exists = FileManager.default.fileExists(atPath: vecturaPath.path)

        if exists {
            print("🔄 VecturaKit database detected at: \(vecturaPath.path)")
            print("   Migration required to ChromaDB")
        }

        return exists
    }

    /// Start migration process
    func startMigration(modelContext: ModelContext) async {
        guard migrationNeeded() else {
            print("ℹ️  No migration needed - VecturaKit database not found")
            return
        }

        print("🔄 Starting migration from VecturaKit to ChromaDB...")

        await MainActor.run {
            isMigrating = true
            migrationProgress = 0.0
        }

        do {
            // Step 1: Fetch all documents that were previously processed
            let descriptor = FetchDescriptor<Document>(
                predicate: #Predicate { document in
                    document.isProcessed == true
                }
            )

            let processedDocs = try modelContext.fetch(descriptor)
            totalDocuments = processedDocs.count

            print("📊 Found \(totalDocuments) documents to migrate")

            if processedDocs.isEmpty {
                print("ℹ️  No documents to migrate")
                await finishMigration()
                return
            }

            // Step 2: Mark all documents as needing re-processing
            // This will trigger ProcessingPipeline to re-embed them with ChromaDB
            for (index, document) in processedDocs.enumerated() {
                document.isProcessed = false
                document.processingStatus = .pending

                // Note: Old chunks and embedding IDs will be replaced automatically
                // during re-processing with ChromaDB

                // Update progress
                processedDocuments = index + 1
                currentDocumentTitle = document.title
                migrationProgress = Double(processedDocuments) / Double(totalDocuments)

                print("   [\(processedDocuments)/\(totalDocuments)] Marked for re-processing: \(document.title)")
            }

            // Save changes
            try modelContext.save()

            print("✅ Migration preparation complete")
            print("   Documents will be re-processed with ChromaDB in the background")

            // Step 3: Trigger automatic processing
            // ProcessingPipeline will handle re-embedding all documents
            Task {
                await ProcessingPipeline.shared.processAllUnprocessedDocuments()
            }

            // Step 4: Clean up old VecturaKit database after a delay
            // Give time for re-processing to start
            try? await Task.sleep(for: .seconds(5))
            await cleanupOldDatabase()

            await finishMigration()

        } catch {
            print("❌ Migration failed: \(error)")
            await MainActor.run {
                isMigrating = false
            }
        }
    }

    /// Clean up old VecturaKit database
    private func cleanupOldDatabase() async {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vecturaPath = documentsDir.appendingPathComponent("VecturaKit")

        print("🗑️ Cleaning up old VecturaKit database...")
        print("   Path: \(vecturaPath.path)")

        do {
            if FileManager.default.fileExists(atPath: vecturaPath.path) {
                try FileManager.default.removeItem(at: vecturaPath)
                print("✅ Old VecturaKit database removed")

                // Calculate freed space
                let attributes = try FileManager.default.attributesOfItem(atPath: vecturaPath.path)
                if let size = attributes[.size] as? UInt64 {
                    let sizeInMB = Double(size) / 1_048_576
                    print("   Freed ~\(String(format: "%.1f", sizeInMB))MB of storage")
                }
            } else {
                print("ℹ️  VecturaKit database already removed")
            }
        } catch {
            print("⚠️ Failed to remove old database: \(error)")
            print("   You can manually delete: \(vecturaPath.path)")
        }
    }

    /// Mark migration as complete
    private func finishMigration() async {
        print("✅ Migration to ChromaDB complete!")

        await MainActor.run {
            isMigrating = false
            migrationProgress = 1.0
        }

        // Store migration flag to prevent future checks
        UserDefaults.standard.set(true, forKey: "hasMigratedToChromaDB")
    }

    /// Check if migration has already been completed
    func hasMigratedPreviously() -> Bool {
        return UserDefaults.standard.bool(forKey: "hasMigratedToChromaDB")
    }

    /// Trigger migration check and start if needed
    func checkAndMigrate(modelContext: ModelContext) async {
        // Skip if already migrated
        guard !hasMigratedPreviously() else {
            print("ℹ️  Migration already completed previously")
            return
        }

        // Check if migration needed and start
        if migrationNeeded() {
            await startMigration(modelContext: modelContext)
        } else {
            // No migration needed, mark as complete to skip future checks
            UserDefaults.standard.set(true, forKey: "hasMigratedToChromaDB")
        }
    }
}
