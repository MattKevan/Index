//
//  IndexApp.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData

// Global shared model container for actors and background tasks
let sharedModelContainer: ModelContainer = {
    let schema = Schema([
        Folder.self,
        Document.self,
        DocumentVersion.self,
        Chunk.self,
        TransformationPreset.self
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()

@main
struct IndexApp: App {
    // Use the global shared model container
    private let container = sharedModelContainer

    // Shared processing queue
    @State private var processingQueue = ProcessingQueue.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(processingQueue)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    NotificationCenter.default.post(name: .importFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reprocess Document") {
                    NotificationCenter.default.post(name: .reprocessDocument, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // Enable text formatting commands (Format menu + keyboard shortcuts)
            TextFormattingCommands()

            // Enable text editing commands (Edit menu + find/replace)
            TextEditingCommands()
        }
    }
}

extension Notification.Name {
    static let importFiles = Notification.Name("importFiles")
    static let openDocument = Notification.Name("openDocument")
    static let reprocessDocument = Notification.Name("reprocessDocument")
}
