//
//  ChromaVectorDB.swift
//  Index
//
//  ChromaDB wrapper for vector operations with local embeddings
//

import Foundation
import Chroma

actor ChromaVectorDB {
    private var isChromaInitialized = false
    private var embedder: ChromaEmbedder?
    private var collectionName = "document-chunks"
    private var _isInitialized = false

    var isInitialized: Bool {
        get async {
            return _isInitialized
        }
    }

    func initialize() async {
        print("🔄 ChromaVectorDB.initialize() called")

        // Get storage path
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let chromaPath = documentsDir.appendingPathComponent("ChromaDB/index-vector-db")

        print("📁 ChromaDB storage path: \(chromaPath.path)")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: chromaPath, withIntermediateDirectories: true)

        do {
            // Get selected embedding model
            let selectedModel = await MainActor.run { EmbeddingModelConfig.shared.selectedModel }
            let displayName = await MainActor.run { selectedModel.displayName }
            let dimensions = await MainActor.run { selectedModel.dimensions }
            let sizeInMB = await MainActor.run { selectedModel.sizeInMB }
            let systemRAM = await MainActor.run { EmbeddingModelConfig.shared.systemRAMGB }

            print("🔄 Initializing ChromaDB with \(displayName)...")
            print("   Model: \(selectedModel.rawValue)")
            print("   Dimensions: \(dimensions)")
            print("   Size: \(sizeInMB)MB")
            print("   System RAM: \(systemRAM)GB")

            // Check if model is suitable for system
            if let warning = await MainActor.run(body: { EmbeddingModelConfig.shared.getRecommendationMessage() }) {
                print("⚠️  \(warning)")
            }

            // Initialize Chroma with persistent storage
            try Chroma.initializeWithPath(path: chromaPath.path, allowReset: false)
            isChromaInitialized = true

            // Convert our EmbeddingModel enum to Chroma's model enum
            // Note: ChromaDB may not have all models, fallback to available ones
            let chromaModel: ChromaEmbedder.EmbeddingModel
            switch selectedModel {
            case .miniLML6:
                chromaModel = .miniLML6
            case .miniLML12:
                chromaModel = .miniLML12
            case .bgeSmall:
                chromaModel = .bgeSmall
            }

            // Initialize embedder with selected model
            embedder = try ChromaEmbedder(model: chromaModel)
            try await embedder?.loadModel()

            // Create or get collection
            do {
                _ = try Chroma.createCollection(name: collectionName)
                print("✅ Created new collection: \(collectionName)")
            } catch {
                // Collection might already exist
                print("ℹ️  Using existing collection: \(collectionName)")
            }

            _isInitialized = true
            print("✅ ChromaDB initialized with \(displayName)")
            print("   (\(dimensions)-dim embeddings)")

        } catch {
            print("❌ ChromaDB initialization failed: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")

            if let nsError = error as? NSError {
                print("   Domain: \(nsError.domain)")
                print("   Code: \(nsError.code)")
                print("   UserInfo: \(nsError.userInfo)")
            }

            _isInitialized = false
        }
    }

    /// Add a single document to the vector database
    func addDocument(text: String) async throws -> UUID {
        guard _isInitialized else {
            print("⚠️ ChromaDB not initialized, skipping embedding")
            throw ChromaError.notInitialized
        }

        guard let embedder = embedder else {
            throw ChromaError.notInitialized
        }

        let id = UUID().uuidString
        let count = try await embedder.addDocuments(
            to: collectionName,
            ids: [id],
            texts: [text]
        )

        print("   Added 1 document to ChromaDB (ID: \(id))")
        return UUID(uuidString: id)!
    }

    /// Add multiple documents to the vector database
    func addDocuments(texts: [String]) async throws -> [UUID] {
        guard _isInitialized else {
            print("⚠️ ChromaDB not initialized, skipping embedding for \(texts.count) documents")
            throw ChromaError.notInitialized
        }

        guard let embedder = embedder else {
            throw ChromaError.notInitialized
        }

        // Generate UUIDs for each document
        let ids = texts.map { _ in UUID().uuidString }

        // Add documents with embeddings (ChromaEmbedder handles embedding internally)
        let count = try await embedder.addDocuments(
            to: collectionName,
            ids: ids,
            texts: texts
        )

        print("   Added \(count) documents to ChromaDB")

        // Convert string IDs back to UUIDs
        return ids.compactMap { UUID(uuidString: $0) }
    }

    /// Search for similar documents using semantic similarity
    func search(
        query: String,
        numResults: Int = 10,
        threshold: Float = 0.7
    ) async throws -> [SearchResult] {
        guard _isInitialized else {
            print("⚠️ Cannot search: ChromaDB not initialized")
            throw ChromaError.notInitialized
        }

        guard let embedder = embedder else {
            throw ChromaError.notInitialized
        }

        // ChromaEmbedder handles query embedding internally
        let queryResult = try await embedder.queryCollection(
            collectionName,
            queryText: query,
            nResults: UInt32(numResults)
        )

        // QueryResult contains nested arrays for batch queries
        // We're doing a single query, so use first element
        var searchResults: [SearchResult] = []

        guard !queryResult.ids.isEmpty else {
            return []
        }

        let ids = queryResult.ids[0]  // First query results
        let documents = queryResult.documents[0]  // First query results

        for i in 0..<ids.count {
            // QueryResult doesn't have distances in the format we expected
            // We'll use a default high similarity score since ChromaDB returns them sorted
            let score: Float = 1.0 - (Float(i) * 0.05)  // Decreasing score

            // Filter by threshold
            if score >= threshold {
                searchResults.append(SearchResult(
                    id: ids[i],
                    content: documents[i] ?? "",
                    score: score
                ))
            }
        }

        return searchResults
    }

    /// Delete documents by their UUIDs
    func deleteDocuments(ids: [UUID]) async throws {
        guard _isInitialized else {
            throw ChromaError.notInitialized
        }

        let stringIds = ids.map { $0.uuidString }
        try Chroma.deleteDocuments(
            collectionName: collectionName,
            ids: stringIds
        )
        print("   Deleted \(ids.count) documents from ChromaDB")
    }

    /// Reset the entire vector database (delete all documents)
    func reset() async throws {
        guard _isInitialized else {
            throw ChromaError.notInitialized
        }

        try Chroma.deleteCollection(collectionName: collectionName)
        print("   Deleted collection: \(collectionName)")

        // Recreate collection
        _ = try Chroma.createCollection(name: collectionName)
        print("   Recreated collection: \(collectionName)")
    }

    /// Clear the ChromaDB storage directory
    func clearDatabase() async {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let chromaPath = documentsDir.appendingPathComponent("ChromaDB/index-vector-db")

        print("🗑️ Clearing ChromaDB at: \(chromaPath.path)")

        do {
            if FileManager.default.fileExists(atPath: chromaPath.path) {
                try FileManager.default.removeItem(at: chromaPath)
                print("✅ ChromaDB storage cleared")
            } else {
                print("ℹ️  ChromaDB storage does not exist")
            }
        } catch {
            print("⚠️ Failed to clear ChromaDB: \(error)")
        }

        _isInitialized = false
    }
}

/// Search result structure matching VecturaDB interface
struct SearchResult {
    let id: String
    let content: String
    let score: Float
}

/// ChromaDB error types
enum ChromaError: Error {
    case notInitialized
    case insertFailed
    case searchFailed
    case modelLoadFailed
}
