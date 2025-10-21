# Virtualized Markdown Rendering - Implementation Plan

## Overview

This document outlines the architecture for implementing virtualized markdown rendering (Option 1) to solve performance issues with large documents while maintaining full markdown formatting capabilities.

## Current Limitation

The current implementation has a hard 50KB threshold where documents switch to plain text fallback. While this works for most documents, it sacrifices markdown formatting for larger files. The root issue is that SwiftUI must build and layout the entire view hierarchy on the main thread, even though markdown parsing happens off-thread.

## Solution Architecture

### Core Concept

Split large markdown documents into **logical sections** (by heading structure) and render them in a `LazyVStack`. SwiftUI's lazy containers only create views for content in or near the viewport, dramatically reducing memory usage and initial layout time.

### Performance Expectations

Based on SwiftUI LazyVStack benchmarks:
- **Memory reduction**: 80-90% compared to eager rendering
- **Initial load**: Milliseconds instead of seconds
- **Scroll performance**: Maintains 60fps even with hundreds of items
- **View lifecycle**: Views created/destroyed as user scrolls

### Implementation Phases

---

## Phase 1: Document Structure Parser

Create a utility to analyze markdown document structure and split into renderable sections.

### MarkdownSectionizer.swift

```swift
import Foundation

struct MarkdownSection: Identifiable {
    let id: UUID
    let level: Int  // Heading level (1-6) or 0 for content without heading
    let title: String?  // Heading text if available
    let content: String  // Raw markdown for this section
    let startOffset: Int  // Character offset in original document
    let endOffset: Int
}

class MarkdownSectionizer {
    /// Split markdown content into sections based on heading structure
    /// - Parameters:
    ///   - content: Full markdown document
    ///   - maxSectionSize: Maximum characters per section (default 5000)
    /// - Returns: Array of sections suitable for lazy rendering
    static func sectionize(_ content: String, maxSectionSize: Int = 5000) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []

        // Regex to match markdown headings: ^#{1,6}\s+(.+)$
        let headingPattern = #"^(#{1,6})\s+(.+)$"#

        // Split by lines and identify heading boundaries
        let lines = content.components(separatedBy: .newlines)
        var currentSection = ""
        var currentHeading: (level: Int, title: String)?
        var startOffset = 0

        for (index, line) in lines.enumerated() {
            // Check if line is a heading
            if let match = line.range(of: headingPattern, options: .regularExpression) {
                // Save previous section if it exists
                if !currentSection.isEmpty {
                    sections.append(MarkdownSection(
                        id: UUID(),
                        level: currentHeading?.level ?? 0,
                        title: currentHeading?.title,
                        content: currentSection.trimmingCharacters(in: .whitespacesAndNewlines),
                        startOffset: startOffset,
                        endOffset: startOffset + currentSection.count
                    ))
                }

                // Start new section
                let level = line.prefix(while: { $0 == "#" }).count
                let title = String(line.dropFirst(level).trimmingCharacters(in: .whitespaces))
                currentHeading = (level, title)
                currentSection = line + "\n"
                startOffset = startOffset + currentSection.count

            } else {
                // Add to current section
                currentSection += line + "\n"

                // Check if section exceeded max size - split here if needed
                if currentSection.count > maxSectionSize {
                    sections.append(MarkdownSection(
                        id: UUID(),
                        level: currentHeading?.level ?? 0,
                        title: currentHeading?.title,
                        content: currentSection.trimmingCharacters(in: .whitespacesAndNewlines),
                        startOffset: startOffset,
                        endOffset: startOffset + currentSection.count
                    ))

                    currentSection = ""
                    currentHeading = nil
                    startOffset = startOffset + currentSection.count
                }
            }
        }

        // Add final section
        if !currentSection.isEmpty {
            sections.append(MarkdownSection(
                id: UUID(),
                level: currentHeading?.level ?? 0,
                title: currentHeading?.title,
                content: currentSection.trimmingCharacters(in: .whitespacesAndNewlines),
                startOffset: startOffset,
                endOffset: startOffset + currentSection.count
            ))
        }

        return sections
    }
}
```

---

## Phase 2: Virtualized Markdown View

Create a SwiftUI view that renders sections lazily.

### VirtualizedMarkdownView.swift

```swift
import SwiftUI
import MarkdownUI

struct VirtualizedMarkdownView: View {
    let sections: [MarkdownSection]
    let typography: TypographyStyle

    @State private var renderedSections: [UUID: MarkdownContent] = [:]
    @State private var visibleSections: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(sections) { section in
                    VirtualizedMarkdownSection(
                        section: section,
                        renderedContent: renderedSections[section.id],
                        onAppear: { renderSection(section) },
                        onDisappear: { cleanupSection(section) }
                    )
                    .id(section.id)
                }
            }
            .frame(maxWidth: typography.maxColumnWidth)
        }
        .onAppear {
            // Pre-render first few sections immediately
            preRenderInitialSections()
        }
    }

    private func renderSection(_ section: MarkdownSection) {
        // Only render if not already cached
        guard renderedSections[section.id] == nil else { return }

        Task.detached(priority: .userInitiated) {
            let parsed = MarkdownContent(section.content)

            await MainActor.run {
                renderedSections[section.id] = parsed
                visibleSections.insert(section.id)
            }
        }
    }

    private func cleanupSection(_ section: MarkdownSection) {
        visibleSections.remove(section.id)

        // Optional: Remove rendered content for sections far from viewport
        // to free memory (trade-off: re-render cost vs memory usage)
        // For now, keep all rendered sections cached
    }

    private func preRenderInitialSections() {
        // Render first 3 sections immediately for smooth initial experience
        for section in sections.prefix(3) {
            renderSection(section)
        }
    }
}

struct VirtualizedMarkdownSection: View {
    let section: MarkdownSection
    let renderedContent: MarkdownContent?
    let onAppear: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        Group {
            if let content = renderedContent {
                Markdown(content)
                    .markdownTheme(.indexTheme)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            } else {
                // Placeholder while rendering
                VStack(alignment: .leading, spacing: 4) {
                    if let title = section.title {
                        Text(title)
                            .font(.headline)
                            .redacted(reason: .placeholder)
                    }
                    Text(String(repeating: "Loading content... ", count: 10))
                        .font(.body)
                        .redacted(reason: .placeholder)
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
}
```

