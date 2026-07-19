import SwiftUI

struct GlobalSearchView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var results = LocalSearchResults(entries: [], tags: [])
    @State private var errorMessage: String?
    @State private var isCapturing = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $query, prompt: "Entries, habits, goals and tags")
                .onChange(of: query) { _, _ in search() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isCapturing = true
                        } label: {
                            Label("Quick Capture", systemImage: "plus")
                        }
                        .accessibilityIdentifier("search-capture-button")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .sheet(isPresented: $isCapturing) {
            QuickCaptureView(mediaStore: mediaStore) {
                isCapturing = false
            }
        }
        .alert("Search Unavailable", isPresented: searchErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if TextSearchNormalizer.normalize(query).isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Search Entries, Reviews, Tags, Habits, Goals and Flags on this device.")
            )
        } else if results.entries.isEmpty && results.tags.isEmpty
            && results.habits.isEmpty && results.goals.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            SearchResultsList(
                results: results,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
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

    private var searchErrorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct SearchResultsList: View {
    let results: LocalSearchResults
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    var body: some View {
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
            if !results.habits.isEmpty {
                Section("Habits") {
                    ForEach(results.habits) { habit in
                        NavigationLink {
                            HabitDetailView(
                                habit: habit,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(habit.name, systemImage: "repeat")
                        }
                        .accessibilityIdentifier("search-habit-\(habit.normalizedName)")
                    }
                }
            }
            if !results.goals.isEmpty {
                Section("Goals and Flags") {
                    ForEach(results.goals) { goal in
                        NavigationLink {
                            GoalDetailView(
                                goal: goal,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(
                                goal.title,
                                systemImage: goal.kind == .flag ? "flag" : "target"
                            )
                        }
                        .accessibilityIdentifier("search-goal-\(goal.normalizedTitle)")
                    }
                }
            }
        }
    }
}
