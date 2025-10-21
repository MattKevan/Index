//
//  TransformationView.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import SwiftUI
import SwiftData
import MarkdownUI

struct TransformationView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransformationPreset.sortOrder) private var presets: [TransformationPreset]

    @Binding var selectedPreset: TransformationPreset?
    @Binding var needsRegeneration: Bool

    @State private var transformedContent: String = ""
    @State private var isTransforming: Bool = false
    @State private var transformProgress: (current: Int, total: Int, status: String) = (0, 0, "")
    @State private var transformError: Error?
    @State private var showError = false

    private let transformationService = DocumentTransformationService.shared

    var body: some View {
        // Main content only - presets moved to inspector sidebar
        transformedContentView
            .task {
                await initializeBuiltInPresets()
            }
            .onChange(of: selectedPreset) { oldValue, newValue in
                // Trigger transformation when preset changes
                if let preset = newValue {
                    Task {
                        await loadOrTransform(preset: preset)
                    }
                }
            }
            .alert("Transformation Error", isPresented: $showError, presenting: transformError) { _ in
                Button("OK") { transformError = nil }
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    // MARK: - Transformed Content

    @ViewBuilder
    private var transformedContentView: some View {
        VStack(spacing: 0) {
            // Title bar with transformation info
            if let preset = selectedPreset {
                HStack {
                    Image(systemName: preset.icon)
                        .foregroundStyle(.secondary)
                    Text(preset.name)
                        .font(.headline)

                    Spacer()

                    if needsRegeneration {
                        Button(action: {
                            Task {
                                await performTransformation(preset: preset, force: true)
                            }
                        }) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()
            }

            // Content
            if isTransforming {
                VStack(spacing: 16) {
                    Spacer()

                    ProgressView(value: Double(transformProgress.current), total: Double(transformProgress.total)) {
                        Text("Transforming Document")
                            .font(.headline)
                    } currentValueLabel: {
                        Text(transformProgress.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 400)

                    if transformProgress.total > 1 {
                        Text("Processing \(transformProgress.current) of \(transformProgress.total) chunks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedPreset == nil {
                ContentUnavailableView(
                    "No Transformation Selected",
                    systemImage: "wand.and.stars",
                    description: Text("Select a transformation preset from the sidebar to transform this document")
                )
            } else if transformedContent.isEmpty {
                ContentUnavailableView(
                    "No Content",
                    systemImage: "doc.text",
                    description: Text("Select a preset to generate transformed content")
                )
            } else {
                // Display transformed markdown
                ScrollView {
                    VStack {
                        Markdown(transformedContent)
                            .markdownTheme(.indexTheme)
                            .textSelection(.enabled)
                            .frame(maxWidth: 800, alignment: .leading)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    // MARK: - Transformation Logic

    private func loadOrTransform(preset: TransformationPreset) async {
        // Check if we have a cached version
        if let cachedVersion = document.versions.first(where: { $0.versionType == preset.versionType }) {
            // Check if needs regeneration
            let currentHash = document.calculateContentHash()
            let needsRegen = await transformationService.needsRegeneration(
                version: cachedVersion,
                currentContentHash: currentHash
            )

            await MainActor.run {
                transformedContent = cachedVersion.content
                needsRegeneration = needsRegen

                if needsRegen {
                    print("⚠️ Cached transformation outdated - needs regeneration")
                } else {
                    print("✅ Loaded cached transformation")
                }
            }
        } else {
            // No cached version - transform now
            await performTransformation(preset: preset, force: false)
        }
    }

    private func performTransformation(preset: TransformationPreset, force: Bool) async {
        await MainActor.run {
            isTransforming = true
            transformProgress = (0, 1, "Starting...")
            transformError = nil
        }

        do {
            let result = try await transformationService.transformDocument(
                document: document,
                preset: preset
            ) { current, total, status in
                Task { @MainActor in
                    transformProgress = (current, total, status)
                }
            }

            // Save to DocumentVersion
            let currentHash = document.calculateContentHash()
            let version = DocumentVersion(
                content: result,
                versionType: preset.versionType,
                transformationPrompt: preset.systemPrompt,
                contentHash: currentHash
            )
            version.document = document

            await MainActor.run {
                modelContext.insert(version)
                try? modelContext.save()

                transformedContent = result
                needsRegeneration = false
                isTransforming = false

                print("✅ Transformation complete and cached")
            }

        } catch {
            print("❌ Transformation failed: \(error)")

            await MainActor.run {
                transformError = error
                showError = true
                isTransforming = false
            }
        }
    }

    private func initializeBuiltInPresets() async {
        // Check if we already have built-in presets
        let hasPresets = !presets.isEmpty

        guard !hasPresets else {
            print("✅ Built-in presets already initialized")
            return
        }

        print("🔧 Initializing built-in transformation presets...")

        await MainActor.run {
            let builtInPresets = TransformationPreset.createBuiltInPresets()

            for preset in builtInPresets {
                modelContext.insert(preset)
            }

            do {
                try modelContext.save()
                print("✅ Built-in presets initialized (\(builtInPresets.count) presets)")
            } catch {
                print("❌ Failed to save built-in presets: \(error)")
            }
        }
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let preset: TransformationPreset
    let isSelected: Bool
    let needsUpdate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : .primary)

                    if needsUpdate {
                        Label("Needs Update", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .orange)
                    } else if isSelected {
                        Text("Selected")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedPreset: TransformationPreset?
    @Previewable @State var needsRegeneration = false

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Document.self, TransformationPreset.self, configurations: config)

    let document = Document(title: "Test Document", content: "# Test\n\nThis is a test document.")
    container.mainContext.insert(document)

    return TransformationView(
        document: document,
        selectedPreset: $selectedPreset,
        needsRegeneration: $needsRegeneration
    )
    .modelContainer(container)
    .frame(width: 1000, height: 600)
}
