import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case timeline
    case growth
    case library
}

struct AppShell: View {
    let container: AppContainer

    @State private var selectedTab: AppTab = .today
    @State private var isCapturing = false
    @State private var isShowingStorage = false
    @State private var isSearching = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    openCapture: { isCapturing = true },
                    openStorage: { isShowingStorage = true },
                    mediaStore: container.mediaStore
                )
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack {
                TimelineView(
                    mediaStore: container.mediaStore,
                    thumbnailStore: container.thumbnailStore
                )
            }
            .tabItem { Label("Timeline", systemImage: "clock") }
            .tag(AppTab.timeline)

            NavigationStack {
                GrowthView(
                    mediaStore: container.mediaStore,
                    thumbnailStore: container.thumbnailStore
                )
            }
            .tabItem { Label("Growth", systemImage: "leaf") }
            .tag(AppTab.growth)

            NavigationStack {
                LibraryView(
                    mediaStore: container.mediaStore,
                    thumbnailStore: container.thumbnailStore
                )
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)
        }
        .accessibilityIdentifier("app-shell")
        .sheet(isPresented: $isCapturing) {
            QuickCaptureView(mediaStore: container.mediaStore) {
                selectedTab = .timeline
                isCapturing = false
            }
        }
        .sheet(isPresented: $isShowingStorage) {
            MediaStorageView(
                mediaStore: container.mediaStore,
                integrityReport: container.mediaIntegrityReport
            )
        }
        .sheet(isPresented: $isSearching) {
            GlobalSearchView(
                mediaStore: container.mediaStore,
                thumbnailStore: container.thumbnailStore
            )
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                Button {
                    isSearching = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.bold())
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 3, y: 1)
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("global-search-button")

                Button {
                    isCapturing = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .frame(width: 52, height: 52)
                        .background(.tint, in: Circle())
                        .foregroundStyle(.white)
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel("Quick Capture")
                .accessibilityIdentifier("global-capture-button")
            }
            .padding(.trailing, 20)
            .padding(.bottom, 72)
        }
    }
}

private struct TodayView: View {
    let openCapture: () -> Void
    let openStorage: () -> Void
    let mediaStore: MediaStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @Query(sort: [
        SortDescriptor(\Goal.normalizedTitle, order: .forward),
        SortDescriptor(\Goal.id, order: .forward)
    ]) private var goals: [Goal]
    @State private var errorMessage: String?

    private var activeHabits: [Habit] {
        habits.filter { $0.status == .active }
    }

    private var activeGoals: [Goal] {
        goals.filter { $0.status == .active }
    }

