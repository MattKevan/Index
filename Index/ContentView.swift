//
//  ContentView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData

enum NavigationItem: Hashable {
    case search
    case folder(Folder)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProcessingQueue.self) private var processingQueue
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @State private var selectedNavigation: NavigationItem?
    @State private var selectedDocument: Document?
    @State private var searchQuery: String = ""
    @State private var isVectorDBReady: Bool = false
    @State private var showProcessingQueue = false
    @State private var migration = VectorDBMigration()
    @FocusState private var renamingFolder: Folder?

    private var isSearching: Bool {
        if case .search = selectedNavigation {
            return true
        }
        return false
    }

    private var selectedFolder: Folder? {
        if case .folder(let folder) = selectedNavigation {
            return folder
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } content: {
            contentPane
        } detail: {
            detailPane
        }
        .searchable(text: $searchQuery, prompt: isVectorDBReady ? "Search with AI..." : "Loading embeddings...")
        .onSubmit(of: .search) {
            performRAGSearch()
        }
        .task {
            await checkVectorDBReady()
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                statusIndicator
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { showProcessingQueue.toggle() }) {
                    ZStack {
                        Image(systemName: "circle.dashed")
                            .symbolEffect(.variableColor.iterative, isActive: processingQueue.hasActiveTasks)

                        if processingQueue.hasActiveTasks {
                            Text("\(processingQueue.tasks.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .help("Processing Tasks")
                .popover(isPresented: $showProcessingQueue) {
                    ProcessingQueueView()
                        .environment(processingQueue)
                }
            }
        }
    }

    // MARK: - View Components

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedNavigation) {
            // Search section
            Section {
                NavigationLink(value: NavigationItem.search) {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }

            // Folders section
            Section("Folders") {
                ForEach(folders) { folder in
                    folderRow(for: folder)
                }
            }
        }
        .navigationTitle("Index")
        .toolbar {
            ToolbarItem {
                Button(action: { addFolder() }) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .onChange(of: selectedNavigation) { _, newValue in
            // Clear document selection when switching views
            if case .search = newValue {
                selectedDocument = nil
            }
        }
        .onAppear {
            // Create default folder if none exist
            if folders.isEmpty {
                createDefaultFolder()
            }
        }
    }

    @ViewBuilder
    private func folderRow(for folder: Folder) -> some View {
        NavigationLink(value: NavigationItem.folder(folder)) {
            HStack {
                Image(systemName: "folder.fill")
                TextField("Folder Name", text: Binding(
                    get: { folder.name },
                    set: { folder.name = $0 }
                ))
                .textFieldStyle(.plain)
                .focused($renamingFolder, equals: folder)
                .onSubmit {
                    renamingFolder = nil
                    try? modelContext.save()
                }
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renamingFolder = folder
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteFolder(folder)
            }
        }
    }

    @ViewBuilder
    private var contentPane: some View {
        if isSearching {
            // Hide content pane during search
            Color.clear
        } else if let folder = selectedFolder {
            DocumentListView(
                folder: folder,
                selectedDocument: $selectedDocument
            )
            .toolbar {
                ToolbarItem {
                    Button(action: { addDocumentToFolder(folder) }) {
                        Label("New Document", systemImage: "doc.badge.plus")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select an Option",
                systemImage: "sidebar.left",
                description: Text("Choose Search or a folder from the sidebar")
            )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if isSearching {
            RAGSearchView(
                query: searchQuery,
                onClose: {
                    // Return to folder view
                    if let firstFolder = folders.first {
                        selectedNavigation = .folder(firstFolder)
                    }
                    searchQuery = ""
                }
            )
        } else if let document = selectedDocument {
            DocumentDetailView(document: document)
                .id(document.id)  // Force refresh when document changes
        } else {
            ContentUnavailableView(
                "No Document Selected",
                systemImage: "doc.text",
                description: Text("Select a document to view or edit")
            )
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if migration.isMigrating {
            HStack(spacing: 6) {
                ProgressView(value: migration.migrationProgress)
                    .controlSize(.small)
                    .frame(width: 100)
                Text("Migrating to ChromaDB... (\(migration.processedDocuments)/\(migration.totalDocuments))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !isVectorDBReady {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Initializing embeddings...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func checkVectorDBReady() async {
        print("📊 Checking VectorDB ready status...")

        // Check if migration is needed and start it
        await migration.checkAndMigrate(modelContext: modelContext)

        // Poll for readiness with timeout
        for attempt in 1...30 {
            let ready = await ProcessingPipeline.shared.isReady()
            print("📊 Attempt \(attempt): VectorDB ready = \(ready)")

            if ready {
                isVectorDBReady = true
                print("✅ VectorDB is ready!")

                // Trigger automatic processing of unprocessed documents
                Task {
                    await ProcessingPipeline.shared.processAllUnprocessedDocuments()
                    await ProcessingPipeline.shared.processDocumentsMissingMetadata()
                }

                break
            }

            // Wait 1 second between checks
            try? await Task.sleep(for: .seconds(1))
        }

        if !isVectorDBReady {
            print("⚠️ VectorDB initialization timed out after 30 seconds")
        }
    }

    private func performRAGSearch() {
        guard !searchQuery.isEmpty else { return }
        guard isVectorDBReady else {
            print("⚠️ Cannot search: VectorDB not ready")
            return
        }
        selectedNavigation = .search
    }

    private func addFolder() {
        let folderName = "Folder \(folders.count + 1)"
        let folder = Folder(name: folderName, sortOrder: folders.count)
        modelContext.insert(folder)
        try? modelContext.save()
        selectedNavigation = .folder(folder)
    }

    private func addDocumentToFolder(_ folder: Folder) {
        let document = Document(title: "Untitled", content: "", folder: folder)
        modelContext.insert(document)

        do {
            try modelContext.save()
            selectedDocument = document
        } catch {
            print("Error creating document: \(error)")
        }
    }

    private func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    private func createDefaultFolder() {
        let folder = Folder(name: "Notes", sortOrder: 0)
        modelContext.insert(folder)
        try? modelContext.save()
        selectedNavigation = .folder(folder)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Folder.self, inMemory: true)
}