---

## Phase 3: Integration with DocumentDetailView

Update the existing view to use virtualized rendering for large documents.

### DocumentDetailView.swift Changes

```swift
// Add new state
@State private var markdownSections: [MarkdownSection]?
private let virtualizationThreshold = 100000  // 100KB - use virtualization above this

// In body, update view mode logic:
if viewMode == .view {
    if document.content.count > virtualizationThreshold {
        // Use virtualized rendering for large documents
        if let sections = markdownSections {
            VirtualizedMarkdownView(
                sections: sections,
                typography: typography
            )
        } else {
            ProgressView("Preparing document...")
                .task {
                    await prepareSections()
                }
        }
    } else {
        // Existing non-virtualized rendering for smaller docs
        // ... current implementation ...
    }
}

private func prepareSections() async {
    let content = document.content

    let sections = await Task.detached(priority: .userInitiated) {
        return MarkdownSectionizer.sectionize(content, maxSectionSize: 8000)
    }.value

    await MainActor.run {
        markdownSections = sections
    }
}
```

---

## Phase 4: State Management Considerations

### Critical Detail: View Lifecycle

**Important**: SwiftUI only retains state for top-level views in LazyVStack. When sections scroll out of view and are destroyed, their internal state is lost.

**Solution**: Store all parsed markdown content at the parent level (`VirtualizedMarkdownView.renderedSections`) rather than in child views. Child views are stateless and only display cached data.

### Memory Management Strategy

**Keep or Discard?** When sections scroll far out of view, should we:

1. **Keep cached** (Current approach)
   - Pros: No re-render when scrolling back
   - Cons: Memory grows with scroll distance
   - Best for: Documents < 1MB

2. **Discard aggressively**
   - Pros: Constant memory usage
   - Cons: Re-render cost on scroll back
   - Best for: Very large documents (>5MB)

**Recommendation**: Keep all rendered sections cached for documents under 2MB. For larger documents, implement LRU cache with max 50 sections.

---

## Performance Benchmarks (Expected)

### Test Case: 1.1MB Document (1,148,236 chars)

**Current Implementation** (plain text fallback):
- Load time: Instant
- Memory: ~2MB (raw text)
- Formatting: None (plain text)

**Virtualized Implementation** (projected):
- Load time: <100ms (parse structure + render 3 sections)
- Memory: ~15-20MB (3-5 visible sections at a time)
- Formatting: Full markdown
- Scroll performance: 60fps
- Section count: ~150-200 sections @ 8KB each

### Test Case: 50KB Document

**Current Implementation** (full eager render):
- Load time: 200-500ms
- Memory: ~10MB
- Formatting: Full markdown

**Virtualized Implementation** (projected):
- Load time: <50ms
- Memory: ~8MB (fewer sections needed)
- Formatting: Full markdown

---

## Implementation Checklist

- [ ] Create `MarkdownSectionizer.swift` utility
- [ ] Write unit tests for sectionizer (edge cases: no headings, nested headings, code blocks)
- [ ] Create `VirtualizedMarkdownView.swift`
- [ ] Update `DocumentDetailView.swift` to use virtualization
- [ ] Add configuration setting for virtualization threshold
- [ ] Test with documents of varying sizes (10KB, 50KB, 100KB, 500KB, 1MB, 5MB)
- [ ] Benchmark memory usage with Instruments
- [ ] Implement LRU cache for very large documents (>2MB)
- [ ] Add telemetry for render performance
- [ ] Update UI to show section count and render status

---

## Future Enhancements

### 1. Smart Section Splitting

Instead of just heading-based splitting, consider:
- Paragraph boundaries
- Code block boundaries (never split a code block)
- List boundaries
- Table boundaries

### 2. Prefetch Adjacent Sections

Render sections above/below viewport proactively:
```swift
// Render +/- 2 sections from viewport
let prefetchRange = max(0, currentIndex - 2)...min(sections.count - 1, currentIndex + 2)
```

### 3. Progressive Enhancement

For extremely large documents (>5MB):
1. Show outline/table of contents first
2. Render section on user navigation
3. Keep only current section + adjacent in memory

### 4. Scroll Position Persistence

Save scroll position as section ID + offset:
```swift
struct ScrollPosition {
    let sectionId: UUID
    let offsetInSection: CGFloat
}
```

---

## Alternative: If Virtualization Still Has Issues

If LazyVStack virtualization still causes performance problems with 5MB+ documents, consider:

1. **Hybrid with Down library**: Use Down (cmark) for parsing to NSAttributedString, then virtualize the attributed string chunks
2. **Custom TextKit rendering**: Bypass SwiftUI entirely for very large documents
3. **Paginated view**: Show one section at a time with navigation

---

## Conclusion

Virtualized rendering is the most SwiftUI-native solution that maintains full markdown formatting while handling documents of any size. The implementation is straightforward and sets a solid foundation for future optimizations like background pre-rendering and incremental updates.

**Recommendation**: Implement for documents >100KB. Below that threshold, the current eager rendering works fine.
