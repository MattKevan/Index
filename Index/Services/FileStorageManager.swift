//
//  FileStorageManager.swift
//  Index
//
//  Created by Matt on 10/13/2025.
//

import Foundation
import SwiftData

/// Actor-isolated service managing file operations with iCloud Drive
actor FileStorageManager {
    static let shared = FileStorageManager()

    private let fileManager = FileManager.default
    private let fileCoordinator = NSFileCoordinator()

    /// Base iCloud Drive folder URL (user-accessible)
    /// Uses ubiquity container which will appear as "Index" folder in Finder's iCloud Drive
    private var iCloudContainerURL: URL? {
        // Try default container first (nil = use bundle ID based container from entitlements)
        if let ubiquityURL = fileManager.url(forUbiquityContainerIdentifier: nil) {
            let documentsURL = ubiquityURL.appendingPathComponent("Documents")
            print("📁 iCloud ubiquity container (default): \(ubiquityURL.path)")
            print("📁 Documents folder: \(documentsURL.path)")
            return documentsURL
        }

        // Try explicit lowercase container
        if let ubiquityURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.newindustries.index") {
            let documentsURL = ubiquityURL.appendingPathComponent("Documents")
            print("📁 iCloud ubiquity container (explicit): \(ubiquityURL.path)")
            print("📁 Documents folder: \(documentsURL.path)")
            return documentsURL
        }

        print("❌ iCloud Drive not available - tried default and explicit containers")
        return nil
    }

    /// Check if iCloud Drive is available
    var isAvailable: Bool {
        get async {
            iCloudContainerURL != nil
        }
    }

    private init() {
        Task {
            await initializeRootFolder()
        }
    }

    // MARK: - Initialization

    /// Create the root "Index" folder in iCloud Drive if it doesn't exist
    private func initializeRootFolder() async {
        guard let rootURL = iCloudContainerURL else {
            print("⚠️ iCloud Drive not available")
            return
        }

        do {
            if !fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                print("✅ Created Index folder in iCloud Drive at: \(rootURL.path)")
            } else {
                print("📁 Index folder already exists in iCloud Drive")
            }
        } catch {
            print("❌ Failed to create Index folder: \(error)")
        }
    }

    // MARK: - Folder Operations

    /// Get or create folder URL for a given folder name
    func getFolderURL(folderName: String) async throws -> URL {
        guard let rootURL = iCloudContainerURL else {
            throw FileStorageError.iCloudUnavailable
        }

        let folderURL = rootURL.appendingPathComponent(folderName)

        // Create folder if it doesn't exist
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            print("📁 Created folder: \(folderName)")
        }

        return folderURL
    }

    /// Rename a folder in iCloud Drive
    func renameFolder(oldName: String, newName: String) async throws {
        guard let rootURL = iCloudContainerURL else {
            throw FileStorageError.iCloudUnavailable
        }

        let oldURL = rootURL.appendingPathComponent(oldName)
        let newURL = rootURL.appendingPathComponent(newName)

        guard fileManager.fileExists(atPath: oldURL.path) else {
            print("⚠️ Folder doesn't exist: \(oldName)")
            return
        }

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: oldURL, options: .forMoving,
                                   writingItemAt: newURL, options: .forReplacing,
                                   error: &error) { oldActualURL, newActualURL in
            do {
                try fileManager.moveItem(at: oldActualURL, to: newActualURL)
                print("✅ Renamed folder: \(oldName) → \(newName)")
            } catch {
                print("❌ Failed to rename folder: \(error)")
            }
        }

        if let error = error {
            throw error
        }
    }

    /// Delete a folder from iCloud Drive (moves to trash)
    func deleteFolder(folderName: String) async throws {
        guard let rootURL = iCloudContainerURL else {
            throw FileStorageError.iCloudUnavailable
        }

        let folderURL = rootURL.appendingPathComponent(folderName)

        guard fileManager.fileExists(atPath: folderURL.path) else {
            print("⚠️ Folder doesn't exist: \(folderName)")
            return
        }

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: folderURL, options: .forDeleting, error: &error) { actualURL in
            do {
                try fileManager.trashItem(at: actualURL, resultingItemURL: nil)
                print("🗑️ Moved folder to trash: \(folderName)")
            } catch {
                print("❌ Failed to delete folder: \(error)")
            }
        }

        if let error = error {
            throw error
        }
    }

    // MARK: - File Operations

    /// Copy a file to iCloud Drive folder
    func copyFileToiCloud(from sourceURL: URL, toFolder folderName: String, fileName: String) async throws -> URL {
        let folderURL = try await getFolderURL(folderName: folderName)
        let destinationURL = folderURL.appendingPathComponent(fileName)

        // If file already exists, make it unique
        let uniqueDestinationURL = makeUniqueURL(destinationURL)

        var error: NSError?
        fileCoordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges,
                                   writingItemAt: uniqueDestinationURL, options: .forReplacing,
                                   error: &error) { actualSourceURL, actualDestinationURL in
            do {
                try fileManager.copyItem(at: actualSourceURL, to: actualDestinationURL)
                print("✅ Copied file to iCloud: \(fileName)")
            } catch {
                print("❌ Failed to copy file: \(error)")
            }
        }

        if let error = error {
            throw error
        }

        return uniqueDestinationURL
    }

    /// Read content from a file in iCloud Drive
    func readFile(at fileURL: URL) async throws -> String {
        var content: String?
        var readError: Error?

        var coordinatorError: NSError?
        fileCoordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { actualURL in
            do {
                content = try String(contentsOf: actualURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        if let coordinatorError = coordinatorError {
            throw coordinatorError
        }

        if let readError = readError {
            throw readError
        }

        guard let content = content else {
            throw FileStorageError.readFailed
        }

        return content
    }

    /// Write content to a file in iCloud Drive
    func writeFile(content: String, to fileURL: URL) async throws {
        var writeError: Error?

        var coordinatorError: NSError?
        fileCoordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { actualURL in
            do {
                try content.write(to: actualURL, atomically: true, encoding: .utf8)
                print("✅ Wrote file: \(fileURL.lastPathComponent)")
            } catch {
                writeError = error
            }
        }

        if let coordinatorError = coordinatorError {
            throw coordinatorError
        }

        if let writeError = writeError {
            throw writeError
        }
    }

    /// Delete a file from iCloud Drive (moves to trash)
    func deleteFile(at fileURL: URL) async throws {
        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &error) { actualURL in
            do {
                try fileManager.trashItem(at: actualURL, resultingItemURL: nil)
                print("🗑️ Moved file to trash: \(fileURL.lastPathComponent)")
            } catch {
                print("❌ Failed to delete file: \(error)")
            }
        }

        if let error = error {
            throw error
        }
    }

    /// Move a file to a different folder
    func moveFile(from sourceURL: URL, toFolder folderName: String) async throws -> URL {
        let folderURL = try await getFolderURL(folderName: folderName)
        let fileName = sourceURL.lastPathComponent
        let destinationURL = folderURL.appendingPathComponent(fileName)

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: sourceURL, options: .forMoving,
                                   writingItemAt: destinationURL, options: .forReplacing,
                                   error: &error) { actualSourceURL, actualDestinationURL in
            do {
                try fileManager.moveItem(at: actualSourceURL, to: actualDestinationURL)
                print("✅ Moved file: \(fileName) → \(folderName)")
            } catch {
                print("❌ Failed to move file: \(error)")
            }
        }

        if let error = error {
            throw error
        }

        return destinationURL
    }

    // MARK: - Reconciliation

    /// Scan iCloud folder and return all files with their metadata
    func scanFolder(folderName: String) async throws -> [FileMetadata] {
        let folderURL = try await getFolderURL(folderName: folderName)

        guard fileManager.fileExists(atPath: folderURL.path) else {
            return []
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )

        var metadata: [FileMetadata] = []

        for fileURL in fileURLs where fileURL.pathExtension == "md" {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

                metadata.append(FileMetadata(
                    url: fileURL,
                    fileName: fileURL.lastPathComponent,
                    modificationDate: resourceValues.contentModificationDate ?? Date(),
                    fileSize: resourceValues.fileSize ?? 0
                ))
            } catch {
                print("⚠️ Failed to get metadata for \(fileURL.lastPathComponent): \(error)")
            }
        }

        return metadata
    }

    /// Scan all folders in iCloud Drive
    func scanAllFolders() async throws -> [String: [FileMetadata]] {
        guard let rootURL = iCloudContainerURL else {
            throw FileStorageError.iCloudUnavailable
        }

        guard fileManager.fileExists(atPath: rootURL.path) else {
            return [:]
        }

        let folderURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        var allMetadata: [String: [FileMetadata]] = [:]

        for folderURL in folderURLs {
            let resourceValues = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                let folderName = folderURL.lastPathComponent
                let files = try await scanFolder(folderName: folderName)
                allMetadata[folderName] = files
            }
        }

        return allMetadata
    }

    // MARK: - Utilities

    /// Make a URL unique by appending a number if it already exists
    private func makeUniqueURL(_ url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var counter = 1
        var uniqueURL = url

        while fileManager.fileExists(atPath: uniqueURL.path) {
            let newFileName = "\(fileName) \(counter).\(fileExtension)"
            uniqueURL = directory.appendingPathComponent(newFileName)
            counter += 1
        }

        return uniqueURL
    }
}

// MARK: - Data Types

struct FileMetadata: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let modificationDate: Date
    let fileSize: Int
}

enum FileStorageError: Error, LocalizedError {
    case iCloudUnavailable
    case readFailed
    case writeFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Please enable iCloud Drive in System Settings."
        case .readFailed:
            return "Failed to read file from iCloud Drive."
        case .writeFailed:
            return "Failed to write file to iCloud Drive."
        case .fileNotFound:
            return "File not found in iCloud Drive."
        }
    }
}
