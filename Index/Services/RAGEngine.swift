//
//  RAGEngine.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import Foundation
import FoundationModels
import Observation

@Observable
class RAGEngine {
    private var session: LanguageModelSession?
    private var vectorDB: VecturaDB?

    var isAvailable: Bool = false

    init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            session = LanguageModelSession(
                instructions: """
                You are a helpful assistant for a personal knowledge management system.
                Answer questions based on the provided context from the user's documents.
                Always cite your sources by mentioning the document title.
                Be concise but thorough. If the context doesn't contain enough information, say so.
                """
            )
            isAvailable = true
            print("✅ Foundation Models available")

        case .unavailable(let reason):
            isAvailable = false
            print("❌ Foundation Models unavailable: \(reason)")
        }

        // Get vector DB from processing pipeline
        vectorDB = await ProcessingPipeline.shared.getVectorDB()
    }

    func query(_ question: String) -> AsyncThrowingStream<RAGResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    print("🔍 RAG Query: \"\(question)\"")

                    guard isAvailable, let session = session else {
                        print("❌ Foundation Models not available")
                        throw RAGError.modelNotAvailable
                    }

                    guard let vectorDB = vectorDB else {
                        print("❌ Vector DB not available")
                        throw RAGError.vectorDBNotAvailable
                    }

                    print("   Searching vector DB...")

                    // 1. Search vector DB (VecturaMLXKit handles embedding internally)
                    let searchResults = try await vectorDB.search(
                        query: question,
                        numResults: 10,  // Get more results for better coverage
                        threshold: 0.7 as Float
                    )

                    print("   Found \(searchResults.count) relevant chunks")
                    for (index, result) in searchResults.enumerated() {
                        print("     [\(index + 1)] Score: \(String(format: "%.3f", result.score)) - \(result.content.prefix(100))...")
                    }

                    guard !searchResults.isEmpty else {
                        print("❌ No relevant documents found")
                        throw RAGError.noRelevantDocuments
                    }

                    // 2. Summarize chunks if needed to fit context window
                    let context: String
                    if searchResults.count > 5 {
                        print("   Large result set (\(searchResults.count) chunks) - performing summarization...")
                        context = try await summarizeChunks(searchResults, question: question, session: session)
                    } else {
                        context = buildContext(from: searchResults)
                    }

                    print("   Context size: \(context.count) chars (~\(context.count / 4) tokens)")

                    // 3. Create prompt
                    let prompt = """
                    Based on the following excerpts from my notes:

                    \(context)

                    Question: \(question)

                    Please provide a helpful answer based on the context above.
                    """

                    print("   Streaming LLM response...")

                    // 4. Stream response
                    let stream = session.streamResponse(to: prompt)

                    for try await snapshot in stream {
                        continuation.yield(RAGResponse(
                            partialAnswer: snapshot.content,
                            isComplete: false,
                            sources: searchResults.map { result in
                                Source(
                                    documentTitle: "Document",
                                    documentID: result.id,
                                    excerpt: result.content,
                                    relevanceScore: result.score
                                )
                            }
                        ))
                    }

                    // Final complete response
                    let finalResponse = try await stream.collect()
                    print("✅ RAG Query completed")

                    continuation.yield(RAGResponse(
                        partialAnswer: finalResponse.content,
                        isComplete: true,
                        sources: searchResults.map { result in
                            Source(
                                documentTitle: "Document",
                                documentID: result.id,
                                excerpt: result.content,
                                relevanceScore: result.score
                            )
                        }
                    ))

                    continuation.finish()

                } catch {
                    print("❌ RAG Query failed: \(error)")
                    if let ragError = error as? RAGError {
                        print("   Error type: \(ragError)")
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildContext(from results: [SearchResult]) -> String {
        var context = ""
        let maxCharsPerResult = 800  // Limit each chunk to ~200 tokens

        for (index, result) in results.enumerated() {
            // Truncate content if too long
            let content = result.content.count > maxCharsPerResult
                ? String(result.content.prefix(maxCharsPerResult)) + "..."
                : result.content

            context += """
            [Source \(index + 1)]
            \(content)

            ---

            """
        }

        // Final safety check - limit total context to ~2400 chars (~600 tokens)
        if context.count > 2400 {
            context = String(context.prefix(2400)) + "\n\n[Context truncated...]"
        }

        return context
    }

    private func summarizeChunks(_ results: [SearchResult], question: String, session: LanguageModelSession) async throws -> String {
        // Split into batches of 3-4 chunks
        let batchSize = 3
        var summaries: [String] = []

        print("   Summarizing in batches of \(batchSize)...")

        for batchIndex in stride(from: 0, to: results.count, by: batchSize) {
            let batch = Array(results[batchIndex..<min(batchIndex + batchSize, results.count)])
            let batchContext = buildContext(from: batch)

            let summarizePrompt = """
            Summarize the following excerpts from notes, focusing on information relevant to: "\(question)"

            Be concise but preserve key facts and details.

            \(batchContext)
            """

            print("     Batch \(batchIndex / batchSize + 1): \(batch.count) chunks")

            let stream = session.streamResponse(to: summarizePrompt)
            let response = try await stream.collect()
            let summary = response.content

            summaries.append(summary)
            print("     Summary \(batchIndex / batchSize + 1): \(summary.count) chars")
        }

        // If we have multiple summaries, combine them
        if summaries.count > 1 {
            print("   Combining \(summaries.count) summaries...")

            let combinedSummaries = summaries.enumerated()
                .map { "[Section \($0.offset + 1)]\n\($0.element)" }
                .joined(separator: "\n\n---\n\n")

            // If still too large, do a final summarization pass
            if combinedSummaries.count > 2400 {
                print("   Final summarization pass...")

                let finalPrompt = """
                Consolidate these summaries into a single coherent summary relevant to: "\(question)"

                \(combinedSummaries)
                """

                let stream = session.streamResponse(to: finalPrompt)
                let finalResponse = try await stream.collect()
                return finalResponse.content
            }

            return combinedSummaries
        }

        return summaries.first ?? ""
    }
}

struct RAGResponse {
    let partialAnswer: String
    let isComplete: Bool
    let sources: [Source]
}

struct Source: Identifiable {
    let id = UUID()
    let documentTitle: String
    let documentID: String
    let excerpt: String
    let relevanceScore: Float
}

enum RAGError: Error, LocalizedError {
    case modelNotAvailable
    case vectorDBNotAvailable
    case noRelevantDocuments
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Foundation Models not available. Please enable on-device AI in System Settings."
        case .vectorDBNotAvailable:
            return "Vector database not initialized. Embeddings may not be available."
        case .noRelevantDocuments:
            return "No relevant documents found for your query. Try different search terms."
        case .queryFailed:
            return "Query failed. Please try again."
        }
    }
}
