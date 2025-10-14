//
//  DocumentListView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    let folder: Folder
    @Binding var selectedDocument: Document?

    @State private var isImporting = false
    @State private var hasEnqueuedRendering = false

    var sortedDocuments: [Document] {
        folder.documents.sorted { $0.createdAt > $1.createdAt }  // Sort by creation date, newest first
    }

    var body: some View {
        List(selection: $selectedDocument) {
            ForEach(sortedDocuments) { document in
                NavigationLink(value: document) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.headline)

                        // Show summary if available
                        if let summary = document.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task {
                            await deleteDocument(document)
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .importFiles)) { notification in
            if let notificationFolder = notification.object as? Folder,
               notificationFolder == folder {
                isImporting = true
            }
        }
        .task {
            // Proactively enqueue documents for background rendering when list loads
            await enqueueDocumentsForRendering()
        }
    }

    private func enqueueDocumentsForRendering() async {
        // Only enqueue once per folder view
        guard !hasEnqueuedRendering else { return }
        hasEnqueuedRendering = true

        print("📄 Enqueueing \(sortedDocuments.count) documents for background rendering")

        // Enqueue all documents in this folder for background rendering
        await MainActor.run {
            for document in sortedDocuments {
                let hash = document.calculateContentHash()

                // Enqueue with normal priority (will render in background)
                MarkdownRenderingPipeline.shared.enqueueRender(
                    documentId: document.id,
                    content: document.content,
                    contentHash: hash,
                    priority: .normal
                )
            }
        }

        print("📄 Background rendering queue populated")
    }

    private func deleteDocument(_ document: Document) async {
        print("🗑️ Deleting document: \(document.title)")
        print("   - Document type: \(document.effectiveDocumentType.rawValue)")
        print("   - fileURL: \(document.fileURL?.path ?? "nil")")
        print("   - originalFileURL: \(document.originalFileURL?.path ?? "nil")")

        // Delete associated files from iCloud Drive first
        do {
            // Delete extracted text file (markdown file)
            if let fileURL = document.fileURL {
                try await FileStorageManager.shared.deleteFile(at: fileURL)
                print("✅ Deleted extracted text file: \(fileURL.lastPathComponent)")
            } else {
                print("⚠️ No extracted text file to delete")
            }

            // Delete original file (for imported PDFs, EPUBs, etc.)
            if let originalFileURL = document.originalFileURL {
                try await FileStorageManager.shared.deleteFile(at: originalFileURL)
                print("✅ Deleted original file: \(originalFileURL.lastPathComponent)")
            } else {
                print("⚠️ No original file to delete")
            }
        } catch {
            print("❌ Failed to delete files: \(error)")
            // Continue with document deletion even if file deletion fails
        }

        // Delete document from SwiftData
        await MainActor.run {
            modelContext.delete(document)
            try? modelContext.save()
        }

        print("✅ Deleted document from database: \(document.title)")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importFiles(urls)
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }

    private func importFiles(_ urls: [URL]) async {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let title = url.deletingPathExtension().lastPathComponent
                let fileName = url.lastPathComponent

                // Copy file to iCloud Drive folder matching this sidebar folder
                let folderName = folder.iCloudPath ?? folder.name
                let fileURL = try await FileStorageManager.shared.copyFileToiCloud(
                    from: url,
                    toFolder: folderName,
                    fileName: fileName
                )

                print("✅ Imported file to iCloud: \(fileURL.path)")

                let documentID = await MainActor.run {
                    // Create file-backed document
                    let doc = Document(
                        title: title,
                        fileURL: fileURL,
                        fileName: fileName,
                        folder: folder
                    )

                    modelContext.insert(doc)
                    try? modelContext.save()
                    return doc.persistentModelID
                }

                // Trigger processing pipeline in background to avoid UI freeze
                let cancellationToken = CancellationToken()
                Task.detached(priority: .utility) {
                    await ProcessingPipeline.shared.processDocument(documentID: documentID, cancellationToken: cancellationToken)
                }

            } catch {
                print("Failed to import \(url.lastPathComponent): \(error)")
            }
        }
    }
}
