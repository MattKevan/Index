//
//  RAGSearchView.swift
//  Index
//
//  Created by Matt on 10/10/2025.
//

import SwiftUI

struct RAGSearchView: View {
    let query: String
    var onClose: (() -> Void)? = nil

    @State private var ragEngine = RAGEngine()
    @State private var response: RAGResponse?
    @State private var error: Error?
    @State private var isLoading = false
    @State private var searchQuery: String

    init(query: String, onClose: (() -> Void)? = nil) {
        self.query = query
        self.onClose = onClose
        _searchQuery = State(initialValue: query)
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Search input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search Your Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Ask a question...", text: $searchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    performSearch()
                                }

                            Button(action: performSearch) {
                                Label("Search", systemImage: "magnifyingglass")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(searchQuery.isEmpty || isLoading)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Divider()

                    // Response
                    if let error = error {
                        ContentUnavailableView(
                            "Search Failed",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error.localizedDescription)
                        )
                    } else if let response = response {
                        VStack(alignment: .leading, spacing: 16) {
                            // Answer
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Answer")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if !response.isComplete {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }

                                Text(response.partialAnswer)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Sources
                            if !response.sources.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sources")
                                        .font(.headline)

                                    ForEach(response.sources) { source in
                                        SourceView(source: source)
                                    }
                                }
                            }
                        }
                    } else if isLoading {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ContentUnavailableView(
                            "Search Your Knowledge",
                            systemImage: "magnifyingglass",
                            description: Text("Enter a question above to search your notes using AI")
                        )
                    }
                }
                .padding()
        }
        .navigationTitle("AI Search")
        .toolbar {
            if let onClose = onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                }
            }
        }
        .onAppear {
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }

        response = nil
        error = nil
        isLoading = true

        Task {
            do {
                for try await partialResponse in ragEngine.query(searchQuery) {
                    await MainActor.run {
                        response = partialResponse
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isLoading = false
                }
            }
        }
    }
}

struct SourceView: View {
    let source: Source

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(source.documentTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(source.relevanceScore * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(source.excerpt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            openDocument(id: source.documentID)
        }
    }

    private func openDocument(id: String) {
        // Post notification to navigate
        NotificationCenter.default.post(
            name: .openDocument,
            object: id
        )
    }
}
