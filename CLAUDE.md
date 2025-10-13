# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Index is a native macOS personal knowledge management (PKM) application built with SwiftUI that provides offline-first RAG (Retrieval-Augmented Generation) search and writing tools. The app targets macOS Tahoe 26.0+ and requires Apple Silicon (M1+).

**Key Features:**
- Document management with folder organization
- Semantic search using MLX-powered embeddings
- RAG-powered Q&A using Foundation Models
- Fully offline AI processing
- SwiftData persistence with CloudKit sync capability

## Technology Stack

- **UI**: SwiftUI 6.0 with Liquid Glass design language
- **Data**: SwiftData with CloudKit integration
- **AI/ML**:
  - MLX Swift (0.25.6) for embeddings
  - VecturaKit (main branch) for vector database
  - Foundation Models framework for LLM queries
  - TaylorAI/bge-micro embedding model (384 dimensions)
- **Platform**: macOS Tahoe 26.0+, Apple Silicon M1+ only

## Architecture

The app follows a three-layer architecture:

### 1. Data Models (SwiftData)
- **Folder**: Organizes documents with sort order
- **Document**: Core content with title, content, processing status
- **DocumentVersion**: Version history for documents
- **Chunk**: Text segments for vector embeddings

All models are stored in SwiftData and can sync via CloudKit. Embeddings are NOT synced - they are regenerated locally from content.

### 2. Services Layer

**ProcessingPipeline** (Actor - `Services/ProcessingPipeline.swift:11`)
- Singleton actor managing document processing workflow
- Initializes VecturaDB on startup
- Chunks documents using TextChunker
- Generates embeddings and stores in vector database
- Updates document processing status

**VecturaDB** (Actor - `Services/VecturaDB.swift:13`)
- Wraps VecturaMLXKit for vector operations
- Uses TaylorAI/bge-micro model (384-dim embeddings)
- Handles embedding generation internally
- Provides semantic search with configurable thresholds
- Initialize asynchronously - check `isInitialized` before use

**RAGEngine** (`Services/RAGEngine.swift:13`)
- Manages Foundation Models integration
- Retrieves relevant chunks from VecturaDB
- Implements context summarization for large result sets
- Streams LLM responses using Foundation Models
- Handles graceful degradation when AI unavailable

**TextChunker** (`Services/TextChunker.swift`)
- Splits documents into semantic chunks for embedding

### 3. Views (SwiftUI)
- **ContentView**: Three-pane navigation (sidebar, list, detail)
- **SidebarView**: Folder navigation and search trigger
- **DocumentListView**: Documents in selected folder
- **DocumentDetailView**: Document editor
- **RAGSearchView**: AI-powered search interface

## Common Development Commands

### Build and Run
```bash
# Build the project
xcodebuild -scheme Index -configuration Debug build

# Run tests
xcodebuild -scheme Index -configuration Debug test

# Clean build folder
xcodebuild clean -scheme Index
```

### Run in Xcode
Open `Index.xcodeproj` in Xcode and use Cmd+R to build and run. The app requires macOS Tahoe 26.0+ to run.

## Critical Implementation Details

### Vector Database Initialization

VecturaDB initialization is **asynchronous** and happens in the background. The app polls for readiness on launch:

```swift
// Check before using (ContentView.swift:132-153)
let ready = await ProcessingPipeline.shared.isReady()
```

First launch downloads the embedding model (~384MB for bge-micro) to the Hugging Face cache directory. This can take 2-5 minutes on first run.

### Document Processing Flow

1. User imports/creates document → Document model created with `processingStatus = .pending`
2. ProcessingPipeline.processDocument() called:
   - Checks VectorDB initialization status
   - Chunks text using TextChunker
   - Generates embeddings via VecturaMLXKit (automatic)
   - Stores chunks with embedding IDs
   - Updates document status to `.completed` or `.failed`

### RAG Query Flow

1. User enters search query → triggers RAGSearchView
2. RAGEngine.query() streams results:
   - Embeds query text (automatic in VecturaDB)
   - Searches vector DB for top 10 chunks (threshold 0.7)
   - If >5 results, summarizes in batches to fit context window
   - Builds context prompt with relevant excerpts
   - Streams Foundation Models response
3. UI displays streaming answer with source citations

### Context Window Management

Foundation Models have limited context windows. RAGEngine implements two-stage summarization:

- **Small result sets** (≤5 chunks): Direct context assembly, max 2400 chars (~600 tokens)
- **Large result sets** (>5 chunks): Batch summarization (3 chunks per batch), then combines summaries
- See `RAGEngine.summarizeChunks()` (Services/RAGEngine.swift:184)

### Foundation Models Availability

Always check availability before use:

```swift
let model = SystemLanguageModel.default
switch model.availability {
case .available: // Ready
case .unavailable(.deviceNotEligible): // Intel Mac
case .unavailable(.appleIntelligenceNotEnabled): // User setting
case .unavailable(.modelNotReady): // Downloading
}
```

Rate limiting: ~60 requests/min on battery, higher when plugged in.

## Model Container Setup

The app uses a shared ModelContainer defined in IndexApp.swift:14-27:

```swift
let schema = Schema([
    Folder.self,
    Document.self,
    DocumentVersion.self,
    Chunk.self
])
```

CloudKit sync is configured but embeddings are NOT synced - they're regenerated on each device from document content.

## Key Files Reference

- **Entry Point**: `Index/IndexApp.swift`
- **Main UI**: `Index/ContentView.swift`
- **Models**: `Index/Models/{Folder,Document,DocumentVersion,Chunk}.swift`
- **Services**: `Index/Services/{ProcessingPipeline,RAGEngine,VecturaDB,TextChunker}.swift`
- **Views**: `Index/Views/{DocumentListView,DocumentDetailView,RAGSearchView,SidebarView}.swift`

## Swift Package Dependencies

See `Package.resolved` for exact versions. Key dependencies:

- **MLX Swift** (0.25.6): Apple's ML framework for Apple Silicon
- **VecturaKit** (main): Vector database with hybrid search
- **swift-embeddings** (0.0.21): Embedding model support
- **swift-transformers** (1.0.0): HuggingFace transformers

All dependencies are managed via SPM and automatically resolved by Xcode.

## Development Notes

### Memory Considerations
- Embedding models load into unified memory
- Large document collections (10K+ docs) require 16GB+ RAM
- VecturaDB keeps indices in memory for fast search

### Performance Targets
- Document import: <3s for 1MB PDF
- Embedding generation: <50ms per chunk
- Vector search: <100ms for 10K docs
- RAG query end-to-end: <2s

### Error Handling
- VecturaDB initialization failures are logged but non-fatal
- Documents can be created/edited without embeddings (search disabled)
- Foundation Models unavailability shows user-facing prompts
- Processing failures set `document.processingStatus = .failed`

## Testing

- **Unit Tests**: `IndexTests/IndexTests.swift`
- **UI Tests**: `IndexUITests/` directory

Run tests via Xcode Test Navigator (Cmd+6) or xcodebuild.

## Future Architecture

See `FEASIBILITY_REPORT.md` for detailed technical proposal including:
- Post-MVP roadmap (MLX LLM support, iOS companion)
- Storage requirements and scaling considerations
- Alternative embedding models (all-MiniLM-L6-v2, bge-small)
- Advanced features (knowledge graph, graph analytics)
