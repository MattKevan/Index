//
//  FileSync.swift
//  Index
//
//  Created by Matt on 10/13/2025.
//

import Foundation
import SwiftData

/// Service to reconcile iCloud Drive changes with the app's database
/// Uses reactive approach - syncs on app activation, folder navigation, etc.
actor FileSync {
    static let shared = FileSync()

    private init() {}

    /// Reconcile all folders - detect new files, deleted files, and modifications
    func reconcileAllFolders(modelContext: ModelContext) async {
        print("🔄 Starting file sync reconciliation...")

        do {
            // Get all folders from database
            let folderDescriptor = FetchDescriptor<Folder>()
            let folders = try modelContext.fetch(folderDescriptor)

            print("   Checking \(folders.count) folders for changes")

            for folder in folders {
                await reconcileFolder(folder, modelContext: modelContext)
            }

            // Also check for new folders in iCloud that aren't in the database
            await discoverNewFolders(modelContext: modelContext)

            print("✅ File sync reconciliation complete")

        } catch {
            print("❌ Reconciliation failed: \(error)")
        }
    }

    /// Reconcile a specific folder
    func reconcileFolder(_ folder: Folder, modelContext: ModelContext) async {
        guard let folderName = folder.iCloudPath else {
            print("⚠️ Folder has no iCloud path: \(folder.name)")
            return
        }

        do {
            // Scan files in iCloud folder
            let filesInCloud = try await FileStorageManager.shared.scanFolder(folderName: folderName)

            // Get documents in database for this folder
            let folderID = folder.id
            let documentDescriptor = FetchDescriptor<Document>(
                predicate: #Predicate<Document> { doc in
                    if let docFolder = doc.folder {
                        docFolder.id == folderID
                    } else {
                        false
                    }
                }
            )
            let documentsInDB = try modelContext.fetch(documentDescriptor)

            print("   📁 \(folder.name): \(filesInCloud.count) files in iCloud, \(documentsInDB.count) in database")

            // Check for new files (in iCloud but not in database)
            await checkForNewFiles(filesInCloud: filesInCloud, documentsInDB: documentsInDB, folder: folder, modelContext: modelContext)

            // Check for deleted files (in database but not in iCloud)
            await checkForDeletedFiles(filesInCloud: filesInCloud, documentsInDB: documentsInDB, modelContext: modelContext)

            // Check for modified files (compare modification dates)
            await checkForModifiedFiles(filesInCloud: filesInCloud, documentsInDB: documentsInDB, modelContext: modelContext)

        } catch {
            print("❌ Failed to reconcile folder \(folder.name): \(error)")
        }
    }

    // MARK: - Private Reconciliation Methods

    private func checkForNewFiles(
        filesInCloud: [FileMetadata],
        documentsInDB: [Document],
        folder: Folder,
        modelContext: ModelContext
    ) async {
        // Create a set of filenames that exist in the database
        let dbFileNames = Set(documentsInDB.compactMap { $0.fileName })

        // Find files in iCloud that aren't in the database
        let newFiles = filesInCloud.filter { !dbFileNames.contains($0.fileName) }

        if !newFiles.isEmpty {
            print("   ➕ Found \(newFiles.count) new files")

            for fileMetadata in newFiles {
                // Create new document for this file
                let title = fileMetadata.url.deletingPathExtension().lastPathComponent

                let document = Document(
                    title: title,
                    fileURL: fileMetadata.url,
                    fileName: fileMetadata.fileName,
                    folder: folder
                )

                modelContext.insert(document)
                print("      • Added: \(fileMetadata.fileName)")

                // Trigger processing
                try? modelContext.save()
                let documentID = document.persistentModelID
                Task.detached(priority: .utility) {
                    await ProcessingPipeline.shared.processDocument(documentID: documentID, cancellationToken: nil)
                }
            }

            try? modelContext.save()
        }
    }

    private func checkForDeletedFiles(
        filesInCloud: [FileMetadata],
        documentsInDB: [Document],
        modelContext: ModelContext
    ) async {
        // Create a set of filenames that exist in iCloud
        let cloudFileNames = Set(filesInCloud.map { $0.fileName })

        // Find file-backed documents in database that aren't in iCloud
        let deletedDocuments = documentsInDB.filter { doc in
            doc.isFileBacked && doc.fileName != nil && !cloudFileNames.contains(doc.fileName!)
        }

        if !deletedDocuments.isEmpty {
            print("   ➖ Found \(deletedDocuments.count) deleted files")

            for document in deletedDocuments {
                print("      • Removed: \(document.fileName ?? "unknown")")
                modelContext.delete(document)
            }

            try? modelContext.save()
        }
    }

    private func checkForModifiedFiles(
        filesInCloud: [FileMetadata],
        documentsInDB: [Document],
        modelContext: ModelContext
    ) async {
        // Create a map of filename to metadata
        let cloudFileMap = Dictionary(uniqueKeysWithValues: filesInCloud.map { ($0.fileName, $0) })

        var modifiedCount = 0

        for document in documentsInDB where document.isFileBacked {
            guard let fileName = document.fileName,
                  let cloudFile = cloudFileMap[fileName] else {
                continue
            }

            // Compare modification dates
            if cloudFile.modificationDate > document.modifiedAt {
                // File was modified externally
                document.modifiedAt = cloudFile.modificationDate
                document.isProcessed = false
                document.processingStatus = .pending

                modifiedCount += 1
                print("      • Modified: \(fileName)")

                // Trigger reprocessing
                let documentID = document.persistentModelID
                Task.detached(priority: .utility) {
                    await ProcessingPipeline.shared.processDocument(documentID: documentID, cancellationToken: nil)
                }
            }
        }

        if modifiedCount > 0 {
            print("   🔄 Found \(modifiedCount) modified files")
            try? modelContext.save()
        }
    }

    private func discoverNewFolders(modelContext: ModelContext) async {
        do {
            // Scan all folders in iCloud Drive
            let foldersInCloud = try await FileStorageManager.shared.scanAllFolders()

            // Get existing folders from database
            let folderDescriptor = FetchDescriptor<Folder>()
            let foldersInDB = try modelContext.fetch(folderDescriptor)
            let dbFolderNames = Set(foldersInDB.compactMap { $0.iCloudPath })

            // Find folders in iCloud that aren't in the database
            let newFolderNames = Set(foldersInCloud.keys).subtracting(dbFolderNames)

            if !newFolderNames.isEmpty {
                print("   📁 Found \(newFolderNames.count) new folders in iCloud")

                for folderName in newFolderNames {
                    let folder = Folder(name: folderName, sortOrder: foldersInDB.count)
                    folder.iCloudPath = folderName
                    modelContext.insert(folder)
                    print("      • Added folder: \(folderName)")

                    // Reconcile files in this new folder
                    await reconcileFolder(folder, modelContext: modelContext)
                }

                try? modelContext.save()
            }

        } catch {
            print("❌ Failed to discover new folders: \(error)")
        }
    }
}
