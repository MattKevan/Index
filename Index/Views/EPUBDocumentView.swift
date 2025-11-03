//
//  EPUBDocumentView.swift
//  Index
//
//  Created by Claude on 11/03/2025.
//

import SwiftUI
import WebKit
import MarkdownUI
import SwiftData

/// View for displaying EPUB documents with toggle between original EPUB rendering and extracted text
struct EPUBDocumentView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext
    @Binding var viewMode: EPUBViewMode

    @State private var extractedText: String = ""
    @State private var isLoading = true
    @State private var loadError: Error?

    private let ragEngine = RAGEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (matching PDF documents)
            VStack(alignment: .leading, spacing: 8) {
                TextField("Document Title", text: $document.title)
                    .font(.title2)
                    .textFieldStyle(.plain)

                // Author info (if available)
                if let author = document.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Editable summary
                TextField("Add a summary...", text: Binding(
                    get: { document.summary ?? "" },
                    set: { document.summary = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                    .lineLimit(2...3)

                // Original filename and metadata
                HStack(spacing: 12) {
                    if let filename = document.originalFileName {
                        Text("Source: \(filename)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let publisher = document.publisher {
                        Text("• Publisher: \(publisher)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            Divider()

            // Content based on view mode
            if isLoading {
                ProgressView("Loading EPUB...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Failed to Load EPUB",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else {
                switch viewMode {
                case .epub:
                    epubContentView
                case .text:
                    textContentView
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: document.id) { _, _ in
            Task {
                await generateSummaryIfNeeded()
            }
        }
    }

    // MARK: - Summary Generation

    private func generateSummaryIfNeeded() async {
        // Only generate if summary is empty and we have content
        guard document.summary == nil || document.summary?.isEmpty == true else {
            print("ℹ️ Summary already exists, skipping generation")
            return
        }

        guard !extractedText.isEmpty else {
            print("⚠️ No extracted text available for summary generation")
            return
        }

        print("📝 Generating AI summary for EPUB: \(document.title)")

        // Truncate content to avoid Foundation Models safety guardrails
        // Use first 10,000 characters (roughly first few chapters)
        let maxChars = 10_000
        let truncatedText = String(extractedText.prefix(maxChars))

        print("   Using first \(truncatedText.count) characters for summary (total: \(extractedText.count))")

        let docTitle = document.title
        let generatedSummary = await ragEngine.generateSummary(
            from: truncatedText,
            documentTitle: docTitle
        )

        await MainActor.run {
            if !generatedSummary.isEmpty {
                document.summary = generatedSummary
                try? modelContext.save()
                print("✅ Generated summary for EPUB")
            } else {
                print("⚠️ No summary generated (Foundation Models may be unavailable)")
            }
        }
    }

    // MARK: - EPUB View

    @ViewBuilder
    private var epubContentView: some View {
        if let originalURL = document.originalFileURL {
            EPUBWebView(epubURL: originalURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "EPUB Not Available",
                systemImage: "book.closed",
                description: Text("The original EPUB file could not be loaded.")
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
                    description: Text("No text could be extracted from this EPUB.")
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

        print("📚 Loading EPUB document: \(document.title)")

        // Check if original EPUB file exists
        guard let originalURL = document.originalFileURL else {
            loadError = EPUBLoadError.fileNotFound
            print("❌ No original EPUB URL available for document: \(document.title)")
            return
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            loadError = EPUBLoadError.fileNotFound
            print("❌ EPUB file not found at: \(originalURL.path)")
            return
        }

        print("✅ EPUB file exists at: \(originalURL.path)")

        // Load extracted text with comprehensive error handling
        do {
            let content = try await document.loadContent()

            // Validate content was actually loaded
            guard !content.isEmpty else {
                loadError = EPUBLoadError.invalidEPUB
                print("⚠️ Loaded content is empty for: \(document.title)")
                return
            }

            extractedText = content
            print("✅ Loaded \(content.count) characters of extracted text")

        } catch {
            print("❌ Failed to load extracted text: \(error.localizedDescription)")
            loadError = error
            extractedText = "" // Ensure we have a safe empty string
        }
    }
}

// MARK: - EPUBWebView

/// WebView for rendering EPUB content
struct EPUBWebView: NSViewRepresentable {
    let epubURL: URL
    @State private var currentChapterHTML: String = ""
    @State private var isLoading = true

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isInspectable = true
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        Task {
            await loadAndRenderEPUB(in: nsView)
        }
    }

    private func loadAndRenderEPUB(in webView: WKWebView) async {
        print("🌐 Rendering EPUB as single scrolling page: \(epubURL.lastPathComponent)")

        do {
            // Verify EPUB file exists
            guard FileManager.default.fileExists(atPath: epubURL.path) else {
                throw NSError(domain: "EPUBError", code: 0, userInfo: [NSLocalizedDescriptionKey: "EPUB file not found"])
            }

            // Extract all chapters (not just first)
            let allChapters = try await extractAllChapters()

            // Validate we got content
            guard !allChapters.isEmpty else {
                throw NSError(domain: "EPUBError", code: 7, userInfo: [NSLocalizedDescriptionKey: "No content extracted from EPUB"])
            }

            print("✅ Extracted \(allChapters.count) chapters for rendering")

            // Combine all chapters into single scrolling document
            let combinedHTML = allChapters.joined(separator: "\n<hr class='chapter-separator'>\n")

            // Create clean HTML with our own default stylesheet (no external resources)
            let styledHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    * {
                        box-sizing: border-box;
                    }
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                        padding: 40px;
                        max-width: 800px;
                        margin: 0 auto;
                        line-height: 1.6;
                        font-size: 18px;
                        color: #1a1a1a;
                        background-color: #ffffff;
                    }
                    h1, h2, h3, h4, h5, h6 {
                        margin-top: 1.5em;
                        margin-bottom: 0.5em;
                        font-weight: 600;
                        line-height: 1.3;
                        color: #000;
                    }
                    h1 { font-size: 2em; }
                    h2 { font-size: 1.5em; }
                    h3 { font-size: 1.25em; }
                    p {
                        margin: 1em 0;
                        text-align: justify;
                    }
                    .chapter-separator {
                        border: none;
                        border-top: 2px solid #e0e0e0;
                        margin: 3em 0;
                    }
                    img {
                        max-width: 100%;
                        height: auto;
                        display: block;
                        margin: 2em auto;
                    }
                    blockquote {
                        border-left: 3px solid #ddd;
                        margin: 1.5em 0;
                        padding-left: 1em;
                        color: #666;
                    }
                    code {
                        font-family: "SF Mono", Monaco, monospace;
                        background: #f5f5f5;
                        padding: 0.2em 0.4em;
                        border-radius: 3px;
                    }
                    pre {
                        background: #f5f5f5;
                        padding: 1em;
                        border-radius: 5px;
                        overflow-x: auto;
                    }
                    a {
                        color: #007aff;
                        text-decoration: none;
                    }
                    a:hover {
                        text-decoration: underline;
                    }
                </style>
            </head>
            <body>
                \(combinedHTML)
            </body>
            </html>
            """

            await MainActor.run {
                // Load without baseURL to prevent external resource loading
                webView.loadHTMLString(styledHTML, baseURL: nil)
                print("✅ WebView loaded EPUB as single scrolling page")
            }
        } catch {
            print("❌ Failed to render EPUB: \(error.localizedDescription)")
            await showErrorMessage(in: webView, error: error)
        }
    }

    private func extractAllChapters() async throws -> [String] {
        print("📖 Extracting all chapters from: \(epubURL.lastPathComponent)")

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract EPUB
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", epubURL.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            print("❌ Unzip failed with status: \(process.terminationStatus)")
            throw NSError(domain: "EPUBError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract EPUB"])
        }

        print("✅ EPUB extracted to temp directory")

        // Parse container.xml
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerPath),
              let containerXML = String(data: containerData, encoding: .utf8),
              let opfPathMatch = containerXML.range(of: #"full-path\s*=\s*"([^"]+)""#, options: .regularExpression),
              let opfPath = extractPath(from: String(containerXML[opfPathMatch])) else {
            print("❌ Failed to parse container.xml")
            throw NSError(domain: "EPUBError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse container.xml"])
        }

        print("✅ Found content.opf at: \(opfPath)")

        // Parse content.opf
        let opfURL = tempDir.appendingPathComponent(opfPath)
        guard let opfData = try? Data(contentsOf: opfURL),
              let opfXML = String(data: opfData, encoding: .utf8) else {
            print("❌ Failed to read content.opf")
            throw NSError(domain: "EPUBError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read content.opf"])
        }

        // Extract all spine items
        var spineItems: [String] = []
        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern, options: []) {
            let range = NSRange(opfXML.startIndex..., in: opfXML)
            regex.enumerateMatches(in: opfXML, range: range) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges == 2,
                      let idrefRange = Range(match.range(at: 1), in: opfXML) else {
                    return
                }
                let idref = String(opfXML[idrefRange])
                spineItems.append(idref)
            }
        }

        print("📚 Found \(spineItems.count) spine items: \(spineItems.prefix(3))")

        // Build manifest map - try multiple patterns for different attribute orders
        var manifest: [String: String] = [:]

        // Pattern 1: id before href
        let pattern1 = #"<item[^>]*\sid="([^"]+)"[^>]*\shref="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern1, options: []) {
            let range = NSRange(opfXML.startIndex..., in: opfXML)
            regex.enumerateMatches(in: opfXML, range: range) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges == 3,
                      let idRange = Range(match.range(at: 1), in: opfXML),
                      let hrefRange = Range(match.range(at: 2), in: opfXML) else {
                    return
                }
                let id = String(opfXML[idRange])
                let href = String(opfXML[hrefRange])
                manifest[id] = href
            }
        }

        // Pattern 2: href before id (if first pattern didn't work)
        if manifest.isEmpty {
            let pattern2 = #"<item[^>]*\shref="([^"]+)"[^>]*\sid="([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern2, options: []) {
                let range = NSRange(opfXML.startIndex..., in: opfXML)
                regex.enumerateMatches(in: opfXML, range: range) { match, _, _ in
                    guard let match = match,
                          match.numberOfRanges == 3,
                          let hrefRange = Range(match.range(at: 1), in: opfXML),
                          let idRange = Range(match.range(at: 2), in: opfXML) else {
                        return
                    }
                    let id = String(opfXML[idRange])
                    let href = String(opfXML[hrefRange])
                    manifest[id] = href
                }
            }
        }

        print("📄 Found \(manifest.count) manifest items")

        if manifest.isEmpty {
            print("⚠️ No manifest items found - printing content.opf sample:")
            print(String(opfXML.prefix(500)))
        }

        // Extract all chapters
        var chapters: [String] = []
        let opfBasePath = (opfPath as NSString).deletingLastPathComponent

        print("🔍 Extracting chapters from spine...")

        for (index, spineID) in spineItems.enumerated() {
            guard let chapterPath = manifest[spineID] else {
                print("   ⚠️ Chapter \(index + 1): No manifest entry for spine ID '\(spineID)'")
                continue
            }

            let chapterURL = tempDir.appendingPathComponent(opfBasePath).appendingPathComponent(chapterPath)
            guard let chapterData = try? Data(contentsOf: chapterURL),
                  let chapterHTML = String(data: chapterData, encoding: .utf8) else {
                print("   ⚠️ Chapter \(index + 1): Failed to read \(chapterPath)")
                continue
            }

            // Extract body content - use simple string operations for better compatibility
            var bodyContent = chapterHTML

            // Find body tag start
            if let bodyStartRange = chapterHTML.range(of: "<body", options: .caseInsensitive) {
                // Find the end of the opening body tag
                if let bodyOpenEndRange = chapterHTML.range(of: ">", range: bodyStartRange.upperBound..<chapterHTML.endIndex) {
                    bodyContent = String(chapterHTML[bodyOpenEndRange.upperBound...])
                }
            }

            // Find body tag end and truncate
            if let bodyEndRange = bodyContent.range(of: "</body>", options: .caseInsensitive) {
                bodyContent = String(bodyContent[..<bodyEndRange.lowerBound])
            }

            // Strip out <link> tags for stylesheets and fonts
            let cleanContent = bodyContent
                .replacingOccurrences(of: #"<link[^>]*>"#, with: "", options: [.regularExpression])
                .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])

            if !cleanContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                chapters.append(cleanContent)
                print("   ✓ Chapter \(chapters.count): \(cleanContent.prefix(50))...")
            } else {
                print("   ⚠️ Chapter \(index + 1): Content empty after cleaning")
            }
        }

        print("✅ Successfully extracted \(chapters.count)/\(spineItems.count) chapters")

        return chapters
    }

    private func extractPath(from match: String) -> String? {
        if let range = match.range(of: #""([^"]+)""#, options: .regularExpression) {
            return String(match[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private func showErrorMessage(in webView: WKWebView, error: Error) async {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    font-family: -apple-system;
                    padding: 40px;
                    text-align: center;
                }
                .error {
                    color: #d32f2f;
                    margin: 20px 0;
                }
            </style>
        </head>
        <body>
            <h1>📚 EPUB Rendering</h1>
            <p>Unable to render EPUB in web view. Please use the <strong>Text</strong> view mode instead.</p>
            <p class="error">\(error.localizedDescription)</p>
        </body>
        </html>
        """

        await MainActor.run {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

// MARK: - View Mode

enum EPUBViewMode: String, CaseIterable {
    case epub = "EPUB"
    case text = "Text"
}

// MARK: - Errors

enum EPUBLoadError: Error, LocalizedError {
    case fileNotFound
    case invalidEPUB

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The EPUB file could not be found."
        case .invalidEPUB:
            return "The file is not a valid EPUB or is corrupted."
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewMode: EPUBViewMode = .text
    // Create a sample document for preview
    let document = Document(title: "Sample EPUB", content: "# Sample EPUB\n\nThis is extracted text from an EPUB document.")
    return EPUBDocumentView(document: document, viewMode: $viewMode)
        .frame(width: 800, height: 600)
}
