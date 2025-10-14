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
    @State private var vectorDBMigration = VectorDBMigration()
    @State private var documentMigration = DocumentMigration()
    @FocusState private var renamingFolder: Folder?

    // File import state
    @State private var showingFileImporter = false
    @State private var importError: Error?
    @State private var showImportError = false

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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Reconcile files when app becomes active
            Task {
                await FileSync.shared.reconcileAllFolders(modelContext: modelContext)
            }
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
                .onChange(of: processingQueue.tasks.count) { oldCount, newCount in
                    // Keep popover open if tasks are still active
                    if oldCount > newCount && newCount > 0 && showProcessingQueue {
                        // Task completed but others remain - keep popover open
                        showProcessingQueue = true
                    }
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

            // Reconcile folder when navigating to it
            if case .folder(let folder) = newValue {
                Task {
                    await FileSync.shared.reconcileFolder(folder, modelContext: modelContext)
                }
            }
        }
        .onAppear {
            // Create default folder if none exist
            if folders.isEmpty {
                createDefaultFolder()
            }

            // Initialize iCloudPath for existing folders that don't have it
            for folder in folders where folder.iCloudPath == nil {
                folder.iCloudPath = folder.name
                try? modelContext.save()
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

                ToolbarItem {
                    Button(action: { showingFileImporter = true }) {
                        Label("Import Document", systemImage: "arrow.down.doc")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: DocumentImporter.supportedUTTypes(),
                allowsMultipleSelection: true
            ) { result in
                Task {
                    await handleFileImport(result: result, folder: folder)
                }
            }
            .alert("Import Failed", isPresented: $showImportError, presenting: importError) { _ in
                Button("OK") { importError = nil }
            } message: { error in
                Text(error.localizedDescription)
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
        if documentMigration.isMigrating {
            HStack(spacing: 6) {
                ProgressView(value: documentMigration.migrationProgress)
                    .controlSize(.small)
                    .frame(width: 100)
                Text("Migrating documents to iCloud... (\(documentMigration.processedDocuments)/\(documentMigration.totalDocuments))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if vectorDBMigration.isMigrating {
            HStack(spacing: 6) {
                ProgressView(value: vectorDBMigration.migrationProgress)
                    .controlSize(.small)
                    .frame(width: 100)
                Text("Migrating to ChromaDB... (\(vectorDBMigration.processedDocuments)/\(vectorDBMigration.totalDocuments))")
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

        // 1. Check if VectorDB migration is needed and start it
        await vectorDBMigration.checkAndMigrate(modelContext: modelContext)

        // 2. Migrate documents to file-based storage
        await documentMigration.checkAndMigrate(modelContext: modelContext)

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

    private func handleFileImport(result: Result<[URL], Error>, folder: Folder) async {
        do {
            let fileURLs = try result.get()

            guard !fileURLs.isEmpty else {
                print("⚠️ No files selected")
                return
            }

            print("📥 Importing \(fileURLs.count) file(s)...")

            // Import documents using DocumentImporter
            let (importedDocuments, errors) = await DocumentImporter.shared.importDocuments(
                from: fileURLs,
                toFolder: folder,
                context: modelContext
            )

            // Report any import errors
            if !errors.isEmpty {
                print("⚠️ Import completed with \(errors.count) error(s)")
                for (url, error) in errors {
                    print("  - \(url.lastPathComponent): \(error.localizedDescription)")
                }

                // Show first error to user
                if let firstError = errors.first?.1 {
                    importError = firstError
                    showImportError = true
                }
            }

            // Successfully imported documents - add to processing queue and process
            for document in importedDocuments {
                // Add to processing queue for UI feedback
                processingQueue.addTask(
                    id: document.id.uuidString,
                    documentTitle: document.title,
                    type: .processing
                )

                // Process document asynchronously
                Task {
                    await ProcessingPipeline.shared.processDocument(documentID: document.persistentModelID)

                    // Remove from queue when done
                    processingQueue.completeTask(id: document.id.uuidString)
                }
            }

            print("✅ Successfully imported \(importedDocuments.count) document(s)")

            // Select the first imported document
            if let firstDocument = importedDocuments.first {
                selectedDocument = firstDocument
            }

        } catch {
            print("❌ File import failed: \(error.localizedDescription)")
            importError = error
            showImportError = true
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Folder.self, inMemory: true)
}
