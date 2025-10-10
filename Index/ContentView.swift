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
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @State private var selectedNavigation: NavigationItem?
    @State private var selectedDocument: Document?
    @State private var searchQuery: String = ""
    @State private var isVectorDBReady: Bool = false

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
            // Sidebar with Search option at top
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
                        NavigationLink(value: NavigationItem.folder(folder)) {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                // TODO: Implement rename
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteFolder(folder)
                            }
                        }
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
        } content: {
            // Content: Hide when searching, show documents for folder
            if isSearching {
                // Hide content pane during search
                Color.clear
            } else if let folder = selectedFolder {
                DocumentListView(
                    folder: folder,
                    selectedDocument: $selectedDocument
                )
            } else {
                ContentUnavailableView(
                    "Select an Option",
                    systemImage: "sidebar.left",
                    description: Text("Choose Search or a folder from the sidebar")
                )
            }
        } detail: {
            // Detail: Show search results or document editor
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
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Select a document to view or edit")
                )
            }
        }
        .searchable(text: $searchQuery, prompt: isVectorDBReady ? "Search with AI..." : "Loading embeddings...")
        .onSubmit(of: .search) {
            performRAGSearch()
        }
        .task {
            // Wait for VectorDB to be ready
            print("📊 Checking VectorDB ready status...")

            // Poll for readiness with timeout
            for attempt in 1...30 {
                let ready = await ProcessingPipeline.shared.isReady()
                print("📊 Attempt \(attempt): VectorDB ready = \(ready)")

                if ready {
                    isVectorDBReady = true
                    print("✅ VectorDB is ready!")
                    break
                }

                // Wait 1 second between checks
                try? await Task.sleep(for: .seconds(1))
            }

            if !isVectorDBReady {
                print("⚠️ VectorDB initialization timed out after 30 seconds")
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                if !isVectorDBReady {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Initializing embeddings...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
