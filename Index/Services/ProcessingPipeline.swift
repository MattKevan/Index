//
//  ProcessingPipeline.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import Foundation
import SwiftData

@ModelActor
actor ProcessingPipeline {
    static let shared: ProcessingPipeline = {
        print("🔧 Creating ProcessingPipeline.shared...")
        let pipeline = ProcessingPipeline(modelContainer: sharedModelContainer)
        Task {
            print("🔧 Starting VectorDB initialization task...")
            await pipeline.initializeVectorDB()
            print("🔧 VectorDB initialization task completed")
        }
        return pipeline
    }()

    private let chunker = TextChunker()
    private var vectorDB: ChromaVectorDB?

    private func initializeVectorDB() async {
        print("🔧 ProcessingPipeline.initializeVectorDB() called")
        vectorDB = ChromaVectorDB()
        print("🔧 Calling ChromaVectorDB.initialize()...")
        await vectorDB?.initialize()
        print("🔧 ChromaVectorDB.initialize() returned")
    }

    func processDocument(documentID: PersistentIdentifier, cancellationToken: CancellationToken? = nil) async {
        // Fetch document in this actor's context
        guard let document = self[documentID, as: Document.self] else {
            print("❌ Cannot process: Document not found")
            return
        }

        let taskID = documentID.hashValue.description
        let docTitle = document.title

        print("🔄 Processing document: \(docTitle)")

        // Register task with queue
        await MainActor.run {
            ProcessingQueue.shared.addTask(id: taskID, documentTitle: docTitle, type: .processing)
        }

        defer {
            // Clean up task when done
            Task { @MainActor in
                ProcessingQueue.shared.completeTask(id: taskID)
            }
        }

        // Check for cancellation
        if cancellationToken?.isCancelled == true {
            print("⚠️ Processing cancelled: \(docTitle)")
            return
        }

        // Check if vector DB is initialized
        guard let vectorDB = vectorDB else {
            print("❌ Cannot process: Vector DB not available")
            document.processingStatus = .failed
            try? modelContext.save()
            return
        }

        let isReady = await vectorDB.isInitialized
        guard isReady else {
            print("❌ Cannot process: Vector DB not initialized yet. Please wait for initialization to complete.")
            document.processingStatus = .pending
            try? modelContext.save()
            return
        }

        // Update status
        document.processingStatus = .processing
        try? modelContext.save()

        await MainActor.run {
            ProcessingQueue.shared.updateProgress(id: taskID, current: 1, total: 3, status: "Chunking document...")
        }

        do {
            // 1. Chunk the document (use plain text for better embeddings)
            let plainText = document.plainTextContent
            let docID = document.id

            let chunks = await chunker.chunk(
                text: plainText,
                documentID: docID
            )

            print("   Chunked into \(chunks.count) segments")

            // Skip embedding if no chunks (empty document)
            if chunks.isEmpty {
                print("⚠️ Document has no content to embed, marking as processed")
                document.isProcessed = true
                document.processingStatus = .completed
                try? modelContext.save()
                return
            }

            // Check for cancellation
            if cancellationToken?.isCancelled == true {
                print("⚠️ Processing cancelled: \(docTitle)")
                return
            }

            await MainActor.run {
                ProcessingQueue.shared.updateProgress(id: taskID, current: 2, total: 3, status: "Generating embeddings...")
            }

            // 2. Store in vector DB (ChromaDB handles embedding internally)
            do {
                let texts = chunks.map { $0.content }
                let embeddingIDs = try await vectorDB.addDocuments(texts: texts)

                print("   Generated embeddings and stored \(embeddingIDs.count) chunks in vector DB")

                // 3. Update chunks with their embedding IDs
                for (index, chunk) in chunks.enumerated() {
                    chunk.embeddingID = embeddingIDs[index].uuidString

                    // Report progress periodically
                    if index % 5 == 0 {
                        await MainActor.run {
                            ProcessingQueue.shared.updateProgress(
                                id: taskID,
                                current: 2,
                                total: 3,
                                status: "Processing chunk \(index + 1) of \(chunks.count)"
                            )
                        }
                    }

                    // Check for cancellation
                    if cancellationToken?.isCancelled == true {
                        print("⚠️ Processing cancelled: \(docTitle)")
                        return
                    }
                }
            } catch {
                print("⚠️ Failed to generate embeddings: \(error)")
                print("   Document processed but not indexed for semantic search")
                throw ProcessingError.embeddingFailed
            }

            await MainActor.run {
                ProcessingQueue.shared.updateProgress(id: taskID, current: 3, total: 3, status: "Finalizing...")
            }

            // 4. Mark as processed
            document.isProcessed = true
            document.processingStatus = .completed
            try? modelContext.save()

            print("✅ Completed: \(docTitle)")

        } catch {
            print("❌ Processing failed: \(error)")
            document.processingStatus = .failed
            try? modelContext.save()
        }
    }

    // Get the vector DB for RAG queries
    func getVectorDB() -> ChromaVectorDB? {
        return vectorDB
    }

    // Check if ready to process documents
    func isReady() async -> Bool {
        guard let vectorDB = vectorDB else {
            return false
        }
        return await vectorDB.isInitialized
    }

    // Process all unprocessed documents
    func processAllUnprocessedDocuments() async {
        print("🔍 Scanning for unprocessed documents...")

        // Fetch all documents that need processing
        let descriptor = FetchDescriptor<Document>(
            predicate: #Predicate { document in
                document.isProcessed == false
            }
        )

        do {
            let unprocessedDocs = try modelContext.fetch(descriptor)
            print("📊 Found \(unprocessedDocs.count) documents needing processing")

            for document in unprocessedDocs {
                let documentID = document.persistentModelID
                let cancellationToken = CancellationToken()

                // Process each document in background
                Task.detached(priority: .utility) {
                    await ProcessingPipeline.shared.processDocument(
                        documentID: documentID,
                        cancellationToken: cancellationToken
                    )
                }
            }

            if unprocessedDocs.isEmpty {
                print("✅ All documents are up to date")
            }

        } catch {
            print("❌ Failed to fetch unprocessed documents: \(error)")
        }
    }

    // Check for documents missing AI-generated content (titles/summaries)
    func processDocumentsMissingMetadata() async {
        print("🔍 Scanning for documents missing titles or summaries...")

        let descriptor = FetchDescriptor<Document>()

        do {
            let allDocs = try modelContext.fetch(descriptor)

            // Collect document IDs that need metadata generation
            var documentsNeedingMetadata: [(id: PersistentIdentifier, needsTitle: Bool, needsSummary: Bool)] = []

            for document in allDocs {
                let needsTitle = document.title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                document.title == "Untitled"
                let needsSummary = document.summary == nil || document.summary?.isEmpty == true
                let hasContent = !document.content.trimmingCharacters(in: .whitespaces).isEmpty

                if hasContent && (needsTitle || needsSummary) {
                    documentsNeedingMetadata.append((
                        id: document.persistentModelID,
                        needsTitle: needsTitle,
                        needsSummary: needsSummary
                    ))
                }
            }

            print("   Found \(documentsNeedingMetadata.count) documents needing metadata")

            // Generate metadata for each document in background tasks
            for docInfo in documentsNeedingMetadata {
                Task.detached(priority: .utility) {
                    await self.generateMetadataForDocument(
                        documentID: docInfo.id,
                        needsTitle: docInfo.needsTitle,
                        needsSummary: docInfo.needsSummary
                    )
                }
            }

        } catch {
            print("❌ Failed to fetch documents: \(error)")
        }
    }

    private func generateMetadataForDocument(
        documentID: PersistentIdentifier,
        needsTitle: Bool,
        needsSummary: Bool
    ) async {
        guard let document = self[documentID, as: Document.self] else {
            return
        }

        let ragEngine = RAGEngine()
        let plainText = document.plainTextContent
        let currentTitle = document.title

        // Generate title if needed
        if needsTitle {
            do {
                let generatedTitle = try await ragEngine.generateTitle(
                    from: plainText,
                    documentTitle: currentTitle
                )
                document.title = generatedTitle
                try? modelContext.save()
                print("   ✅ Generated title for: \(generatedTitle)")
            } catch {
                print("   ⚠️ Title generation failed: \(error)")
            }
        }

        // Generate summary if needed
        if needsSummary {
            let generatedSummary = await ragEngine.generateSummary(
                from: plainText,
                documentTitle: document.title
            )
            if !generatedSummary.isEmpty {
                document.summary = generatedSummary
                try? modelContext.save()
                print("   ✅ Generated summary for: \(document.title)")
            }
        }
    }
}

enum ProcessingError: Error {
    case vectorDBNotInitialized
    case chunkingFailed
    case embeddingFailed
}
