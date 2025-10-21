//
//  TransformationPresetsSidebar.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import SwiftUI
import SwiftData

/// Inspector sidebar showing transformation presets
struct TransformationPresetsSidebar: View {
    @Query(sort: \TransformationPreset.sortOrder) private var presets: [TransformationPreset]
    @Binding var selectedPreset: TransformationPreset?
    @Binding var needsRegeneration: Bool
    let onPresetSelected: (TransformationPreset) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                Text("Transformations")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Presets
                ForEach(presets) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id,
                        needsUpdate: needsRegeneration && selectedPreset?.id == preset.id
                    ) {
                        onPresetSelected(preset)
                    }
                }
            }
            .padding()
        }
    }
}
