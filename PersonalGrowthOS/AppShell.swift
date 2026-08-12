import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    @AppStorage("floatingControlsHorizontalFraction") private var floatingControlsHorizontalFraction = 1.0
    @AppStorage("floatingControlsVerticalFraction") private var floatingControlsVerticalFraction = 1.0
    @State private var floatingControlsDragOrigin: CGPoint?
    @State private var isKeyboardVisible = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    openCapture: { isCapturing = true },
                    openStorage: { isShowingStorage = true },
                    openGrowth: { selectedTab = .growth },
                    mediaStore: container.mediaStore,
                    thumbnailStore: container.thumbnailStore
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
                importExportService: container.importExportService,
                integrityReport: container.mediaIntegrityReport
            )
        }
        .sheet(isPresented: $isSearching) {
            GlobalSearchView(
                mediaStore: container.mediaStore,
                thumbnailStore: container.thumbnailStore
            )
        }
        .overlay {
            GeometryReader { proxy in
                let layout = FloatingControlsLayout(
                    containerSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets
                )
                if !isKeyboardVisible && !isCapturing && !isSearching {
                    FloatingControlsCluster(
                        openSearch: { isSearching = true },
                        openCapture: { isCapturing = true },
                        dragBegan: {
                            floatingControlsDragOrigin = layout.point(
                                horizontalFraction: floatingControlsHorizontalFraction,
                                verticalFraction: floatingControlsVerticalFraction
                            )
                        },
                        dragChanged: { translation in
                            guard let origin = floatingControlsDragOrigin else { return }
                            let point = layout.clampedPoint(
                                CGPoint(
                                    x: origin.x + translation.width,
                                    y: origin.y + translation.height
                                )
                            )
                            let fraction = layout.fraction(for: point)
                            floatingControlsHorizontalFraction = fraction.horizontal
                            floatingControlsVerticalFraction = fraction.vertical
                        },
                        dragEnded: {
                            floatingControlsDragOrigin = nil
                        }
                    )
                    .position(layout.point(
                        horizontalFraction: floatingControlsHorizontalFraction,
                        verticalFraction: floatingControlsVerticalFraction
                    ))
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }
}

struct FloatingControlsLayout: Equatable {
    static let clusterSize = CGSize(width: 52, height: 108)
    private static let edgePadding: CGFloat = 16
    private static let topReservedHeight: CGFloat = 64
    private static let bottomReservedHeight: CGFloat = 92

    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    var allowedRect: CGRect {
        let halfWidth = Self.clusterSize.width / 2
        let halfHeight = Self.clusterSize.height / 2
        let minimumX = safeAreaInsets.leading + Self.edgePadding + halfWidth
        let maximumX = max(minimumX, containerSize.width - safeAreaInsets.trailing - Self.edgePadding - halfWidth)
        let minimumY = safeAreaInsets.top + Self.topReservedHeight + halfHeight
        let maximumY = max(minimumY, containerSize.height - safeAreaInsets.bottom - Self.bottomReservedHeight - halfHeight)
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    func point(horizontalFraction: Double, verticalFraction: Double) -> CGPoint {
        let horizontal = min(max(horizontalFraction, 0), 1)
        let vertical = min(max(verticalFraction, 0), 1)
        return CGPoint(
            x: allowedRect.minX + allowedRect.width * horizontal,
            y: allowedRect.minY + allowedRect.height * vertical
        )
    }

    func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, allowedRect.minX), allowedRect.maxX),
            y: min(max(point.y, allowedRect.minY), allowedRect.maxY)
        )
    }

    func fraction(for point: CGPoint) -> (horizontal: Double, vertical: Double) {
        let clamped = clampedPoint(point)
        return (
            horizontal: allowedRect.width == 0 ? 0 : Double((clamped.x - allowedRect.minX) / allowedRect.width),
            vertical: allowedRect.height == 0 ? 0 : Double((clamped.y - allowedRect.minY) / allowedRect.height)
        )
    }
}

