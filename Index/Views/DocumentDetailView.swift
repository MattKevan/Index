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

    // File-based content management
    @State private var editableContent: String = ""  // In-memory content for editing
    @State private var isLoadingContent: Bool = false
    @State private var contentLoadError: Error?

    // PDF view mode
    @State private var pdfViewMode: PDFViewMode = .pdf

    // EPUB view mode
    @State private var epubViewMode: EPUBViewMode = .text

    // Transformation mode state
    @State private var selectedTransformPreset: TransformationPreset?
    @State private var needsTransformRegeneration = false

    private let ragEngine = RAGEngine()
    private let typography = TypographyStyle.default

    // Threshold for using simpler rendering (characters)
    private let largeDocumentThreshold = 50000

    enum ViewMode {
        case edit
        case view
        case transform
    }

    // Computed property to control inspector visibility
    private var isInspectorPresented: Bool {
        viewMode == .transform
    }

    var body: some View {
        // Route to appropriate view based on document type
        Group {
            switch document.effectiveDocumentType {
            case .pdf:
                PDFDocumentView(document: document, viewMode: $pdfViewMode)
                    .toolbar {
                        ToolbarItem {
                            // PDF view mode toggle
                            Picker("View Mode", selection: $pdfViewMode) {
                                Text("PDF").tag(PDFViewMode.pdf)
                                Text("Text").tag(PDFViewMode.text)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }

                        ToolbarItem {
                            Button(action: {
                                openPDFInPreview()
                            }) {
                                Label("Open in Preview", systemImage: "arrow.up.forward.app")
                            }
                            .help("Open PDF in Preview app")
                        }
                    }
            case .epub:
                EPUBDocumentView(document: document, viewMode: $epubViewMode)
                    .toolbar {
                        ToolbarItem {
                            // EPUB view mode toggle
                            Picker("View Mode", selection: $epubViewMode) {
                                Text("EPUB").tag(EPUBViewMode.epub)
                                Text("Text").tag(EPUBViewMode.text)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }

                        ToolbarItem {
                            Button(action: {
                                openEPUBExternally()
                            }) {
                                Label("Open Externally", systemImage: "arrow.up.forward.app")
                            }
                            .help("Open EPUB in external reader")
                        }
                    }
            case .docx:
                // Future: DOCXDocumentView(document: document)
                unsupportedDocumentView(type: "DOCX")
            case .markdown, .plainText:
                markdownEditorView
            }
        }
    }

    // MARK: - Markdown Editor View

    @ViewBuilder
    private var markdownEditorView: some View {
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
                    if viewMode == .transform {
                        // Transform mode: AI-powered document transformations
                        TransformationView(
                            document: document,
                            selectedPreset: $selectedTransformPreset,
                            needsRegeneration: $needsTransformRegeneration
                        )
                    } else if viewMode == .view {
                        // View mode: Rendered Markdown with performance optimization
                        ZStack {
                            if editableContent.count > largeDocumentThreshold {
                                // For very large documents (>50k chars), use plain text to avoid UI freeze
                                VStack(spacing: 0) {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(.secondary)
                                        Text("Large document (\(editableContent.count / 1000)KB) - showing plain text for performance")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5))

                                    ScrollView {
                                        VStack {
                                            Text(editableContent)
                                                .font(.system(size: 16))
                                                .lineSpacing(typography.lineSpacingPoints)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: typography.maxColumnWidth, alignment: .leading)
                                                .padding()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                // removed outer frame(maxWidth: typography.maxColumnWidth)
                            } else if let content = renderedContent {
                                // Render pre-parsed markdown content
                                ScrollView {
                                    VStack {
                                        Markdown(content)
                                            .markdownTheme(.indexTheme)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: typography.maxColumnWidth, alignment: .leading)
                                            .padding()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                // removed frame(maxWidth: typography.maxColumnWidth)
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
                        if isLoadingContent {
                            VStack {
                                Spacer()
                                ProgressView("Loading...")
                                    .controlSize(.large)
                                Spacer()
                            }
                            .frame(maxWidth: typography.maxColumnWidth)
                        } else {
                            TextEditor(text: $editableContent)
                                .font(.system(size: 16, design: .monospaced))
                                .lineSpacing(typography.lineSpacingPoints)
                                .frame(maxWidth: typography.maxColumnWidth)
                                .onChange(of: editableContent) { _, _ in
                                    scheduleAutosave()
                                }
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
                    Text("Transform").tag(ViewMode.transform)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
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
        .onChange(of: editableContent) { _, newContent in
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
            // Load content for the new document
            Task {
                await loadDocumentContent()
            }
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
            // Load document content first
            await loadDocumentContent()

            // Then load cached render or render in background when document changes
            await loadOrRenderPreview()
        }
        .inspector(isPresented: .constant(isInspectorPresented)) {
            if viewMode == .transform {
                TransformationPresetsSidebar(
                    selectedPreset: $selectedTransformPreset,
                    needsRegeneration: $needsTransformRegeneration
                ) { preset in
                    // Update the binding - TransformationView will react to the change
                    selectedTransformPreset = preset
                }
                .inspectorColumnWidth(min: 220, ideal: 260, max: 300)
            }
        }
    }

    // MARK: - Unsupported Document Types

    @ViewBuilder
    private func unsupportedDocumentView(type: String) -> some View {
        ContentUnavailableView(
            "\(type) Not Yet Supported",
            systemImage: "doc.text",
            description: Text("\(type) document viewing will be available in a future update. For now, you can view the extracted text.")
        )
    }

    // MARK: - Content Loading

    private func loadDocumentContent() async {
        isLoadingContent = true
        contentLoadError = nil

        do {
            let content = try await document.loadContent()
            await MainActor.run {
                editableContent = content
                isLoadingContent = false
            }
            print("✅ Loaded document content (\(content.count) chars)")
        } catch {
            print("❌ Failed to load document content: \(error)")
            await MainActor.run {
                contentLoadError = error
                isLoadingContent = false
                // Fallback for legacy documents
                editableContent = document.content
            }
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
        if editableContent.count > largeDocumentThreshold {
            print("📄 Skipping markdown render for large document (\(editableContent.count) chars) - using plain text")
            return
        }

        let currentHash = document.calculateContentHash()
        let content = editableContent

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

        // Save content to file (async)
        Task {
            do {
                try await document.saveContent(editableContent)
                print("✅ Saved document content to file")
            } catch {
                print("❌ Failed to save document content: \(error)")
            }
        }

        // Generate title if empty or still "Untitled"
        let needsTitleGeneration = document.title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   document.title == "Untitled"

        if needsTitleGeneration && !editableContent.trimmingCharacters(in: .whitespaces).isEmpty {
            Task {
                await generateTitleIfNeeded()
            }
        }

        // Generate summary if empty or not yet generated
        let needsSummaryGeneration = document.summary == nil || document.summary?.isEmpty == true

        if needsSummaryGeneration && !editableContent.trimmingCharacters(in: .whitespaces).isEmpty {
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
            // Strip Markdown from editable content for title generation
            let plainText = stripMarkdown(from: editableContent)
            let currentTitle = document.title
            let generatedTitle = try await ragEngine.generateTitle(
                from: plainText,
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
        // Strip Markdown from editable content for summary generation
        let plainText = stripMarkdown(from: editableContent)
        let docTitle = document.title
        let generatedSummary = await ragEngine.generateSummary(
            from: plainText,
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

    // Helper to strip Markdown syntax for clean text
    private func stripMarkdown(from content: String) -> String {
        var plainText = content

        // Remove heading markers
        plainText = plainText.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)

        // Remove bold/italic markers
        plainText = plainText.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)

        // Remove inline code markers
        plainText = plainText.replacingOccurrences(of: #"`(.+?)`"#, with: "$1", options: .regularExpression)

        // Remove link syntax but keep text
        plainText = plainText.replacingOccurrences(of: #"\[(.+?)\]\(.+?\)"#, with: "$1", options: .regularExpression)

        return plainText
    }

    // Open PDF in Preview app
    private func openPDFInPreview() {
        guard let originalFileURL = document.originalFileURL else {
            print("⚠️ No original PDF file URL available")
            return
        }

        NSWorkspace.shared.open(originalFileURL)
        print("📄 Opening PDF in Preview: \(originalFileURL.lastPathComponent)")
    }

    // Open EPUB in external reader (Books.app or other)
    private func openEPUBExternally() {
        guard let originalFileURL = document.originalFileURL else {
            print("⚠️ No original EPUB file URL available")
            return
        }

        NSWorkspace.shared.open(originalFileURL)
        print("📚 Opening EPUB externally: \(originalFileURL.lastPathComponent)")
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

