import SwiftUI

struct GlobalSearchView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var results = LocalSearchResults(entries: [], tags: [])
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if TextSearchNormalizer.normalize(query).isEmpty {
                    ContentUnavailableView(
                        "Search Your Library",
                        systemImage: "magnifyingglass",
                        description: Text("Search Entry text, titles, reviews and tags on this device.")
                    )
                } else if results.entries.isEmpty && results.tags.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        if !results.entries.isEmpty {
                            Section("Entries") {
                                ForEach(results.entries) { entry in
                                    NavigationLink {
                                        EntryDetailView(
                                            entry: entry,
                                            mediaStore: mediaStore,
                                            thumbnailStore: thumbnailStore
                                        )
                                    } label: {
                                        TimelineRow(entry: entry, thumbnailStore: thumbnailStore)
                                    }
                                }
                            }
                        }
                        if !results.tags.isEmpty {
                            Section("Tags") {
                                ForEach(results.tags) { tag in
                                    NavigationLink {
                                        TagEntriesView(
                                            tag: tag,
                                            mediaStore: mediaStore,
                                            thumbnailStore: thumbnailStore
                                        )
                                    } label: {
                                        Label(tag.displayName, systemImage: "tag")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Entries and tags")
            .onChange(of: query) { _, _ in search() }
            .toolbar {
                Button("Done") { dismiss() }
            }
            .alert("Search Unavailable", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func search() {
        do {
            results = try LocalSearchService(context: modelContext).search(query)
            errorMessage = nil
        } catch {
            results = LocalSearchResults(entries: [], tags: [])
            errorMessage = "Your local data could not be searched."
        }
    }
}