private struct FloatingControlsCluster: View {
    let openSearch: () -> Void
    let openCapture: () -> Void
    let dragBegan: () -> Void
    let dragChanged: (CGSize) -> Void
    let dragEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: openSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.bold())
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 3, y: 1)
            }
            .accessibilityLabel("Search")
            .accessibilityIdentifier("global-search-button")

            Button(action: openCapture) {
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard case .second(true, let drag?) = value else { return }
                    if !isDragging {
                        isDragging = true
                        dragBegan()
                    }
                    dragChanged(drag.translation)
                }
                .onEnded { _ in
                    guard isDragging else { return }
                    isDragging = false
                    dragEnded()
                }
        )
    }
}

private struct TodayView: View {
    let openCapture: () -> Void
    let openStorage: () -> Void
    let openGrowth: () -> Void
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @Query(sort: [
        SortDescriptor(\Goal.normalizedTitle, order: .forward),
        SortDescriptor(\Goal.id, order: .forward)
    ]) private var goals: [Goal]
    @Query private var habitLogs: [HabitLog]
    @Query private var habitConfigurations: [HabitConfiguration]
    @Query(sort: WeightRecordOrdering.newestFirstSortDescriptors)
    private var queriedWeightRecords: [WeightRecord]
    @State private var coolingDownHabitIDs: Set<UUID> = []
    @State private var recentCheckIn: RecentHabitCheckIn?
    @State private var transientMessage: String?
    @State private var errorMessage: String?

    private var activeHabits: [Habit] {
        habits.filter { $0.status == .active }
    }

    private var activeGoals: [Goal] {
        goals.filter { $0.status == .active }
    }

    private var weightRecords: [WeightRecord] {
        WeightRecordOrdering.newestFirst(queriedWeightRecords)
    }

