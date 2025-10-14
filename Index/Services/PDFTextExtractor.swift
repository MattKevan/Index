//
//  PDFTextExtractor.swift
//  Index
//
//  Created by Claude on 10/14/2025.
//

import Foundation
import PDFKit

/// Actor-isolated service for extracting text from PDF documents using PDFKit
actor PDFTextExtractor {
    static let shared = PDFTextExtractor()

    private init() {}

    // MARK: - Text Extraction

    /// Extract text from a PDF file
    /// - Parameter url: URL to the PDF file
    /// - Returns: Extracted text in plain format with page breaks
    /// - Throws: PDFExtractionError if extraction fails
    func extractText(from url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFExtractionError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFExtractionError.noPagesFound
        }

        var extractedText = ""
        var successfulPages = 0

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                print("⚠️ Could not access page \(pageIndex + 1)")
                continue
            }

            if let pageText = page.string, !pageText.isEmpty {
                // Add page separator for multi-page documents (except first page)
                if successfulPages > 0 {
                    extractedText += "\n\n---\n\n"
                    extractedText += "## Page \(pageIndex + 1)\n\n"
                }

                // Clean up newlines in extracted text
                let cleanedText = cleanupNewlines(pageText)
                extractedText += cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                extractedText += "\n"
                successfulPages += 1
            }
        }

        // Check if PDF has no text (scanned document)
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PDFExtractionError.noTextFound(message: "PDF appears to be scanned or image-based. OCR support coming soon.")
        }

        print("✅ Extracted text from \(successfulPages)/\(pageCount) pages")
        return extractedText
    }

    /// Clean up newlines that break words or sentences
    /// - Parameter text: Raw text from PDF
    /// - Returns: Text with unnecessary newlines removed
    private func cleanupNewlines(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result = ""

        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Skip completely empty lines (preserve paragraph breaks)
            if line.isEmpty {
                if !result.isEmpty && !result.hasSuffix("\n\n") {
                    result += "\n\n"
                }
                continue
            }

            // Check if this line should be joined with the previous one
            let shouldJoin = !result.isEmpty &&
                            !result.hasSuffix("\n\n") &&
                            !endsWithSentenceTerminator(result)

            if shouldJoin {
                // Join with a space if the last character isn't already whitespace
                if !result.hasSuffix(" ") {
                    result += " "
                }
                result += line
            } else {
                // Start a new line or paragraph
                if !result.isEmpty && !result.hasSuffix("\n\n") {
                    result += "\n"
                }
                result += line
            }
        }

        return result
    }

    /// Check if text ends with a sentence terminator
    /// - Parameter text: Text to check
    /// - Returns: True if ends with sentence-ending punctuation
    private func endsWithSentenceTerminator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last else { return false }
        return [".", "!", "?", ":", ";"].contains(lastChar)
    }

    /// Extract text with detailed metadata about extraction quality
    /// - Parameter url: URL to the PDF file
    /// - Returns: Extraction result with text and metadata
    func extractTextWithMetadata(from url: URL) async throws -> PDFExtractionResult {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFExtractionError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFExtractionError.noPagesFound
        }

        var extractedText = ""
        var pagesWithText = 0
        var pagesWithoutText = 0
        var totalCharacters = 0

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }

            if let pageText = page.string, !pageText.isEmpty {
                if pagesWithText > 0 {
                    extractedText += "\n\n---\n\n"
                    extractedText += "## Page \(pageIndex + 1)\n\n"
                }

                // Clean up newlines in extracted text
                let cleanedText = cleanupNewlines(pageText)
                let trimmedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                extractedText += trimmedText
                extractedText += "\n"

                pagesWithText += 1
                totalCharacters += trimmedText.count
            } else {
                pagesWithoutText += 1
            }
        }

        let quality: ExtractionQuality
        if pagesWithoutText == 0 {
            quality = .excellent
        } else if pagesWithText > pagesWithoutText {
            quality = .good
        } else if pagesWithText > 0 {
            quality = .poor
        } else {
            quality = .failed
        }

        return PDFExtractionResult(
            text: extractedText,
            pageCount: pageCount,
            pagesWithText: pagesWithText,
            pagesWithoutText: pagesWithoutText,
            totalCharacters: totalCharacters,
            quality: quality
        )
    }

    // MARK: - PDF Information

    /// Get basic information about a PDF file
    /// - Parameter url: URL to the PDF file
    /// - Returns: PDF metadata
    func getPDFInfo(from url: URL) async throws -> PDFInfo {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFExtractionError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        var hasText = false

        // Check first few pages for text content
        let pagesToCheck = min(3, pageCount)
        for pageIndex in 0..<pagesToCheck {
            if let page = pdfDocument.page(at: pageIndex),
               let pageText = page.string,
               !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasText = true
                break
            }
        }

        return PDFInfo(
            pageCount: pageCount,
            hasText: hasText,
            title: pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            author: pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
            subject: pdfDocument.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String,
            creator: pdfDocument.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String,
            creationDate: pdfDocument.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date
        )
    }
}

// MARK: - Data Types

struct PDFExtractionResult {
    let text: String
    let pageCount: Int
    let pagesWithText: Int
    let pagesWithoutText: Int
    let totalCharacters: Int
    let quality: ExtractionQuality
}

enum ExtractionQuality {
    case excellent  // All pages have text
    case good       // Most pages have text
    case poor       // Some pages have text
    case failed     // No text found (scanned PDF)
}

struct PDFInfo {
    let pageCount: Int
    let hasText: Bool
    let title: String?
    let author: String?
    let subject: String?
    let creator: String?
    let creationDate: Date?
}

enum PDFExtractionError: Error, LocalizedError {
    case invalidPDF
    case noPagesFound
    case noTextFound(message: String)
    case readFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "The file is not a valid PDF or is corrupted."
        case .noPagesFound:
            return "The PDF contains no pages."
        case .noTextFound(let message):
            return message
        case .readFailed:
            return "Failed to read the PDF file."
        }
    }
}
