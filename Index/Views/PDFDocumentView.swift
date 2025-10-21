//
//  PDFDocumentView.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import SwiftUI
import PDFKit
import MarkdownUI
import SwiftData

/// View for displaying PDF documents with toggle between original PDF and extracted text
struct PDFDocumentView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext
    @Binding var viewMode: PDFViewMode

    @State private var pdfDocument: PDFDocument?
    @State private var extractedText: String = ""
    @State private var isLoading = true
    @State private var loadError: Error?

    private let ragEngine = RAGEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (matching markdown documents)
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

                // Original filename info
                if let filename = document.originalFileName {
                    Text("Source: \(filename)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            Divider()

            // Content based on view mode
            if isLoading {
                ProgressView("Loading PDF...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Failed to Load PDF",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else {
                switch viewMode {
                case .pdf:
                    pdfContentView
                case .text:
                    textContentView
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: document.id) { _, _ in
            // Generate summary when document loads if empty
            Task {
                await generateSummaryIfNeeded()
            }
        }
        .onAppear {
            // Generate summary on first appearance if needed
            Task {
                await generateSummaryIfNeeded()
            }
        }
    }

    // MARK: - Summary Generation

    private func generateSummaryIfNeeded() async {
        // Only generate if summary is empty and we have content
        guard document.summary == nil || document.summary?.isEmpty == true else {
            return
        }

        guard !extractedText.isEmpty else {
            return
        }

        print("📝 Generating summary for PDF: \(document.title)")

        let docTitle = document.title
        let generatedSummary = await ragEngine.generateSummary(
            from: extractedText,
            documentTitle: docTitle
        )

        await MainActor.run {
            if !generatedSummary.isEmpty {
                document.summary = generatedSummary
                try? modelContext.save()
                print("✅ Generated summary for PDF")
            }
        }
    }

    // MARK: - PDF View

    @ViewBuilder
    private var pdfContentView: some View {
        if let pdfDocument = pdfDocument {
            PDFViewRepresentable(document: pdfDocument)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "PDF Not Available",
                systemImage: "doc.text",
                description: Text("The original PDF file could not be loaded.")
            )
        }
    }

    // MARK: - Text View

    @ViewBuilder
    private var textContentView: some View {
        ScrollView {
            if extractedText.isEmpty {
                ContentUnavailableView(
                    "No Text Available",
                    systemImage: "doc.text",
                    description: Text("No text could be extracted from this PDF.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Markdown(extractedText)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 800)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Loading

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        // Load PDF document
        if let originalURL = document.originalFileURL {
            pdfDocument = PDFDocument(url: originalURL)

            if pdfDocument == nil {
                loadError = PDFLoadError.invalidPDF
                print("❌ Failed to load PDF from: \(originalURL.path)")
            }
        } else {
            loadError = PDFLoadError.fileNotFound
            print("❌ No original PDF URL available")
        }

        // Load extracted text
        do {
            extractedText = try await document.loadContent()
        } catch {
            print("❌ Failed to load extracted text: \(error)")
            loadError = error
        }
    }
}

// MARK: - PDFView NSViewRepresentable

struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.textBackgroundColor
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}

// MARK: - View Mode

enum PDFViewMode: String, CaseIterable {
    case pdf = "PDF"
    case text = "Text"
}

// MARK: - Errors

enum PDFLoadError: Error, LocalizedError {
    case fileNotFound
    case invalidPDF

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The PDF file could not be found."
        case .invalidPDF:
            return "The file is not a valid PDF or is corrupted."
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewMode: PDFViewMode = .pdf
    // Create a sample document for preview
    let document = Document(title: "Sample PDF", content: "# Sample PDF\n\nThis is extracted text from a PDF document.")
    return PDFDocumentView(document: document, viewMode: $viewMode)
        .frame(width: 800, height: 600)
}
