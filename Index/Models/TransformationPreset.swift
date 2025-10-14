//
//  TransformationPreset.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import SwiftData
import Foundation

@Model
final class TransformationPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var systemPrompt: String
    var icon: String // SF Symbol name
    var isBuiltIn: Bool
    var sortOrder: Int
    var versionType: VersionType // Links to VersionType for categorization

    init(name: String, systemPrompt: String, icon: String, isBuiltIn: Bool = false, sortOrder: Int = 0, versionType: VersionType) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.versionType = versionType
    }

    // Built-in presets factory methods
    static func createBuiltInPresets() -> [TransformationPreset] {
        return [
            TransformationPreset(
                name: "Executive Summary",
                systemPrompt: """
                Create a concise executive summary of this document. Include:
                1) Main topic in one sentence
                2) 3-5 key points using bullet points
                3) Key takeaways or conclusions

                Keep it under 300 words. Use markdown formatting.
                """,
                icon: "sparkles",
                isBuiltIn: true,
                sortOrder: 0,
                versionType: .executiveSummary
            ),
            TransformationPreset(
                name: "Article",
                systemPrompt: """
                Rewrite this content as a well-structured article. Add:
                - A clear introduction
                - Properly formatted sections with headings
                - Smooth transitions between ideas
                - A conclusion

                Preserve all important details and facts. Use markdown formatting with proper headings (##, ###).
                """,
                icon: "doc.text",
                isBuiltIn: true,
                sortOrder: 1,
                versionType: .article
            ),
            TransformationPreset(
                name: "Flashcards",
                systemPrompt: """
                Extract the most important concepts and create flashcards in this format:

                **Q:** [Question]
                **A:** [Answer]

                ---

                Create 5-10 flashcards focusing on key definitions, concepts, and facts.
                Make questions clear and concise. Use markdown formatting.
                """,
                icon: "rectangle.stack",
                isBuiltIn: true,
                sortOrder: 2,
                versionType: .flashcards
            ),
            TransformationPreset(
                name: "Study Notes",
                systemPrompt: """
                Transform this into structured study notes. Include:
                - Main topics as ## headings
                - Key points as bullet lists
                - Important terms in **bold**
                - Examples where relevant
                - Summary at the end

                Organize for easy review and memorization. Use markdown formatting.
                """,
                icon: "brain.head.profile",
                isBuiltIn: true,
                sortOrder: 3,
                versionType: .studyNotes
            )
        ]
    }
}
