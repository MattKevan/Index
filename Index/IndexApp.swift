//
//  IndexApp.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI
import SwiftData

@main
struct IndexApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Folder.self,
            Document.self,
            DocumentVersion.self,
            Chunk.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Text Files...") {
                    NotificationCenter.default.post(name: .importFiles, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let importFiles = Notification.Name("importFiles")
    static let openDocument = Notification.Name("openDocument")
}
