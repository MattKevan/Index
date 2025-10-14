//
//  ProcessingQueue.swift
//  Index
//
//  Created by Claude Code
//

import Foundation
import Observation

@Observable
@MainActor
class ProcessingQueue {
    static let shared = ProcessingQueue()

    private(set) var tasks: [ProcessingTask] = []

    var hasActiveTasks: Bool {
        !tasks.isEmpty
    }

    private init() {}

    func addTask(id: String, documentTitle: String, type: TaskType) {
        // Don't add duplicate tasks
        guard !tasks.contains(where: { $0.id == id }) else {
            return
        }

        let task = ProcessingTask(id: id, documentTitle: documentTitle, type: type)
        tasks.append(task)
    }

    func updateProgress(id: String, current: Int, total: Int, status: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].currentStep = current
        tasks[index].totalSteps = total
        tasks[index].status = status
    }

    func completeTask(id: String) {
        tasks.removeAll { $0.id == id }
    }

    func cancelTask(id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].cancellationToken.cancel()
        tasks.removeAll { $0.id == id }
    }

    func cancelAllTasks() {
        for task in tasks {
            task.cancellationToken.cancel()
        }
        tasks.removeAll()
    }
}

@Observable
class ProcessingTask: Identifiable {
    let id: String
    let documentTitle: String
    let type: TaskType
    var currentStep: Int = 0
    var totalSteps: Int = 1
    var status: String = "Starting..."
    nonisolated let cancellationToken = CancellationToken()

    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    init(id: String, documentTitle: String, type: TaskType) {
        self.id = id
        self.documentTitle = documentTitle
        self.type = type
    }
}

enum TaskType {
    case processing  // Full document processing (chunking + embedding)
    case titleGeneration
    case summaryGeneration

    var icon: String {
        switch self {
        case .processing: return "doc.text.magnifyingglass"
        case .titleGeneration: return "textformat.size"
        case .summaryGeneration: return "text.alignleft"
        }
    }

    var displayName: String {
        switch self {
        case .processing: return "Processing"
        case .titleGeneration: return "Generating Title"
        case .summaryGeneration: return "Generating Summary"
        }
    }
}

class CancellationToken: @unchecked Sendable {
    private let _isCancelled = Atomic<Bool>(false)

    var isCancelled: Bool {
        _isCancelled.value
    }

    func cancel() {
        _isCancelled.value = true
    }
}

// Simple atomic wrapper for thread-safe access
final class Atomic<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    init(_ value: T) {
        _value = value
    }
}
