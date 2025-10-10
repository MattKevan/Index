//
//  SidebarView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    let folders: [Folder]
    @Binding var selectedFolder: Folder?

    @State private var isAddingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(folders) { folder in
                NavigationLink(value: folder) {
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
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem {
                Button(action: { isAddingFolder = true }) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("New Folder", isPresented: $isAddingFolder) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                addFolder()
            }
        }
        .onAppear {
            // Create default folder if none exist
            if folders.isEmpty {
                createDefaultFolder()
            }
        }
    }

    private func addFolder() {
        guard !newFolderName.isEmpty else { return }

        let folder = Folder(
            name: newFolderName,
            sortOrder: folders.count
        )
        modelContext.insert(folder)

        do {
            try modelContext.save()
            selectedFolder = folder
            newFolderName = ""
        } catch {
            print("Error creating folder: \(error)")
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
        selectedFolder = folder
    }
}