    var body: some View {
        List {
            Section {
                Button(action: openCapture) {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("quick-capture-button")
            } footer: {
                Text("Save a thought or photo now. Organize it later if you want.")
            }
            if activeHabits.isEmpty && activeGoals.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Record Today", systemImage: "sun.max")
                            .font(.headline)
                        Text("Today keeps your active Habits, Goals, and Flags close at hand. Start by creating one in Growth or use Quick Capture above.")
                            .foregroundStyle(.secondary)
                        Button(action: openGrowth) {
                            Label("Create a Habit, Goal, or Flag", systemImage: "leaf")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("today-open-growth")
                    }
                    .padding(.vertical, 4)
                }
            }
            if !activeHabits.isEmpty {
                Section {
                    ForEach(activeHabits) { habit in
                        let progress = HabitTodayProgress(
                            habitID: habit.id,
                            logs: habitLogs,
                            settings: HabitSettingsResolver.settings(
                                for: habit.id,
                                configurations: habitConfigurations
                            )
                        )
                        if progress.settings.recordingMode == .multiplePerDay {
                            RepeatableHabitCounter(
                                habitName: habit.name,
                                progress: progress,
                                accessibilityIdentifierPrefix: "today-habit-\(habit.normalizedName)",
                                decrease: { decrementRepeatable(habit) },
                                increase: { incrementRepeatable(habit) }
                            )
                        } else {
                            Button {
                                checkIn(habit)
                            } label: {
                                HStack {
                                    Text(habit.name)
                                    Spacer()
                                    Label(
                                        progress.actionTitle,
                                        systemImage: progress.isCompletedForOncePerDay
                                            ? "checkmark.circle.fill"
                                            : "checkmark.circle"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                            .disabled(
                                coolingDownHabitIDs.contains(habit.id)
                                    || progress.isCompletedForOncePerDay
                            )
                            .accessibilityLabel("Check in \(habit.name)")
                            .accessibilityIdentifier("today-habit-\(habit.normalizedName)")
                        }
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
                        .accessibilityLabel("\(goal.kind.localizedName): \(goal.title)")
                        .accessibilityIdentifier("today-goal-\(goal.normalizedTitle)")
                    }
                } header: {
                    Text("Active Goals and Flags")
                } footer: {
                    Text("Context for today, not a list of tasks you must update.")
                }
            }
            weightAndReviewSections
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .navigationTitle("Today")
        .toolbar {
            Button(action: openStorage) {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
        .safeAreaInset(edge: .bottom) {
            if let recentCheckIn,
               HabitSettingsResolver.settings(
                for: recentCheckIn.habitID,
                configurations: habitConfigurations
               ).recordingMode == .oncePerDay {
                HabitCheckInUndoBar {
                    undo(recentCheckIn)
                }
            } else if let transientMessage {
                Text(transientMessage)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("habit-check-in-message")
            }
        }
        .alert("Could Not Check In", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
    }

    @ViewBuilder
    private var weightAndReviewSections: some View {
        Section("Weight") {
            NavigationLink {
                WeightHistoryView()
            } label: {
                if let latest = weightRecords.first {
                    LabeledContent {
                        Text(verbatim: WeightFormatting.kilograms(latest.weightKilograms))
                            .accessibilityIdentifier("today-latest-weight")
                    } label: {
                        Label("Latest Weight", systemImage: "scalemass")
                    }
                } else {
                    Label("Record Weight", systemImage: "scalemass")
                }
            }
            .accessibilityIdentifier("today-weight")
        }
        Section {
            NavigationLink {
                WeeklyReviewView()
            } label: {
                Label("Weekly Review", systemImage: "text.book.closed")
            }
            .accessibilityIdentifier("today-weekly-review")
        } header: {
            Text("Reflect")
        } footer: {
            Text("Look back on this week and choose one next step when you are ready.")
        }
    }

    private func checkIn(_ habit: Habit) {
        do {
            let log = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).checkIn(habit)
            registerSuccessfulCheckIn(log, habitID: habit.id)
        } catch HabitCheckInError.alreadyCheckedInToday {
            showTransientMessage(String(localized: "This Habit is already completed today."))
        } catch HabitCheckInError.recentlyCheckedIn {
            showTransientMessage(String(localized: "Just checked in. Try again in a moment."))
        } catch {
            errorMessage = String(localized: "The check-in was not saved.")
        }
    }

    private func registerSuccessfulCheckIn(_ log: HabitLog, habitID: UUID) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        transientMessage = nil
        recentCheckIn = RecentHabitCheckIn(habitID: habitID, logID: log.id)
        coolingDownHabitIDs.insert(habitID)
        Task {
            try? await Task.sleep(for: .seconds(HabitCheckInPolicy.duplicatePreventionInterval))
            coolingDownHabitIDs.remove(habitID)
            try? await Task.sleep(for: .seconds(
                HabitCheckInPolicy.undoPresentationInterval
                    - HabitCheckInPolicy.duplicatePreventionInterval
            ))
            if recentCheckIn?.logID == log.id {
                recentCheckIn = nil
            }
        }
    }

    private func incrementRepeatable(_ habit: Habit) {
        do {
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).incrementCount(habit)
            recentCheckIn = nil
            coolingDownHabitIDs.remove(habit.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = String(localized: "The check-in was not saved.")
        }
    }

    private func decrementRepeatable(_ habit: Habit) {
        do {
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).removeLatestStructuredCheckIn(habitID: habit.id)
            recentCheckIn = nil
            coolingDownHabitIDs.remove(habit.id)
        } catch {
            errorMessage = String(localized: "The latest check-in could not be undone.")
        }
    }

    private func undo(_ checkIn: RecentHabitCheckIn) {
        do {
            try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).undoLatestCheckIn(habitID: checkIn.habitID, logID: checkIn.logID)
            coolingDownHabitIDs.remove(checkIn.habitID)
            recentCheckIn = nil
        } catch {
            errorMessage = String(localized: "The latest check-in could not be undone.")
        }
    }

    private func showTransientMessage(_ message: String) {
        transientMessage = message
        Task {
            try? await Task.sleep(for: .seconds(HabitCheckInPolicy.duplicatePreventionInterval))
            if transientMessage == message {
                transientMessage = nil
            }
        }
    }
}

struct HabitTodayProgress: Equatable {
    let count: Int
    let settings: HabitSettings

    init(
        habitID: UUID,
        logs: [HabitLog],
        settings: HabitSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        count = logs.filter {
            $0.habitID == habitID
                && calendar.isDate($0.occurredAt, inSameDayAs: now)
        }.count
        self.settings = settings
    }

    var isCompletedForOncePerDay: Bool {
        settings.recordingMode == .oncePerDay && count > 0
    }

    var actionTitle: String {
        if isCompletedForOncePerDay {
            return String(localized: "Completed Today")
        }
        guard settings.recordingMode == .multiplePerDay else {
            return String(localized: "Check In")
        }
        if let target = settings.dailyTargetCount {
            return String(localized: "Today \(count) / \(target) times")
        }
        return String(localized: "Today \(count) times")
    }
}

enum TimelineItem: Identifiable {
    case entry(Entry)
    case habit(HabitDaySummary)
    case goalEvent(GoalLifecycleEvent)

    var id: String {
        switch self {
        case .entry(let entry): "entry-\(entry.id.uuidString)"
        case .habit(let summary): "habit-\(summary.day.timeIntervalSinceReferenceDate)"
        case .goalEvent(let event): "goal-event-\(event.id.uuidString)"
        }
    }

    var occurredAt: Date {
        switch self {
        case .entry(let entry): entry.occurredAt
        case .habit(let summary): summary.latestOccurredAt
        case .goalEvent(let event): event.occurredAt
        }
    }

    static func chronologically(
        entries: [Entry],
        habitActivity: [HabitDaySummary],
        goalEvents: [GoalLifecycleEvent]
    ) -> [TimelineItem] {
        var items = entries.map(TimelineItem.entry)
        items.append(contentsOf: habitActivity.map(TimelineItem.habit))
        items.append(contentsOf: goalEvents.map(TimelineItem.goalEvent))
        return items.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id < $1.id
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

    private var timelineItems: [TimelineItem] {
        TimelineItem.chronologically(
            entries: displayedEntries,
            habitActivity: habitActivity,
            goalEvents: displayedGoalEvents
        )
    }

    var body: some View {
        Group {
            if timelineItems.isEmpty {
                ContentUnavailableView(
                    showsArchived
                        ? String(localized: "No Archived Entries")
                        : String(localized: "No Entries Yet"),
                    systemImage: showsArchived ? "archivebox" : "clock",
                    description: Text(
                        showsArchived
                            ? String(localized: "Archived entries will appear here.")
                            : String(localized: "Your captures will appear here.")
                    )
                )
            } else {
                List {
                    Section("History") {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .entry(let entry):
                                NavigationLink {
                                    EntryDetailView(
                                        entry: entry,
                                        mediaStore: mediaStore,
                                        thumbnailStore: thumbnailStore
                                    )
                                } label: {
                                    TimelineRow(entry: entry, thumbnailStore: thumbnailStore)
                                }
                            case .habit(let summary):
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Habit Activity", systemImage: "repeat")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    LabeledContent(
                                        summary.day.formatted(date: .abbreviated, time: .omitted),
                                        value: summary.logCount == 1
                                            ? String(localized: "1 check-in")
                                            : String(localized: "\(summary.logCount) check-ins")
                                    )
                                    if !summary.habitNames.isEmpty {
                                        Text(summary.habitNames.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            case .goalEvent(let event):
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Goal Change", systemImage: "target")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(goalsByID[event.goalID]?.title ?? "Goal")
                                    LabeledContent(
                                        event.kind.localizedName,
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
    let importExportService: ImportExportService
    let integrityReport: MediaIntegrityReport

    @Environment(\.dismiss) private var dismiss
    @State private var byteCount: Int64?
    @State private var isCapturing = false
    @State private var isConfirmingExport = false
    @State private var isImporting = false
    @State private var isSharing = false
    @State private var exportLease: ExportPackageLease?
    @State private var transferMessage: String?
    @State private var transferTask: Task<Void, Never>?
    @State private var isTransferring = false

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
                Section {
                    Button {
                        isConfirmingExport = true
                    } label: {
                        Label("Export Full Backup", systemImage: "square.and.arrow.up")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("settings-export-button")
                    .disabled(isTransferring)

                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Full Backup", systemImage: "square.and.arrow.down")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("settings-import-button")
                    .disabled(isTransferring)

                    if isTransferring {
                        HStack {
                            ProgressView()
                            Text("Preparing and verifying backup…")
                        }
                        Button("Cancel Transfer", role: .cancel) {
                            transferTask?.cancel()
                        }
                        .accessibilityIdentifier("settings-cancel-transfer")
                    }
                } header: {
                    Text("Data Transfer")
                } footer: {
                    Text("Backups contain all records, entry text, and original photos and are not encrypted. Import is available only when this database is empty; V1 never merges or erases existing data.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isCapturing = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick Capture")
                    .accessibilityIdentifier("settings-capture-button")
                    .disabled(isTransferring)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isTransferring)
                }
            }
            .interactiveDismissDisabled(isTransferring)
            .task {
                byteCount = try? mediaStore.originalsByteCount()
            }
            .sheet(isPresented: $isCapturing) {
                QuickCaptureView(mediaStore: mediaStore) {
                    isCapturing = false
                    byteCount = try? mediaStore.originalsByteCount()
                }
            }
            .confirmationDialog(
                "Export an unencrypted backup?",
                isPresented: $isConfirmingExport,
                titleVisibility: .visible
            ) {
                Button("Export and Share") {
                    startExport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The ZIP may contain private personal records, entry text, and original photos. Handle it as sensitive data.")
            }
            .sheet(isPresented: $isSharing, onDismiss: cleanupExport) {
                if let exportLease {
                    ActivityShareSheet(items: [exportLease.url]) {
                        isSharing = false
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let selectedURL = try result.get().first else { return }
                    startImport(selectedURL)
                } catch {
                    transferMessage = transferErrorMessage(error)
                }
            }
            .alert("Data Transfer", isPresented: Binding(
                get: { transferMessage != nil },
                set: { if !$0 { transferMessage = nil } }
            )) {
                Button("OK") { transferMessage = nil }
            } message: {
                Text(transferMessage ?? "")
            }
            .onDisappear {
                transferTask?.cancel()
                cleanupExport()
            }
        }
    }

    private func startExport() {
        transferTask?.cancel()
        isTransferring = true
        transferTask = Task {
            defer {
                isTransferring = false
                transferTask = nil
            }
            do {
                exportLease?.cleanup()
                exportLease = try await importExportService.exportPackage()
                try Task.checkCancellation()
                isSharing = true
            } catch is CancellationError {
                cleanupExport()
                transferMessage = String(localized: "Export cancelled. Temporary files were removed.")
            } catch {
                transferMessage = transferErrorMessage(error)
            }
        }
    }

    private func startImport(_ selectedURL: URL) {
        transferTask?.cancel()
        isTransferring = true
        transferTask = Task {
            let accessed = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { selectedURL.stopAccessingSecurityScopedResource() }
                isTransferring = false
                transferTask = nil
            }
            do {
                let restored = try await importExportService.importPackage(from: selectedURL)
                byteCount = try? mediaStore.originalsByteCount()
                transferMessage = String(
                    localized: "Restore completed: \(restored.objectCounts.values.reduce(0, +)) objects and \(restored.restoredMediaCount) original photo(s)."
                )
            } catch is CancellationError {
                transferMessage = String(localized: "Import cancelled. Existing data was left unchanged.")
            } catch {
                transferMessage = transferErrorMessage(error)
            }
        }
    }

    private func cleanupExport() {
        exportLease?.cleanup()
        exportLease = nil
    }

    private func transferErrorMessage(_ error: Error) -> String {
        switch error {
        case TransferPackageError.targetNotEmpty:
            String(localized: "Import requires an empty database. Existing data was left unchanged.")
        case TransferPackageError.unsupportedSchema:
            String(localized: "This backup uses an unsupported newer format. Existing data was left unchanged.")
        case ZIPArchiveError.archiveTooLarge,
             ZIPArchiveError.expandedSizeExceeded,
             ZIPArchiveError.tooManyFiles,
             ZIPArchiveError.compressionRatioExceeded,
             TransferPackageError.objectLimitExceeded:
            String(localized: "This backup exceeds the safe import limits. Existing data was left unchanged.")
        case ZIPArchiveError.insufficientCapacity,
             MediaStoreError.insufficientCapacity:
            String(localized: "There is not enough free device storage to complete this transfer safely. Free space and try again; existing data was left unchanged.")
        case TransferPackageError.missingMedia,
             TransferPackageError.mediaMismatch,
             TransferPackageError.corruptManifest,
             TransferPackageError.corruptData,
             ZIPArchiveError.checksumMismatch:
            String(localized: "The backup is incomplete or corrupt. Existing data was left unchanged.")
        default:
            String(localized: "The data transfer could not be completed. Existing data was left unchanged.")
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { completion() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TimelineRow: View {
    let entry: Entry
    let thumbnailStore: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.kind == .review {
                Label("Review", systemImage: "text.book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                    accessibilityLabel: String(localized: "First photo in entry")
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
    var mediaStore: MediaStore?
    var accessibilityLabel = String(localized: "Entry photo")

    @State private var isShowingPreview = false

    var body: some View {
        if let image = thumbnailStore.image(for: metadata) {
            if let mediaStore {
                Button { isShowingPreview = true } label: {
                    imagePresentation(image)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Open larger photo")
                .accessibilityIdentifier("entry-photo-\(metadata.id.uuidString)")
                .fullScreenCover(isPresented: $isShowingPreview) {
                    EntryImagePreview(
                        metadata: metadata,
                        fallbackImage: image,
                        mediaStore: mediaStore
                    )
                }
            } else {
                imagePresentation(image)
                    .accessibilityLabel(accessibilityLabel)
            }
        } else {
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

    private func imagePresentation(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(
                CGFloat(max(metadata.pixelWidth, 1)) / CGFloat(max(metadata.pixelHeight, 1)),
                contentMode: .fit
            )
            .frame(maxHeight: TimelineImagePresentation.maximumHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EntryImagePreview: View {
    let metadata: ImageMetadata
    let fallbackImage: UIImage
    let mediaStore: MediaStore

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image ?? fallbackImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
                .accessibilityLabel("Large photo")
            Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                .font(.title2)
                .foregroundStyle(.white)
                .padding()
                .accessibilityIdentifier("entry-photo-preview-close")
        }
        .accessibilityIdentifier("entry-photo-preview")
        .task {
            guard let url = try? mediaStore.fileURL(for: metadata.relativePath) else { return }
            image = ThumbnailStore.downsampledImage(at: url, maximumPixelSize: 2_048)
        }
    }
}

enum TimelineImagePresentation {
    static let contentMode: ContentMode = .fit
    static let minimumHeight: CGFloat = 80
    static let maximumHeight: CGFloat = 240

    static func fittedSize(
        pixelWidth: Int,
        pixelHeight: Int,
        containerWidth: CGFloat
    ) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0, containerWidth > 0 else {
            return CGSize(width: max(containerWidth, 0), height: minimumHeight)
        }
        let naturalHeight = containerWidth * CGFloat(pixelHeight) / CGFloat(pixelWidth)
        return CGSize(
            width: containerWidth,
            height: min(max(naturalHeight, minimumHeight), maximumHeight)
        )
    }
}

extension GoalLifecycleEventKind {
    var localizedName: String {
        switch self {
        case .created: String(localized: "Created")
        case .paused: String(localized: "Paused")
        case .resumed: String(localized: "Resumed")
        case .completed: String(localized: "Completed")
        case .abandoned: String(localized: "Abandoned")
        case .archived: String(localized: "Archived")
        case .reactivated: String(localized: "Reactivated")
        }
    }
}

extension Entry: Identifiable {}
