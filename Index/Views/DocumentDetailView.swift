//
//  DocumentDetailView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData
import MarkdownUI

struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext

    @State private var viewMode: ViewMode = .edit
    @State private var saveTask: Task<Void, Never>?
    @State private var showVersionHistory = false
    @State private var renderedContent: MarkdownContent?  // Pre-parsed markdown content
    @State private var cachedContentHash: String?  // Hash of currently rendered content
    @State private var renderTask: Task<Void, Never>?  // Track rendering task for cancellation
    private let ragEngine = RAGEngine()
    private let typography = TypographyStyle.default

    // Threshold for using simpler rendering (characters)
    private let largeDocumentThreshold = 50000

    enum ViewMode {
        case edit
        case view
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 8) {
                TextField("Document Title", text: $document.title)
                    .font(.title2)
                    .textFieldStyle(.plain)

                // Editable summary
                TextField("Add a summary...", text: Binding(
                    get: { document.summary ?? "" },
                    set: { document.summary = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                    .lineLimit(2...3)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            Divider()

            // Content editor/viewer - Centered column layout
            HStack(spacing: 0) {
                Spacer(minLength: typography.editorPadding)

                Group {
                    if viewMode == .view {
                        // View mode: Rendered Markdown with performance optimization
                        ZStack {
                            if document.content.count > largeDocumentThreshold {
                                // For very large documents (>50k chars), use plain text to avoid UI freeze
                                VStack(spacing: 0) {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(.secondary)
                                        Text("Large document (\(document.content.count / 1000)KB) - showing plain text for performance")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5))

                                    ScrollView {
                                        Text(document.content)
                                            .font(.system(size: 16))
                                            .lineSpacing(typography.lineSpacingPoints)
                                            .textSelection(.enabled)
                                            .padding(.vertical, 16)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .frame(maxWidth: typography.maxColumnWidth)
                            } else if let content = renderedContent {
                                // Render pre-parsed markdown content
                                ScrollView {
                                    Markdown(content)
                                        .markdownTheme(.indexTheme)
                                        .textSelection(.enabled)
                                        .padding(.vertical, 16)
                                }
                                .frame(maxWidth: typography.maxColumnWidth)
                            } else {
                                // Fallback while loading
                                VStack {
                                    Spacer()
                                    Text("No preview available")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: typography.maxColumnWidth)
                            }
                        }
                    } else {
                        // Edit mode: Plain text monospace editor
                        TextEditor(text: $document.content)
                            .font(.system(size: 16, design: .monospaced))
                            .lineSpacing(typography.lineSpacingPoints)
                            .frame(maxWidth: typography.maxColumnWidth)
                            .onChange(of: document.content) { _, _ in
                                scheduleAutosave()
                            }
                    }
                }

                Spacer(minLength: typography.editorPadding)
            }
        }
        .toolbar {
            ToolbarItem {
                // Mode toggle
                Picker("Mode", selection: $viewMode) {
                    Text("Edit").tag(ViewMode.edit)
                    Text("View").tag(ViewMode.view)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            ToolbarItem {
                Button(action: {
                    saveTask?.cancel()
                    saveDocument()
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            ToolbarItem {
                Button(action: {
                    viewMode = viewMode == .edit ? .view : .edit
                }) {
                    Label("Toggle Preview", systemImage: viewMode == .edit ? "eye" : "pencil")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Toggle between edit and preview mode (⌘R)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reprocessDocument)) { _ in
            let documentID = document.persistentModelID
            let cancellationToken = CancellationToken()
            Task.detached(priority: .userInitiated) {
                await ProcessingPipeline.shared.processDocument(documentID: documentID, cancellationToken: cancellationToken)
            }
        }
        .onChange(of: viewMode) { oldMode, newMode in
            if newMode == .view {
                // Only render if content has changed since last render
                renderPreviewIfNeeded()
            } else if oldMode == .view {
                // Cancel any pending render when switching to edit mode
                renderTask?.cancel()
            }
        }
        .onChange(of: document.content) { _, newContent in
            // Invalidate memory cache when content changes
            let newHash = document.calculateContentHash()
            if cachedContentHash != newHash {
                cachedContentHash = nil
                renderedContent = nil

                // Invalidate pipeline cache too
                Task { @MainActor in
                    MarkdownRenderingPipeline.shared.invalidateCache(documentId: document.id)
                }
            }

            // If in view mode and content changed, re-render
            if viewMode == .view {
                renderPreviewIfNeeded()
            }
        }
        .onChange(of: document.id) { oldValue, newValue in
            // When navigating AWAY from a document (oldValue has previous document)
            // Check if the title was deleted and regenerate if needed
            if oldValue != newValue {
                // Check if the current document's title is empty
                let currentTitle = document.title.trimmingCharacters(in: .whitespaces)

                if currentTitle.isEmpty && !document.content.trimmingCharacters(in: .whitespaces).isEmpty {
                    // User deleted the title - regenerate it
                    Task {
                        await generateTitleIfNeeded()
                    }
                }

                // Reset view mode and rendered content when switching documents
                viewMode = .edit
                renderedContent = nil
                renderTask?.cancel()
            }

            // Cancel any pending save and render for the previous document
            saveTask?.cancel()
            renderTask?.cancel()
        }
        .sheet(isPresented: $showVersionHistory) {
            VersionHistoryView(document: document)
        }
        .task(id: document.id) {
            // Load cached render or render in background when document changes
            await loadOrRenderPreview()
        }
    }

    private func loadOrRenderPreview() async {
        let currentHash = document.calculateContentHash()

        // First, check if we already have it in local memory
        if cachedContentHash == currentHash, renderedContent != nil {
            print("📄 Using cached render from local memory")
            return
        }

        // Second, check the rendering pipeline cache
        if let cached = await MarkdownRenderingPipeline.shared.getCachedRender(
            documentId: document.id,
            contentHash: currentHash
        ) {
            print("📄 Using cached render from pipeline")
            renderedContent = cached
            cachedContentHash = currentHash
            return
        }

        // Need to render
        print("📄 Cache miss - rendering preview")
        await renderPreview()
    }

    private func renderPreviewIfNeeded() {
        // Only render if in view mode
        guard viewMode == .view else { return }

        // Cancel any existing render
        renderTask?.cancel()

        // Start new render
        renderTask = Task {
            await renderPreview()
        }
    }

    private func renderPreview() async {
        // Skip rendering for very large documents - use plain text fallback instead
        if document.content.count > largeDocumentThreshold {
            print("📄 Skipping markdown render for large document (\(document.content.count) chars) - using plain text")
            return
        }

        let currentHash = document.calculateContentHash()
        let content = document.content

        print("📄 Rendering preview (\(content.count) chars)")

        // Use rendering pipeline to parse markdown OFF the main thread
        let parsed = await MarkdownRenderingPipeline.shared.renderMarkdownContent(
            content,
            contentHash: currentHash
        )

        // Check if task was cancelled
        guard !Task.isCancelled else {
            print("📄 Render cancelled")
            return
        }

        // Small delay to allow UI to complete any transitions before adding the heavy view
        try? await Task.sleep(for: .milliseconds(100))

        // Update UI with pre-parsed content
        await MainActor.run {
            renderedContent = parsed
            cachedContentHash = currentHash
            print("✅ Preview rendered and cached in memory")

            // Cache in rendering pipeline for future use
            MarkdownRenderingPipeline.shared.cacheRender(
                documentId: document.id,
                content: parsed,
                contentHash: currentHash
            )

            // Update hash in database for persistence
            document.contentHash = currentHash
            try? modelContext.save()
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
        document.modifiedAt = Date()
        document.isProcessed = false // Mark for reprocessing
        document.processingStatus = .pending

        // Generate title if empty or still "Untitled"
        let needsTitleGeneration = document.title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   document.title == "Untitled"

        if needsTitleGeneration && !document.content.trimmingCharacters(in: .whitespaces).isEmpty {
            Task {
                await generateTitleIfNeeded()
            }
        }

        // Generate summary if empty or not yet generated
        let needsSummaryGeneration = document.summary == nil || document.summary?.isEmpty == true

        if needsSummaryGeneration && !document.content.trimmingCharacters(in: .whitespaces).isEmpty {
            Task {
                await generateSummaryIfNeeded()
            }
        }

        try? modelContext.save()

        // Trigger processing pipeline in background to avoid UI freeze
        let documentID = document.persistentModelID
        let cancellationToken = CancellationToken()
        Task.detached(priority: .utility) {
            await ProcessingPipeline.shared.processDocument(documentID: documentID, cancellationToken: cancellationToken)
        }
    }

    private func generateTitleIfNeeded() async {
        do {
            // Use plain text content for title generation
            let currentTitle = document.title
            let generatedTitle = try await ragEngine.generateTitle(
                from: document.plainTextContent,
                documentTitle: currentTitle
            )

            await MainActor.run {
                document.title = generatedTitle
                try? modelContext.save()
            }
        } catch {
            print("⚠️ Title generation failed: \(error.localizedDescription)")

            await MainActor.run {
                // Fallback to timestamp-based title
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                document.title = "Note - \(dateFormatter.string(from: Date()))"
                try? modelContext.save()
            }
        }
    }

    private func generateSummaryIfNeeded() async {
        // Use plain text content for summary generation
        let docTitle = document.title
        let generatedSummary = await ragEngine.generateSummary(
            from: document.plainTextContent,
            documentTitle: docTitle
        )

        await MainActor.run {
            // Only update if we got a non-empty summary
            if !generatedSummary.isEmpty {
                document.summary = generatedSummary
            }
            try? modelContext.save()
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
