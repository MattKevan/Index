//
//  VecturaDB.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import Foundation
import VecturaKit
import VecturaMLXKit
import MLXEmbedders

actor VecturaDB {
    private var db: VecturaMLXKit?
    private var _isInitialized = false

    var isInitialized: Bool {
        get async {
            return _isInitialized
        }
    }

    func initialize() async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let modelCache = cacheDir.appendingPathComponent("huggingface")
        print("📁 Model cache directory: \(modelCache.path)")

        do {
            print("🔄 Initializing VecturaMLXKit with TaylorAI/bge-micro model...")

            let searchOptions = VecturaConfig.SearchOptions(
                defaultNumResults: 10,
                minThreshold: 0.7,
                hybridWeight: 0.5,
                k1: 1.2,
                b: 0.75
            )

            let config = VecturaConfig(
                name: "index-vector-db",
                directoryURL: nil,
                dimension: 384,  // bge-micro uses 384 dimensions
                searchOptions: searchOptions
            )

            let modelConfig = ModelConfiguration(id: "TaylorAI/bge-micro")

            db = try await VecturaMLXKit(
                config: config,
                modelConfiguration: modelConfig
            )
            _isInitialized = true
            print("✅ VecturaMLXKit initialized with TaylorAI/bge-micro (384-dim embeddings)")

        } catch {
            print("❌ VecturaMLXKit initialization failed: \(error)")
            print("   App will continue without embeddings (semantic search disabled).")
            _isInitialized = false
        }
    }

    func clearCacheAndReinitialize() async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let modelCache = cacheDir.appendingPathComponent("huggingface")

        print("🗑️ Clearing model cache at: \(modelCache.path)")
        try? FileManager.default.removeItem(at: modelCache)

        db = nil
        _isInitialized = false

        await initialize()
    }

    func addDocument(text: String) async throws -> UUID {
        guard _isInitialized, let db = db else {
            print("⚠️ VecturaMLXKit not initialized, skipping embedding for document")
            throw VecturaError.notInitialized
        }

        // VecturaMLXKit's addDocuments handles single documents too
        let ids = try await db.addDocuments(texts: [text], ids: nil)
        return ids[0]
    }

    func addDocuments(texts: [String]) async throws -> [UUID] {
        guard _isInitialized, let db = db else {
            print("⚠️ VecturaMLXKit not initialized, skipping embedding for \(texts.count) documents")
            throw VecturaError.notInitialized
        }

        // VecturaMLXKit handles embedding internally
        let ids = try await db.addDocuments(texts: texts, ids: nil)
        return ids
    }

    func search(
        query: String,
        numResults: Int = 10,
        threshold: Float = 0.7
    ) async throws -> [SearchResult] {
        guard _isInitialized else {
            print("⚠️ Cannot search: VectorDB not initialized")
            throw VecturaError.notInitialized
        }

        guard let db = db else {
            throw VecturaError.notInitialized
        }

        // VecturaMLXKit handles embedding and search
        let results = try await db.search(
            query: query,
            numResults: numResults,
            threshold: threshold
        )

        return results.map { result in
            SearchResult(
                id: result.id.uuidString,
                content: result.text,
                score: result.score
            )
        }
    }

    func deleteDocuments(ids: [UUID]) async throws {
        guard let db = db else {
            throw VecturaError.notInitialized
        }

        try await db.deleteDocuments(ids: ids)
    }

    func reset() async throws {
        guard let db = db else {
            throw VecturaError.notInitialized
        }

        try await db.reset()
    }
}

struct SearchResult {
    let id: String
    let content: String
    let score: Float
}

enum VecturaError: Error {
    case notInitialized
    case insertFailed
    case searchFailed
}
