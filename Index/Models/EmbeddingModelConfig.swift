//
//  EmbeddingModelConfig.swift
//  Index
//
//  Embedding model configuration and auto-detection
//

import Foundation

/// Supported embedding models with their specifications
enum EmbeddingModel: String, Codable, CaseIterable {
    case miniLML6 = "all-MiniLM-L6-v2"
    case miniLML12 = "all-MiniLM-L12-v2"
    case bgeSmall = "BAAI/bge-small-en-v1.5"

    /// Model dimensions
    var dimensions: Int {
        switch self {
        case .miniLML6:
            return 384
        case .miniLML12:
            return 384
        case .bgeSmall:
            return 384
        }
    }

    /// Approximate model size in MB
    var sizeInMB: Int {
        switch self {
        case .miniLML6:
            return 80
        case .miniLML12:
            return 120
        case .bgeSmall:
            return 130
        }
    }

    /// Quality rating (1-5, 5 being best)
    var qualityRating: Int {
        switch self {
        case .miniLML6:
            return 3
        case .miniLML12:
            return 3
        case .bgeSmall:
            return 4
        }
    }

    /// Minimum recommended RAM in GB
    var minRecommendedRAMGB: Int {
        switch self {
        case .miniLML6:
            return 4
        case .miniLML12:
            return 8
        case .bgeSmall:
            return 8
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .miniLML6:
            return "MiniLM-L6 (Fastest)"
        case .miniLML12:
            return "MiniLM-L12 (Fast)"
        case .bgeSmall:
            return "BGE-Small (Balanced)"
        }
    }

    /// Short description
    var description: String {
        switch self {
        case .miniLML6:
            return "Fastest, smallest model for low-end systems"
        case .miniLML12:
            return "Lightweight model, good for systems with limited RAM"
        case .bgeSmall:
            return "Better quality, balanced performance, recommended for most users"
        }
    }
}

/// Manages embedding model selection and configuration
class EmbeddingModelConfig {
    static let shared = EmbeddingModelConfig()

    private let userDefaultsKey = "selectedEmbeddingModel"

    /// Currently selected embedding model
    var selectedModel: EmbeddingModel {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
               let model = EmbeddingModel(rawValue: rawValue) {
                return model
            }
            // Auto-select on first launch
            return autoSelectModel()
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            print("📊 Embedding model changed to: \(newValue.displayName)")
        }
    }

    private init() {
        // Perform auto-selection on first launch
        if UserDefaults.standard.string(forKey: userDefaultsKey) == nil {
            let model = autoSelectModel()
            UserDefaults.standard.set(model.rawValue, forKey: userDefaultsKey)
            print("📊 Auto-selected embedding model: \(model.displayName)")
            print("   System RAM: \(systemRAMGB)GB")
            print("   Model size: \(model.sizeInMB)MB")
            print("   Dimensions: \(model.dimensions)")
        }
    }

    /// Auto-select the best model based on available system RAM
    func autoSelectModel() -> EmbeddingModel {
        let ramGB = systemRAMGB

        print("📊 Auto-selecting embedding model for \(ramGB)GB RAM...")

        if ramGB >= 16 {
            print("   Selected: BGE-Small (balanced quality)")
            return .bgeSmall
        } else if ramGB >= 8 {
            print("   Selected: MiniLM-L12 (optimized for lower RAM)")
            return .miniLML12
        } else {
            print("   Selected: MiniLM-L6 (fastest, smallest)")
            return .miniLML6
        }
    }

    /// Get system RAM in GB
    var systemRAMGB: Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ramGB = Int(physicalMemory / 1_073_741_824) // Convert bytes to GB
        return ramGB
    }

    /// Check if current model is suitable for system
    func isCurrentModelSuitable() -> Bool {
        return systemRAMGB >= selectedModel.minRecommendedRAMGB
    }

    /// Get recommendation message if current model is not suitable
    func getRecommendationMessage() -> String? {
        if !isCurrentModelSuitable() {
            let recommended = autoSelectModel()
            return "Your system has \(systemRAMGB)GB RAM. We recommend \(recommended.displayName) instead of \(selectedModel.displayName)."
        }
        return nil
    }
}
