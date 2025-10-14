//
//  DocumentTransformationService.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import Foundation
import SwiftData

/// Actor-isolated service for transforming documents using Foundation Models
actor DocumentTransformationService {
    static let shared = DocumentTransformationService()

    private let ragEngine = RAGEngine()

    // Context window budget: 4,096 tokens total
    // Budget breakdown:
    // - Content: 2,400 chars (~600 tokens)
    // - Transformation prompt: ~100-200 tokens
    // - System instructions: ~50 tokens
    // - Response: ~1,500 tokens
    // - Safety margin: ~1,800 tokens
    private let maxCharsPerChunk = 2400

    private init() {}

    // MARK: - Public API

    /// Transform a document using a preset template
    /// - Parameters:
    ///   - document: Document to transform
    ///   - preset: Transformation preset with instructions
    ///   - progressCallback: Callback for progress updates (current, total, status)
    /// - Returns: Transformed content as markdown string
    func transformDocument(
        document: Document,
        preset: TransformationPreset,
        progressCallback: @escaping (Int, Int, String) -> Void
    ) async throws -> String {
        // Load document content
        let content = try await document.loadContent()

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransformationError.emptyContent
        }

        print("🔄 Transforming document: \(document.title)")
        print("   Preset: \(preset.name)")
        print("   Content length: \(content.count) chars")

        // Check if content fits in single chunk
        if content.count <= maxCharsPerChunk {
            print("   Single chunk processing")
            progressCallback(1, 1, "Transforming...")

            do {
                let result = try await ragEngine.performTransformation(
                    prompt: preset.systemPrompt,
                    content: content
                )

                progressCallback(1, 1, "Complete")
                print("✅ Transformation complete")
                return result

            } catch let error as RAGError {
                // If context window still exceeded, fall back to chunking
                if case .contextWindowExceeded = error {
                    print("⚠️ Single chunk still too large - falling back to multi-chunk")
                    return try await transformLargeDocument(
                        content: content,
                        prompt: preset.systemPrompt,
                        progressCallback: progressCallback
                    )
                }
                throw error
            }
        }

        // Multi-chunk processing
        print("   Multi-chunk processing required")
        return try await transformLargeDocument(
            content: content,
            prompt: preset.systemPrompt,
            progressCallback: progressCallback
        )
    }

    /// Check if a cached transformation needs regeneration
    /// - Parameters:
    ///   - version: Cached transformation version
    ///   - currentContentHash: Current hash of source document
    /// - Returns: True if regeneration is needed
    func needsRegeneration(version: DocumentVersion, currentContentHash: String) -> Bool {
        guard let cachedHash = version.createdFromHash else {
            // No hash stored - assume needs regeneration
            return true
        }

        return cachedHash != currentContentHash
    }

    // MARK: - Large Document Handling

    /// Transform a large document by chunking and sequential processing
    private func transformLargeDocument(
        content: String,
        prompt: String,
        progressCallback: @escaping (Int, Int, String) -> Void
    ) async throws -> String {
        // Split into chunks
        let chunks = chunkForTransformation(content: content)

        print("   Split into \(chunks.count) chunks")
        progressCallback(0, chunks.count, "Processing chunk 1/\(chunks.count)...")

        var results: [String] = []
        var previousContext = ""

        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1
            print("   Processing chunk \(chunkNumber)/\(chunks.count)")
            progressCallback(chunkNumber, chunks.count, "Processing chunk \(chunkNumber)/\(chunks.count)...")

            // Build contextual prompt that includes previous context and chunk
            // NOTE: We pass the full contextual prompt as "prompt" and empty content
            // This way the session doesn't accumulate history between chunks
            let fullPrompt = buildFullPromptWithContext(
                basePrompt: prompt,
                chunk: chunk,
                previousContext: previousContext,
                isFirstChunk: index == 0,
                isLastChunk: index == chunks.count - 1,
                chunkNumber: chunkNumber,
                totalChunks: chunks.count
            )

            // Transform this chunk using standalone prompt (no session history accumulation)
            let result = try await ragEngine.performTransformation(
                prompt: fullPrompt,
                content: "" // Content already included in prompt
            )

            results.append(result)

            // Create summary of this result for next chunk's context
            // Keep it short to preserve context window space
            previousContext = createContextSummary(result, maxLength: 150)

            print("   ✓ Chunk \(chunkNumber) complete (\(result.count) chars)")
        }

        // Combine all results
        let combined = results.joined(separator: "\n\n")

        print("✅ Large document transformation complete")
        print("   Total output: \(combined.count) chars")

        progressCallback(chunks.count, chunks.count, "Complete")

        return combined
    }

    /// Split content into chunks suitable for transformation
    private func chunkForTransformation(content: String) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        // Split by sentences for natural boundaries
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))

        for sentence in sentences {
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedSentence.isEmpty else { continue }

            // Add period back if this was a sentence-ending split
            let sentenceWithPunctuation = trimmedSentence.hasSuffix(".") || trimmedSentence.hasSuffix("!") || trimmedSentence.hasSuffix("?")
                ? trimmedSentence
                : trimmedSentence + "."

            // Check if adding this sentence would exceed chunk size
            let testChunk = currentChunk.isEmpty
                ? sentenceWithPunctuation
                : currentChunk + " " + sentenceWithPunctuation

            if testChunk.count > maxCharsPerChunk && !currentChunk.isEmpty {
                // Save current chunk and start new one
                chunks.append(currentChunk)
                currentChunk = sentenceWithPunctuation
            } else {
                currentChunk = testChunk
            }
        }

        // Add final chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [content] : chunks
    }

    /// Build a full prompt that includes previous context and current chunk content
    private func buildFullPromptWithContext(
        basePrompt: String,
        chunk: String,
        previousContext: String,
        isFirstChunk: Bool,
        isLastChunk: Bool,
        chunkNumber: Int,
        totalChunks: Int
    ) -> String {
        var prompt = ""

        // Add context from previous chunks (keep brief)
        if !previousContext.isEmpty {
            prompt += "Context from previous section: \(previousContext)\n\n"
        }

        // Add position information
        if totalChunks > 1 {
            if isFirstChunk {
                prompt += "This is the first section of a \(totalChunks)-part document.\n\n"
            } else if isLastChunk {
                prompt += "This is the final section (part \(chunkNumber) of \(totalChunks)).\n\n"
            } else {
                prompt += "This is section \(chunkNumber) of \(totalChunks).\n\n"
            }
        }

        // Add base transformation instructions
        prompt += basePrompt
        prompt += "\n\n"

        // Add the chunk content directly
        prompt += "Content to transform:\n"
        prompt += chunk
        prompt += "\n\n"

        // Add special instructions for multi-chunk
        if totalChunks > 1 {
            if !isLastChunk {
                prompt += "Note: Continue from where you left off. More content will follow in the next section."
            } else {
                prompt += "Note: This is the final section. Provide a concluding summary if appropriate."
            }
        }

        return prompt
    }

    /// Create a brief summary of transformed content for context
    private func createContextSummary(_ content: String, maxLength: Int) -> String {
        // Take first few sentences or first N characters
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var summary = ""

        for sentence in sentences.prefix(3) {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if (summary + trimmed).count > maxLength {
                break
            }

            summary += trimmed + ". "
        }

        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Types

enum TransformationError: Error, LocalizedError {
    case emptyContent
    case transformationFailed(message: String)
    case contextWindowExceeded

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Cannot transform empty document."
        case .transformationFailed(let message):
            return "Transformation failed: \(message)"
        case .contextWindowExceeded:
            return "Document is too large to process. Please try with a smaller document."
        }
    }
}
