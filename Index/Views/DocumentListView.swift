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

    @State private var isAddingDocument = false
    @State private var newDocTitle = ""
    @State private var isImporting = false

    var sortedDocuments: [Document] {
        folder.documents.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        List(selection: $selectedDocument) {
            ForEach(sortedDocuments) { document in
                NavigationLink(value: document) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.headline)

                        HStack {
                            Text(document.modifiedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !document.isProcessed {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteDocument(document)
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem {
                Button(action: { isAddingDocument = true }) {
                    Label("Add Document", systemImage: "doc.badge.plus")
                }
            }

            ToolbarItem {
                Button(action: { isImporting = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
        }
        .alert("New Document", isPresented: $isAddingDocument) {
            TextField("Document Title", text: $newDocTitle)
            Button("Cancel", role: .cancel) {
                newDocTitle = ""
            }
            Button("Create") {
                addDocument()
            }
        }
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
    }

    private func addDocument() {
        guard !newDocTitle.isEmpty else { return }

        let document = Document(title: newDocTitle, folder: folder)
        modelContext.insert(document)

        do {
            try modelContext.save()
            selectedDocument = document
            newDocTitle = ""
        } catch {
            print("Error creating document: \(error)")
        }
    }

    private func deleteDocument(_ document: Document) {
        modelContext.delete(document)
        try? modelContext.save()
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
                let content = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent

                await MainActor.run {
                    let document = Document(
                        title: title,
                        content: content,
                        folder: folder
                    )

                    modelContext.insert(document)
                    try? modelContext.save()

                    // Trigger processing pipeline
                    Task {
                        await ProcessingPipeline.shared.processDocument(document)
                    }
                }

            } catch {
                print("Failed to import \(url.lastPathComponent): \(error)")
            }
        }
    }
}
