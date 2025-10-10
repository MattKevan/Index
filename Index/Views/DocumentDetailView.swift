//
//  DocumentDetailView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext

    @State private var editableContent: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showVersionHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                TextField("Document Title", text: $document.title)
                    .font(.title2)
                    .textFieldStyle(.plain)
                    .padding(.horizontal)

                Spacer()

                if !document.isProcessed {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: {
                    saveTask?.cancel()
                    saveDocument()
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(action: {
                    Task {
                        await ProcessingPipeline.shared.processDocument(document)
                    }
                }) {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }

                Button(action: { showVersionHistory.toggle() }) {
                    Label("Versions", systemImage: "clock")
                }
                .padding(.trailing)
            }
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Content editor
            TextEditor(text: $editableContent)
                .font(.body)
                .padding()
                .onChange(of: editableContent) { oldValue, newValue in
                    scheduleAutosave()
                }
        }
        .onAppear {
            editableContent = document.content
        }
        .onChange(of: document.id) { _, _ in
            // Cancel any pending save for the previous document
            saveTask?.cancel()

            // Load content for the new document
            editableContent = document.content
        }
        .sheet(isPresented: $showVersionHistory) {
            VersionHistoryView(document: document)
        }
    }

    private func scheduleAutosave() {
        // Cancel existing save task
        saveTask?.cancel()

        // Schedule new save after 1 second delay
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                saveDocument()
            }
        }
    }

    private func saveDocument() {
        guard document.content != editableContent else { return }

        document.content = editableContent
        document.modifiedAt = Date()
        document.isProcessed = false // Mark for reprocessing
        document.processingStatus = .pending

        try? modelContext.save()

        // Trigger processing pipeline
        Task {
            await ProcessingPipeline.shared.processDocument(document)
        }
    }
}

// Version History View (simple placeholder for now)
struct VersionHistoryView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if document.versions.isEmpty {
                    ContentUnavailableView(
                        "No Versions",
                        systemImage: "clock",
                        description: Text("No version history available for this document")
                    )
                } else {
                    ForEach(document.versions.sorted(by: { $0.createdAt > $1.createdAt })) { version in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(version.versionType.rawValue.capitalized)
                                    .font(.headline)

                                Spacer()

                                Text(version.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let prompt = version.prompt {
                                Text(prompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(version.content)
                                .font(.body)
                                .lineLimit(5)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Version History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
