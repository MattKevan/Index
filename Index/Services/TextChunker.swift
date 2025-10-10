//
//  TextChunker.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import Foundation
import NaturalLanguage

actor TextChunker {
    let chunkSize: Int
    let overlapSize: Int

    init(chunkSize: Int = 512, overlapSize: Int = 50) {
        self.chunkSize = chunkSize
        self.overlapSize = overlapSize
    }

    func chunk(text: String, documentID: UUID) -> [Chunk] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var chunks: [Chunk] = []
        var currentChunk = ""
        var currentStartOffset = 0
        var chunkIndex = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])

            if (currentChunk + sentence).count > chunkSize && !currentChunk.isEmpty {
                // Save current chunk
                let endOffset = currentStartOffset + currentChunk.count
                chunks.append(Chunk(
                    documentID: documentID,
                    content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                    chunkIndex: chunkIndex,
                    startOffset: currentStartOffset,
                    endOffset: endOffset
                ))

                // Start new chunk with overlap
                let overlapText = getOverlap(from: currentChunk)
                currentChunk = overlapText + sentence
                currentStartOffset = endOffset - overlapText.count
                chunkIndex += 1
            } else {
                currentChunk += sentence
            }

            return true
        }

        // Add final chunk
        if !currentChunk.isEmpty {
            chunks.append(Chunk(
                documentID: documentID,
                content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                chunkIndex: chunkIndex,
                startOffset: currentStartOffset,
                endOffset: currentStartOffset + currentChunk.count
            ))
        }

        return chunks
    }

    private func getOverlap(from text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > 0 else { return "" }

        let overlapWords = words.suffix(min(overlapSize / 6, words.count))
        return overlapWords.joined(separator: " ") + " "
    }
}
