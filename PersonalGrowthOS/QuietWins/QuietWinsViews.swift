import SwiftData
import SwiftUI
import UIKit

extension QuietWinsCard {
    var fact: String {
        switch kind {
        case .goal: String(localized: "Completed “\(title)”")
        case .todos: String(localized: "Tasks completed: \(count)")
        case .habit: String(localized: "Days with check-ins for “\(title)”: \(count)")
        case .entries: String(localized: "Days with life records: \(count)")
        case .reviews: String(localized: "Calendar weeks with completed reviews: \(count)")
        }
    }
    var symbol: String {
        switch kind {
        case .goal: "target"
        case .todos: "checkmark.circle"
        case .habit: "repeat"
        case .entries: "book"
        case .reviews: "calendar"
        }
    }
}

struct QuietWinsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var days = 30
    @State private var refresh = 0
    @State private var projection: QuietWinsProjection?
    @State private var failed = false

    var body: some View {
        List {
            Section {
                Picker("Time range", selection: $days) {
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("Last 90 days").tag(90)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("quiet-wins-range")
                if let window = projection?.window {
                    Text("\(window.start.formatted(date: .abbreviated, time: .omitted)) – \(window.asOf.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("quiet-wins-dates")
                }
                Text("These are things you really did")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                #if DEBUG
                if QuietWinsUITestFixture.integrationEnabled, let window = projection?.window {
                    QuietWinsUITestReadMarker(window: window)
                }
                #endif
            }
            if failed {
                ContentUnavailableView("Unable to Load Evidence", systemImage: "exclamationmark.triangle",
                    description: Text("Your records are unchanged. Try opening this page again."))
            } else if let projection {
                if projection.cards.isEmpty {
                    ContentUnavailableView("Quiet Wins", systemImage: "leaf",
                        description: Text("There aren't enough records in this period for a reflection yet. You can return here to look back on things you've done."))
                        .accessibilityIdentifier("quiet-wins-empty")
                } else {
                    ForEach(projection.cards) { card in
                        NavigationLink {
                            QuietWinsEvidenceView(cardID: card.id, window: projection.window,
                                mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(card.fact, systemImage: card.symbol)
                                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                                if card.kind == .goal, let date = card.sources.first?.date {
                                    Text(date, format: .dateTime.year().month().day()).font(.subheadline)
                                }
                                Text("View evidence").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("quiet-wins-card-\(card.kind.rawValue)")
                    }
                }
            } else {
                ProgressView().accessibilityLabel("Loading evidence")
            }
        }
        .navigationTitle("Quiet Wins")
        #if DEBUG
        .toolbar {
            if QuietWinsUITestFixture.integrationEnabled { QuietWinsUITestImportControl(mediaStore: mediaStore) }
        }
        #endif
        .accessibilityIdentifier("quiet-wins-view")
        .task(id: "\(days):\(refresh)") { await load() }
        .onAppear { refresh += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in refresh += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh += 1 }
    }

    @MainActor private func load() async {
        let window = QuietWinsWindow(days: days, asOf: Date(), timeZone: .current)
        let container = context.container
        // Hide outdated assertions during a refresh, including an undo or deletion.
        projection = nil; failed = false
        let work = Task.detached { try await QuietWinsReader(modelContainer: container).read(window: window) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            projection = result
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

struct QuietWinsEvidenceView: View {
    let cardID: String
    let window: QuietWinsWindow
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var card: QuietWinsCard?
    @State private var loadedWindow: QuietWinsWindow?
    @State private var loaded = false
    @State private var failed = false
    @State private var refresh = 0

    var body: some View {
        List {
            if let card {
                Section {
                    Text(card.fact).font(.headline).fixedSize(horizontal: false, vertical: true)
                    #if DEBUG
                    if QuietWinsUITestFixture.integrationEnabled, let window = loadedWindow {
                        QuietWinsUITestReadMarker(window: window)
                    }
                    #endif
                    if card.kind == .reviews {
                        Text("Weeks overlapping this date range; completion time is not inferred.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("Sources") {
                    ForEach(card.sources) { source in
                        NavigationLink {
                            QuietWinsSourceView(source: source, window: loadedWindow ?? window,
                                mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: source.day.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("quiet-wins-source-\(source.kind.rawValue)")
                    }
                }
            } else if loaded {
                ContentUnavailableView(failed ? "Unable to Load Evidence" : "Evidence No Longer Available",
                    systemImage: "leaf", description: Text("The current source records determine this reflection."))
            } else { ProgressView().accessibilityLabel("Loading evidence") }
        }
        .navigationTitle("Evidence")
        #if DEBUG
        .toolbar {
            if QuietWinsUITestFixture.integrationEnabled { QuietWinsUITestImportControl(mediaStore: mediaStore) }
        }
        #endif
        .task(id: refresh) { await load() }
        .onAppear { refresh += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in refresh += 1 }
    }

    @MainActor private func load() async {
        card = nil; loaded = false; failed = false
        let container = context.container
        let currentWindow = QuietWinsWindow(days: window.days, asOf: Date(), timeZone: .current)
        let work = Task.detached { try await QuietWinsReader(modelContainer: container).read(window: currentWindow) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            card = result.evidenceCard(id: cardID); loadedWindow = result.window; loaded = true
        } catch is CancellationError {
        } catch { if !Task.isCancelled { failed = true; loaded = true } }
    }
}

#if DEBUG
/// Explicit synthetic UI-test instrumentation; absent from Release and ordinary launches.
private struct QuietWinsUITestReadMarker: View {
    let window: QuietWinsWindow
    var body: some View {
        Text(verbatim: "\(window.days):\(window.asOf.timeIntervalSince1970)")
            .accessibilityIdentifier("quiet-wins-test-read")
    }
}

private struct QuietWinsUITestImportControl: View {
    let mediaStore: MediaStore
    @Environment(\.modelContext) private var context
    @State private var status = "Import fixture"
    var body: some View {
        Button(status) {
            status = "Importing fixture"
            Task { @MainActor in
                do {
                    try await QuietWinsUITestFixture.importPublicFixture(container: context.container, mediaStore: mediaStore)
                    status = "Import committed"
                } catch { status = "Import failed" }
            }
        }
        .disabled(status != "Import fixture")
        .accessibilityIdentifier("quiet-wins-test-import")
    }
}
#endif

/// Resolve stable IDs against current models, never keep a deleted model as a route.
struct QuietWinsSourceView: View {
    let source: QuietWinsSource
    let window: QuietWinsWindow
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Query private var goals: [Goal]
    @Query private var todos: [TodoTask]
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var entries: [Entry]
    @Query private var reviews: [WeeklyReview]

    init(source: QuietWinsSource, window: QuietWinsWindow, mediaStore: MediaStore, thumbnailStore: ThumbnailStore) {
        self.source = source; self.window = window; self.mediaStore = mediaStore; self.thumbnailStore = thumbnailStore
        let id = source.sourceID, parent = source.parentID ?? source.sourceID
        _goals = Query(filter: #Predicate<Goal> { $0.id == id })
        _todos = Query(filter: #Predicate<TodoTask> { $0.id == id })
        _habits = Query(filter: #Predicate<Habit> { $0.id == parent })
        _logs = Query(filter: #Predicate<HabitLog> { $0.id == id })
        _entries = Query(filter: #Predicate<Entry> { $0.id == id })
        _reviews = Query(filter: #Predicate<WeeklyReview> { $0.id == id })
    }

    var body: some View {
        Group {
            switch source.kind {
            case .goal:
                if let goal = goals.first, goal.status == .completed, let date = goal.completedAt, window.contains(date) {
                    GoalDetailView(goal: goal, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                } else { unavailable }
            case .todo:
                if let task = todos.first, task.state == .completed, let date = task.completedAt, window.contains(date) {
                    TodoDetailView(taskID: task.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                } else { unavailable }
            case .habitLog:
                if let habit = habits.first, let log = logs.first, log.isCompleted, log.habitID == habit.id {
                    HabitDetailView(habit: habit, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                } else { unavailable }
            case .entry:
                if let entry = entries.first, entry.kind == .quickNote, window.contains(entry.occurredAt) {
                    EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                } else { unavailable }
            case .review:
                if let review = reviews.first, review.isCompleted, review.weekIdentifier == source.weekIdentifier {
                    WeeklyReviewView(weekIdentifier: review.weekIdentifier)
                } else { unavailable }
            }
        }
    }
    private var unavailable: some View {
        ContentUnavailableView("Evidence No Longer Available", systemImage: "leaf",
            description: Text("The current source records determine this reflection."))
    }
}
