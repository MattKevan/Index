//
//  ProcessingPipeline.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import Foundation
import SwiftData

actor ProcessingPipeline {
    static let shared = ProcessingPipeline()

    private let chunker = TextChunker()
    private var vectorDB: VecturaDB?

    private init() {
        Task {
            await initializeVectorDB()
        }
    }

    private func initializeVectorDB() async {
        vectorDB = VecturaDB()
        await vectorDB?.initialize()
    }

    func processDocument(_ document: Document) async {
        print("🔄 Processing document: \(document.title)")

        // Check if vector DB is initialized
        guard let vectorDB = vectorDB else {
            print("❌ Cannot process: Vector DB not available")
            await MainActor.run {
                document.processingStatus = .failed
            }
            return
        }

        let isReady = await vectorDB.isInitialized
        guard isReady else {
            print("❌ Cannot process: Vector DB not initialized yet. Please wait for initialization to complete.")
            await MainActor.run {
                document.processingStatus = .pending
            }
            return
        }

        // Update status
        await MainActor.run {
            document.processingStatus = .processing
        }

        do {
            // 1. Chunk the document
            let chunks = await chunker.chunk(
                text: document.content,
                documentID: document.id
            )

            print("   Chunked into \(chunks.count) segments")

            // 2. Store in vector DB (VecturaMLXKit handles embedding internally)
            do {
                let texts = chunks.map { $0.content }
                let embeddingIDs = try await vectorDB.addDocuments(texts: texts)

                print("   Generated embeddings and stored \(embeddingIDs.count) chunks in vector DB")

                // 3. Update chunks with their embedding IDs
                for (index, chunk) in chunks.enumerated() {
                    chunk.embeddingID = embeddingIDs[index].uuidString
                }
            } catch {
                print("⚠️ Failed to generate embeddings: \(error)")
                print("   Document processed but not indexed for semantic search")
                throw ProcessingError.embeddingFailed
            }

            // 4. Mark as processed
            await MainActor.run {
                document.isProcessed = true
                document.processingStatus = .completed
            }

            print("✅ Completed: \(document.title)")

        } catch {
            print("❌ Processing failed: \(error)")

            await MainActor.run {
                document.processingStatus = .failed
            }
        }
    }

    // Get the vector DB for RAG queries
    func getVectorDB() -> VecturaDB? {
        return vectorDB
    }

    // Check if ready to process documents
    func isReady() async -> Bool {
        guard let vectorDB = vectorDB else {
            return false
        }
        return await vectorDB.isInitialized
    }
}

enum ProcessingError: Error {
    case vectorDBNotInitialized
    case chunkingFailed
    case embeddingFailed
}