    var body: some View {
        List {
            Section {
                Button(action: openCapture) {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .font(.headline)
                }
                .accessibilityIdentifier("quick-capture-button")
            } footer: {
                Text("Save a thought or photo now. Organize it later if you want.")
            }
            if !activeHabits.isEmpty {
                Section {
                    ForEach(activeHabits) { habit in
                        Button {
                            checkIn(habit)
                        } label: {
                            HStack {
                                Text(habit.name)
                                Spacer()
                                Label("Check In", systemImage: "checkmark.circle")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .accessibilityLabel("Check in \(habit.name)")
                    }
                } header: {
                    Text("Today's Habits")
                } footer: {
                    Text("Missing a day is not failure. Check in when the habit happens.")
                }
            }
            if !activeGoals.isEmpty {
                Section {
                    ForEach(activeGoals) { goal in
                        Label(
                            goal.title,
                            systemImage: goal.kind == .flag ? "flag" : "target"
                        )
                    }
                } header: {
                    Text("Active Goals and Flags")
                } footer: {
                    Text("Context for today, not a list of tasks you must update.")
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            Button(action: openStorage) {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
        }
        .alert("Could Not Check In", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func checkIn(_ habit: Habit) {
        do {
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).checkIn(habit)
        } catch {
            errorMessage = "The check-in was not saved."
        }
    }
}

private struct TimelineView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.createdAt, order: .reverse),
        SortDescriptor(\Entry.id, order: .forward)
    ]) private var entries: [Entry]
    @Query(sort: [
        SortDescriptor(\HabitLog.occurredAt, order: .reverse),
        SortDescriptor(\HabitLog.id, order: .forward)
    ]) private var habitLogs: [HabitLog]
    @Query private var habits: [Habit]
    @Query(sort: [
        SortDescriptor(\GoalLifecycleEvent.occurredAt, order: .reverse),
        SortDescriptor(\GoalLifecycleEvent.id, order: .forward)
    ]) private var goalEvents: [GoalLifecycleEvent]
    @Query private var goals: [Goal]
    @State private var showsArchived = false

    private var displayedEntries: [Entry] {
        entries.filter { showsArchived ? $0.status == .archived : $0.status != .archived }
    }

    private var habitActivity: [HabitDaySummary] {
        guard !showsArchived else { return [] }
        return HabitTimelineAggregator.summarize(logs: habitLogs, habits: habits)
    }

    private var displayedGoalEvents: [GoalLifecycleEvent] {
        showsArchived ? [] : goalEvents
    }

    private var goalsByID: [UUID: Goal] {
        Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Group {
            if displayedEntries.isEmpty && habitActivity.isEmpty && displayedGoalEvents.isEmpty {
                ContentUnavailableView(
                    showsArchived ? "No Archived Entries" : "No Entries Yet",
                    systemImage: showsArchived ? "archivebox" : "clock",
                    description: Text(showsArchived ? "Archived entries will appear here." : "Your captures will appear here.")
                )
            } else {
                List {
                    if !displayedEntries.isEmpty {
                        Section("Entries") {
                            ForEach(displayedEntries) { entry in
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
                    if !habitActivity.isEmpty {
                        Section("Habit Activity") {
                            ForEach(habitActivity) { summary in
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent(
                                        summary.day.formatted(date: .abbreviated, time: .omitted),
                                        value: "\(summary.logCount) check-in\(summary.logCount == 1 ? "" : "s")"
                                    )
                                    if !summary.habitNames.isEmpty {
                                        Text(summary.habitNames.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !displayedGoalEvents.isEmpty {
                        Section("Goal Changes") {
                            ForEach(displayedGoalEvents) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goalsByID[event.goalID]?.title ?? "Goal")
                                    LabeledContent(
                                        event.kindRawValue.capitalized,
                                        value: event.occurredAt.formatted(date: .abbreviated, time: .shortened)
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            Button {
                showsArchived.toggle()
            } label: {
                Label(
                    showsArchived ? "Show Active" : "Show Archived",
                    systemImage: showsArchived ? "clock" : "archivebox"
                )
            }
        }
        .accessibilityIdentifier("timeline-view")
    }
}

private struct MediaStorageView: View {
    let mediaStore: MediaStore
    let integrityReport: MediaIntegrityReport

    @Environment(\.dismiss) private var dismiss
    @State private var byteCount: Int64?
    @State private var isCapturing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Original photos") {
                        if let byteCount {
                            Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        } else {
                            ProgressView()
                        }
                    }
                } header: {
                    Text("Media Storage")
                } footer: {
                    Text("Original photos are stored privately on this device.")
                }
                if integrityReport.requiresAttention {
                    Section {
                        if !integrityReport.missingOriginalPaths.isEmpty {
                            Label(
                                "\(integrityReport.missingOriginalPaths.count) photo(s) are missing",
                                systemImage: "exclamationmark.triangle"
                            )
                        }
                        if !integrityReport.recoveryFilePaths.isEmpty {
                            Label(
                                "\(integrityReport.recoveryFilePaths.count) unlinked photo(s) were preserved",
                                systemImage: "lifepreserver"
                            )
                        }
                    } header: {
                        Text("Recovery")
                    } footer: {
                        Text("The app preserved recoverable files instead of deleting them. Keep an app backup before troubleshooting.")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Quick Capture", systemImage: "plus")
                    }
                    .accessibilityIdentifier("settings-capture-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                byteCount = try? mediaStore.originalsByteCount()
            }
            .sheet(isPresented: $isCapturing) {
                QuickCaptureView(mediaStore: mediaStore) {
                    isCapturing = false
                    byteCount = try? mediaStore.originalsByteCount()
                }
            }
        }
    }
}

struct TimelineRow: View {
    let entry: Entry
    let thumbnailStore: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = entry.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let body = entry.body, !body.isEmpty {
                Text(body)
            }
            if let image = entry.images.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                DownsampledOriginalView(
                    metadata: image,
                    thumbnailStore: thumbnailStore,
                    accessibilityLabel: "First photo in entry"
                )
            }
            Text(entry.occurredAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("timeline-entry-\(entry.id.uuidString)")
    }
}

struct DownsampledOriginalView: View {
    let metadata: ImageMetadata
    let thumbnailStore: ThumbnailStore
    var accessibilityLabel = "Entry photo"

    var body: some View {
        if let image = thumbnailStore.image(for: metadata) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(accessibilityLabel)
        } else {
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

}

extension Entry: Identifiable {}
