//
//  MarkdownRenderingPipeline.swift
//  Index
//
//  Background rendering pipeline for pre-computing markdown previews
//

import Foundation
import SwiftData
import MarkdownUI

/// Background pipeline that proactively renders markdown previews for documents
/// Rendered content is stored in memory with hash-based cache validation
@MainActor
class MarkdownRenderingPipeline {
    static let shared = MarkdownRenderingPipeline()

    // Cache of pre-rendered markdown content
    private var renderCache: [UUID: CachedRender] = [:]

    // Queue of documents waiting to be rendered
    private var renderQueue: [RenderJob] = []

    // Currently rendering document
    private var currentTask: Task<Void, Never>?

    // Configuration
    private let maxCacheSize = 100  // Maximum number of cached renders
    private let largeDocumentThreshold = 50000  // Skip rendering above this size

    private init() {
        print("📄 MarkdownRenderingPipeline initialized")
    }

    /// Enqueue a document for background rendering
    /// - Parameters:
    ///   - documentId: Document UUID
    ///   - content: Document markdown content
    ///   - contentHash: SHA256 hash of content for cache validation
    ///   - priority: Whether to render immediately or add to queue
    func enqueueRender(
        documentId: UUID,
        content: String,
        contentHash: String,
        priority: RenderPriority = .normal
    ) {
        // Check if already cached and valid
        if let cached = renderCache[documentId], cached.contentHash == contentHash {
            print("📄 Document \(documentId) already rendered and cached")
            return
        }

        // Skip very large documents
        if content.count > largeDocumentThreshold {
            print("📄 Skipping render for large document \(documentId) (\(content.count) chars)")
            return
        }

        let job = RenderJob(
            documentId: documentId,
            content: content,
            contentHash: contentHash
        )

        // Add to queue based on priority
        switch priority {
        case .immediate:
            // Cancel current task and render immediately
            currentTask?.cancel()
            renderQueue.insert(job, at: 0)
            startNextRender()

        case .normal:
            // Add to end of queue if not already queued
            if !renderQueue.contains(where: { $0.documentId == documentId }) {
                renderQueue.append(job)
                print("📄 Enqueued document \(documentId) for rendering (queue size: \(renderQueue.count))")
            }

            // Start processing if idle
            if currentTask == nil {
                startNextRender()
            }
        }
    }

    /// Get cached render for a document
    /// - Parameters:
    ///   - documentId: Document UUID
    ///   - contentHash: Expected content hash for validation
    /// - Returns: Pre-rendered MarkdownContent if cache is valid, nil otherwise
    func getCachedRender(documentId: UUID, contentHash: String) -> MarkdownContent? {
        guard let cached = renderCache[documentId] else {
            print("📄 Cache miss for document \(documentId)")
            return nil
        }

        // Validate hash
        guard cached.contentHash == contentHash else {
            print("📄 Cache invalid for document \(documentId) (hash mismatch)")
            renderCache.removeValue(forKey: documentId)
            return nil
        }

        // Update last accessed time for LRU eviction
        renderCache[documentId]?.lastAccessed = Date()
        print("📄 Cache hit for document \(documentId)")

        return cached.content
    }

    /// Invalidate cache for a document (call when content changes)
    func invalidateCache(documentId: UUID) {
        renderCache.removeValue(forKey: documentId)
        print("📄 Invalidated cache for document \(documentId)")
    }

    /// Clear all cached renders
    func clearCache() {
        renderCache.removeAll()
        print("📄 Cleared all render cache")
    }

    /// Get cache statistics
    func getCacheStats() -> CacheStats {
        CacheStats(
            cachedCount: renderCache.count,
            queueSize: renderQueue.count,
            isRendering: currentTask != nil
        )
    }

    // MARK: - Private Methods

    private func startNextRender() {
        guard currentTask == nil else { return }
        guard !renderQueue.isEmpty else { return }

        let job = renderQueue.removeFirst()

        currentTask = Task.detached(priority: .utility) { [weak self] in
            await self?.renderDocument(job: job)
        }
    }

    private func renderDocument(job: RenderJob) async {
        print("📄 Background rendering document \(job.documentId) (\(job.content.count) chars)...")

        // Parse markdown off the main thread
        let parsed = await renderMarkdownContent(job.content, contentHash: job.contentHash)

        // Cache the result on main actor
        await MainActor.run {
            self.cacheRender(
                documentId: job.documentId,
                content: parsed,
                contentHash: job.contentHash
            )

            print("✅ Background render completed for \(job.documentId)")

            // Mark task as complete and process next
            currentTask = nil
            startNextRender()
        }
    }

    /// Internal render method that does the actual markdown parsing
    nonisolated func renderMarkdownContent(_ content: String, contentHash: String) async -> MarkdownContent {
        // Parse markdown OFF the main thread
        print("📄 Parsing markdown (\(content.count) chars)...")
        let parsed = MarkdownContent(content)
        print("✅ Markdown parsed successfully")
        return parsed
    }

    /// Store rendered content in cache
    func cacheRender(documentId: UUID, content: MarkdownContent, contentHash: String) {
        // Evict oldest entries if cache is full
        if renderCache.count >= maxCacheSize {
            evictOldestEntries(count: 10)
        }

        renderCache[documentId] = CachedRender(
            content: content,
            contentHash: contentHash,
            renderedAt: Date(),
            lastAccessed: Date()
        )

        print("📄 Cached render for document \(documentId) (cache size: \(renderCache.count))")
    }

    private func evictOldestEntries(count: Int) {
        // Sort by last accessed time and remove oldest
        let sorted = renderCache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let toRemove = sorted.prefix(count)

        for (id, _) in toRemove {
            renderCache.removeValue(forKey: id)
        }

        print("📄 Evicted \(count) oldest cache entries")
    }
}

// MARK: - Supporting Types

struct RenderJob {
    let documentId: UUID
    let content: String
    let contentHash: String
}

struct CachedRender {
    let content: MarkdownContent
    let contentHash: String
    let renderedAt: Date
    var lastAccessed: Date
}

enum RenderPriority {
    case immediate  // Cancel current and render now
    case normal     // Add to queue
}

struct CacheStats {
    let cachedCount: Int
    let queueSize: Int
    let isRendering: Bool
}
