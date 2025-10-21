//
//  ProcessingQueueView.swift
//  Index
//
//  Created by Claude Code
//

import SwiftUI

struct ProcessingQueueView: View {
    @Environment(ProcessingQueue.self) private var queue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Processing Tasks")
                    .font(.headline)

                Spacer()

                if queue.hasActiveTasks {
                    Button("Cancel All", role: .destructive) {
                        queue.cancelAllTasks()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding()

            Divider()

            if queue.tasks.isEmpty {
                // Empty state
                ContentUnavailableView(
                    "No Active Tasks",
                    systemImage: "checkmark.circle",
                    description: Text("All processing tasks are complete")
                )
                .frame(height: 200)
            } else {
                // Task list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(queue.tasks) { task in
                            ProcessingTaskRow(task: task)
                        }
                    }
                    .padding()
                }
                .frame(height: min(CGFloat(queue.tasks.count) * 90 + 20, 400))
            }
        }
        .frame(width: 350)
    }
}

struct ProcessingTaskRow: View {
    @Environment(ProcessingQueue.self) private var queue
    let task: ProcessingTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.type.icon)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.documentTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Text(task.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: {
                    queue.cancelTask(id: task.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Cancel this task")
            }

            // Progress bar
            ProgressView(value: task.progress) {
                Text(task.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    @Previewable @State var queue = ProcessingQueue.shared

    // Add some sample tasks
    queue.addTask(id: "1", documentTitle: "Long Document About AI and Machine Learning", type: .processing)
    queue.updateProgress(id: "1", current: 14, total: 35, status: "Processing chunk 14 of 35")

    queue.addTask(id: "2", documentTitle: "Meeting Notes", type: .titleGeneration)
    queue.updateProgress(id: "2", current: 1, total: 1, status: "Generating title...")

    return ProcessingQueueView()
        .environment(queue)
}
