import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum AppTab: Hashable {
    case today
    case timeline
    case record
    case growth
    case library
}

struct AppShell: View {
    let container: AppContainer

    @State private var selectedTab: AppTab = .today
    @State private var isShowingStorage = false
    @Environment(\.scenePhase) private var captureScenePhase
    @State private var captureFailure = false
    @State private var failedCaptureIDs: [String] = []
    @State private var captureDiagnostic: FailureDiagnostic?
    @State private var captureStateRecovered = false
    @State private var captureStateWriteFailed = false
    @State private var isShowingPendingShares = false
    #if DEBUG
    @State private var captureTestStatus: String?
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
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

            QuickCaptureView(
                mediaStore: container.mediaStore,
                showsCancel: false,
                cleansUpOnDisappear: false
            ) { _ in
                selectedTab = .timeline
            }
            .tabItem { Label("Record", systemImage: "plus.circle.fill") }
            .tag(AppTab.record)

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
        #if DEBUG
        .overlay(alignment: .top) {
            if let captureTestStatus {
                Text(verbatim: captureTestStatus).accessibilityIdentifier("capture-test-status")
            }
        }
        #endif
        .task { await importShares() }
        .onChange(of: captureScenePhase) { _, phase in
            if phase == .active { Task { await importShares() } }
        }
        .alert("Some shared content could not be imported", isPresented: $captureFailure) {
            Button("Review Pending Shares") { isShowingPendingShares = true }
            if let captureDiagnostic {
                Button("Copy Diagnostic Report") { UIPasteboard.general.string = captureDiagnostic.report }
            }
            Button("Keep for Later", role: .cancel) {
                Task {
                    do {
                        let importer = ExternalCaptureImporter(container: container.modelContainer,
                            mediaStore: container.mediaStore, inbox: try captureManagementInbox(mediaStore: container.mediaStore))
                        try await importer.keepForLater(failedCaptureIDs)
                    } catch { CaptureLog.event("inbox.deferFailed") }
                }
            }
        } message: {
            if captureStateWriteFailed { Text(CaptureInboxSnapshot.writeFailureMessage) }
            else if captureStateRecovered { Text(CaptureInboxSnapshot.recoveryMessage) }
            else if let captureDiagnostic { Text(captureDiagnostic.category.title) }
            else { Text("The shared files are retained. You can retry when storage is available or after updating the app.") }
        }
        .sheet(isPresented: $isShowingPendingShares) {
            NavigationStack {
                CaptureInboxView(mediaStore: container.mediaStore)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPendingShares = false }
                    } }
            }
        }
        .sheet(isPresented: $isShowingStorage) {
            MediaStorageView(
                mediaStore: container.mediaStore,
                importExportService: container.importExportService,
                integrityReport: container.mediaIntegrityReport
            )
        }
    }

    private func importShares() async {
        if container.configuration.launchMode == .uiTesting {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PGOSOwnedCopyRecoveryTest") {
                do {
                    let inbox = try captureManagementInbox(mediaStore: container.mediaStore)
                    let marker = container.mediaStore.rootURL.appendingPathComponent("CopyFixtureSeeded")
                    if !FileManager.default.fileExists(atPath: marker.path) {
                        let image = container.mediaStore.rootURL.appendingPathComponent("fixture.png")
                        let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
                            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
                        }
                        try data.write(to: image)
                        let imageID = UUID()
                        let attachment = CaptureAttachment(id: imageID, filename: imageID.uuidString.lowercased(), contentType: "image/png",
                            byteCount: Int64(data.count), checksum: try ShareInbox.checksum(image))
                        try inbox.publish(ShareImportPayload(text: "Interrupted copy fixture", images: [attachment]), files: [attachment.id: image])
                        try Data().write(to: marker)
                    }
                    let importer = ExternalCaptureImporter(container: container.modelContainer,
                        mediaStore: container.mediaStore, inbox: inbox)
                    if ProcessInfo.processInfo.arguments.contains("-PGOSKillAfterCopy") {
                        importer.checkpoint = { phase in
                            if phase == "attachment" {
                                Task { @MainActor in captureTestStatus = "copy-durable-before-save" }
                                // Test-only barrier: UI test terminates this process at the durable-copy boundary.
                                DispatchSemaphore(value: 0).wait()
                            }
                        }
                    }
                    _ = try await importer.scanReport()
                    let originals = container.mediaStore.rootURL.appendingPathComponent("Media/Originals")
                    let files = (FileManager.default.enumerator(at: originals, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
                        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                    captureTestStatus = "originals=\(files.count);recovery=\(container.mediaIntegrityReport.recoveryFilePaths.count);pending=\(try inbox.pending().count)"
                } catch { captureTestStatus = "fixture-failed" }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-PGOSPendingInboxTest") {
                do {
                    let inbox = try captureManagementInbox(mediaStore: container.mediaStore)
                    let importer = ExternalCaptureImporter(container: container.modelContainer,
                        mediaStore: container.mediaStore, inbox: inbox)
                    let marker = container.mediaStore.rootURL.appendingPathComponent("PendingFixtureSeeded")
                    if !FileManager.default.fileExists(atPath: marker.path) {
                        for suffix in ["1", "2"] {
                            var payload = ShareImportPayload(text: "Synthetic pending fixture")
                            payload.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(suffix)")!
                            try inbox.publish(payload, files: [:])
                            payload.schemaVersion = 99
                            let directory = try inbox.pending().first { $0.lastPathComponent == payload.id.uuidString }!
                            try JSONEncoder().encode(payload).write(to: directory.appendingPathComponent("payload.json"))
                        }
                        if ProcessInfo.processInfo.arguments.contains("-PGOSPendingStateDamageTest") {
                            try inbox.publish(ShareImportPayload(text: "Intact share after reminder damage"), files: [:])
                            try Data("{damaged reminder fixture".utf8).write(to: container.mediaStore.rootURL.appendingPathComponent("CaptureInboxState.json"))
                        }
                        try Data().write(to: marker)
                    }
                    let report = try await importer.scanReport()
                    captureStateRecovered = report.recoveredAuxiliaryState
                    if !report.newFailureIDs.isEmpty || report.recoveredAuxiliaryState {
                        failedCaptureIDs = report.newFailureIDs
                        captureFailure = true
                    }
                } catch { captureFailure = true }
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("-PGOSCaptureShareTest") else { return }
            do {
                let inbox = try ShareInbox.shared()
                let importer = ExternalCaptureImporter(container: container.modelContainer,
                    mediaStore: container.mediaStore, inbox: inbox)
                for directory in try inbox.pending() {
                    let payload = try inbox.read(directory)
                    // Only the explicit synthetic localhost test page may enter the isolated UI store.
                    if payload.source?.url == "http://127.0.0.1:18763/capture.html" {
                        try await importer.consume(directory)
                    }
                }
            } catch { captureFailure = true }
            #endif
            return
        }
        var stage = FailureDiagnostic.Stage.appGroup
        do {
            let importer = ExternalCaptureImporter(container: container.modelContainer,
                mediaStore: container.mediaStore, inbox: try ShareInbox.shared())
            stage = .inboxState
            let report = try await importer.scanReport()
            captureDiagnostic = nil
            captureStateRecovered = report.recoveredAuxiliaryState
            captureStateWriteFailed = report.auxiliaryStateWriteFailed
            if !report.newFailureIDs.isEmpty || report.recoveredAuxiliaryState || report.auxiliaryStateWriteFailed {
                failedCaptureIDs = report.newFailureIDs
                captureFailure = true
            }
        } catch {
            let diagnostic = (error as? AppDiagnosticFailure)?.diagnostic ?? FailureDiagnostic(error: error, stage: stage)
            diagnostic.log()
            captureDiagnostic = diagnostic
            captureFailure = true
        }
    }
}

private struct TodayView: View {
    let openStorage: () -> Void
    let openGrowth: () -> Void
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var referenceDate = Date()
    @State private var showsAllHabits = false
    @State private var showsAllGoals = false
    @State private var isAddingWeight = false
    @Query private var lifecycleEvents: [HabitLifecycleEvent]
    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @Query(sort: [
        SortDescriptor(\Goal.normalizedTitle, order: .forward),
        SortDescriptor(\Goal.id, order: .forward)
    ]) private var goals: [Goal]
    @Query private var habitLogs: [HabitLog]
    @Query private var habitLogDayMetadata: [HabitLogDayMetadata]
    @Query private var habitConfigurations: [HabitConfiguration]
    @Query private var habitPlanRevisions: [HabitPlanRevision]
    @Query(sort: WeightRecordOrdering.newestFirstSortDescriptors)
    private var queriedWeightRecords: [WeightRecord]
    @Query private var weeklyReviews: [WeeklyReview]
    @State private var coolingDownHabitIDs: Set<UUID> = []
    @State private var recentCheckIn: RecentHabitCheckIn?
    @State private var transientMessage: String?
    @State private var errorMessage: String?

    private var todayHabits: [Habit] {
        TodayHabitGrouping.habits(habits, period: .day, plans: habitPlanRevisions, on: referenceDate)
    }

    private var activeGoals: [Goal] {
        goals.filter { $0.status == .active }
    }

    private var weightRecords: [WeightRecord] {
        WeightRecordOrdering.newestFirst(queriedWeightRecords)
    }

    private var thisWeeksFocus: String? {
        guard let period = try? WeeklyReviewPeriod(containing: referenceDate),
              let previousPeriod = try? period.previous(),
              let focus = weeklyReviews.first(where: {
                $0.weekIdentifier == previousPeriod.identifier
              })?.focusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !focus.isEmpty else {
            return nil
        }
        return focus
    }

    var body: some View {
        List {
            if !todayHabits.isEmpty {
                Section {
                    ForEach(showsAllHabits ? todayHabits : Array(todayHabits.prefix(4))) { habit in
                        let progress = HabitTodayProgress(
                            habitID: habit.id,
                            logs: habitLogs,
                            dayMetadata: habitLogDayMetadata,
                            settings: HabitRuntimeResolver.settings(
                                for: habit.id,
                                on: referenceDate,
                                plans: habitPlanRevisions,
                                legacyConfigurations: habitConfigurations
                            ),
                            now: referenceDate
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
                            .frame(minHeight: 52)
                        }
                    }
                    if todayHabits.count > 4 {
                        Button(showsAllHabits ? "Show Less" : "Show All Habits") { showsAllHabits.toggle() }
                            .accessibilityIdentifier("today-expand-habits")
                    }
                } header: {
                    Text("Today's Habits")
                }
            } else {
                Section("Today's Habits") {
                    Button(action: openGrowth) {
                        Label("Find or create a habit in Growth", systemImage: "leaf")
                    }
                    .accessibilityIdentifier("today-open-growth")
                }
            }
            weightSection
            if !activeGoals.isEmpty {
                Section {
                    ForEach(showsAllGoals ? activeGoals : Array(activeGoals.prefix(2))) { goal in
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
                    if activeGoals.count > 2 {
                        Button(showsAllGoals ? "Show Less" : "Show All Goals") { showsAllGoals.toggle() }
                    }
                } header: {
                    Text("Active Goals and Flags")
                }
            }
            periodSection(.week, title: "This Week")
            periodSection(.month, title: "This Month")
            if let thisWeeksFocus {
                Section("This Week’s Focus") {
                    Label(thisWeeksFocus, systemImage: "scope")
                        .accessibilityIdentifier("today-weekly-focus")
                }
            }
            reviewSection
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Today").font(.headline)
                    Text(referenceDate, format: .dateTime.month().day().weekday()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { referenceDate = Date() } }
        .sheet(isPresented: $isAddingWeight) {
            WeightEditorView(record: nil) { isAddingWeight = false }
        }
        .toolbar {
            Button(action: openStorage) {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
        .safeAreaInset(edge: .bottom) {
            if let recentCheckIn,
               HabitRuntimeResolver.settings(
                for: recentCheckIn.habitID,
                plans: habitPlanRevisions,
                legacyConfigurations: habitConfigurations
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

    private func periodSection(_ period: HabitPlanPeriod, title: LocalizedStringKey) -> some View {
        let grouped = TodayHabitGrouping.habits(habits, period: period, plans: habitPlanRevisions, on: referenceDate)
        return Group {
            if !grouped.isEmpty {
                Section(title) {
                    ForEach(grouped) { habit in
                        HabitOverviewRow(
                            habit: habit,
                            plan: HabitPlanResolver.currentPlan(for: habit.id, on: referenceDate, plans: habitPlanRevisions),
                            settings: HabitRuntimeResolver.settings(for: habit.id, on: referenceDate, plans: habitPlanRevisions, legacyConfigurations: habitConfigurations),
                            logs: habitLogs.filter { $0.habitID == habit.id },
                            dayMetadata: habitLogDayMetadata,
                            analytics: HabitAnalyticsSnapshotBuilder.summary(habit: habit, logs: habitLogs, dayMetadata: habitLogDayMetadata, plans: habitPlanRevisions, lifecycleEvents: lifecycleEvents, legacyConfigurations: habitConfigurations, asOf: referenceDate),
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    }
                }
            }
        }
    }

    private var weightSection: some View {
        Section("Weight") {
            HStack {
                NavigationLink {
                    WeightHistoryView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if let today = TodayWeightSnapshot(records: weightRecords).today {
                            Text("Recorded Today").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: WeightFormatting.kilograms(today.weightKilograms))
                                .accessibilityIdentifier("today-latest-weight")
                        } else {
                            Text("No Weight Recorded Today")
                            if let previous = TodayWeightSnapshot(records: weightRecords).previous {
                                Text("\(previous.recordedAt.formatted(date: .abbreviated, time: .omitted)) · \(WeightFormatting.kilograms(previous.weightKilograms))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("today-weight")
                Button("Record Weight") { isAddingWeight = true }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("today-add-weight")
            }
        }
    }

    private var reviewSection: some View {
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
        dayMetadata: [HabitLogDayMetadata] = [],
        settings: HabitSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let currentDay = HabitLocalDay(date: now, timeZone: calendar.timeZone).description
        let metadataByLogID = HabitLogDayResolver.metadataByLogID(dayMetadata)
        count = logs.filter {
            $0.habitID == habitID
                && $0.isCompleted
                && HabitLogDayResolver.localDay(
                    for: $0,
                    metadataByLogID: metadataByLogID,
                    fallbackTimeZone: calendar.timeZone
                ).description == currentDay
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
    @Query private var entryPins: [EntryPin]
    @State private var showsArchived = false

    private var pinnedEntries: [Entry] {
        EntryPinOrdering.entries(pins: entryPins, entries: entries)
    }

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
                    if !showsArchived && !pinnedEntries.isEmpty {
                        Section("Pinned Entries") {
                            ForEach(Array(pinnedEntries.prefix(3))) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                                } label: {
                                    PinnedEntrySummary(entry: entry)
                                }
                            }
                            if pinnedEntries.count > 3 {
                                NavigationLink("View All Pinned") {
                                    PinnedEntriesView(mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                                }
                            }
                        }
                    }
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
    @State private var pendingImportURL: URL?
    @State private var importPreview: ImportResult?
    @State private var versionCopied = false
    @State private var byteCount: Int64?
    @State private var isCapturing = false
    @State private var isConfirmingExport = false
    @State private var isConfirmingPendingExclusion = false
    @State private var isImporting = false
    @State private var isSharing = false
    @State private var exportLease: ExportPackageLease?
    @State private var transferMessage: String?
    @State private var transferTask: Task<Void, Never>?
    @State private var isTransferring = false
    @AppStorage("dailyRecordingReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("dailyRecordingReminderMinutes") private var dailyReminderMinutes = 20 * 60
    @AppStorage("weeklyReviewReminderEnabled") private var weeklyReminderEnabled = false
    @AppStorage("weeklyReviewReminderWeekday") private var weeklyReminderWeekday = 1
    @AppStorage("weeklyReviewReminderMinutes") private var weeklyReminderMinutes = 19 * 60
    @State private var notificationPermissionDenied = false
    @State private var reminderMessage: String?
    @State private var reminderAlertOffersSettings = false
    @State private var dailyReminderTask: Task<Void, Never>?
    @State private var weeklyReminderTask: Task<Void, Never>?

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
                    Toggle("Daily Recording Reminder", isOn: $dailyReminderEnabled)
                        .accessibilityIdentifier("daily-reminder-toggle")
                    if dailyReminderEnabled {
                        DatePicker(
                            "Time",
                            selection: dailyReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .accessibilityIdentifier("daily-reminder-time")
                    }

                    Toggle("Weekly Review Reminder", isOn: $weeklyReminderEnabled)
                        .accessibilityIdentifier("weekly-reminder-toggle")
                    if weeklyReminderEnabled {
                        Picker("Weekday", selection: $weeklyReminderWeekday) {
                            ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) {
                                index, weekday in
                                Text(verbatim: weekday).tag(index + 1)
                            }
                        }
                        .accessibilityIdentifier("weekly-reminder-weekday")
                        DatePicker(
                            "Time",
                            selection: weeklyReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .accessibilityIdentifier("weekly-reminder-time")
                    }

                    if notificationPermissionDenied {
                        Label(
                            "Notifications are disabled in iOS Settings.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                        Button("Open iOS Settings", action: openSystemSettings)
                            .accessibilityIdentifier("reminders-open-settings")
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders stay on this device and are scheduled only after you turn them on.")
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
                Section {
                    NavigationLink {
                        CaptureInboxView(mediaStore: mediaStore)
                    } label: {
                        Label("Pending Shares", systemImage: "tray")
                    }
                    .accessibilityIdentifier("settings-pending-shares")
                }
                Section("About") {
                    Button {
                        UIPasteboard.general.string = AppVersionInformation().displayText
                        versionCopied = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: AppVersionInformation().displayText)
                            Text(versionCopied ? "Copied" : "Tap to copy version information")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings-version")
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
                notificationPermissionDenied = await LocalReminderScheduler()
                    .authorizationIsDenied()
            }
            .onChange(of: dailyReminderEnabled) { _, enabled in
                updateDailyReminder(requestPermission: enabled)
            }
            .onChange(of: dailyReminderMinutes) { _, _ in
                guard dailyReminderEnabled else { return }
                updateDailyReminder(requestPermission: false)
            }
            .onChange(of: weeklyReminderEnabled) { _, enabled in
                updateWeeklyReminder(requestPermission: enabled)
            }
            .onChange(of: weeklyReminderWeekday) { _, _ in
                guard weeklyReminderEnabled else { return }
                updateWeeklyReminder(requestPermission: false)
            }
            .onChange(of: weeklyReminderMinutes) { _, _ in
                guard weeklyReminderEnabled else { return }
                updateWeeklyReminder(requestPermission: false)
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
            .alert("Pending shares are not in this backup", isPresented: $isConfirmingPendingExclusion) {
                Button("Share Backup") { isSharing = true }
                Button("Cancel", role: .cancel) { cleanupExport() }
            } message: {
                Text("At backup start, \(exportLease?.pendingShareCount ?? 0) shares were still pending and are not included. They remain in Pending Shares. New shares are included only after import.")
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
                    previewImport(selectedURL)
                } catch {
                    transferMessage = transferErrorMessage(error)
                }
            }
            .confirmationDialog("Restore this backup?", isPresented: Binding(
                get: { pendingImportURL != nil }, set: { if !$0 { pendingImportURL = nil; importPreview = nil } }
            ), titleVisibility: .visible) {
                Button("Restore Backup") {
                    guard let url = pendingImportURL else { return }
                    pendingImportURL = nil
                    importPreview = nil
                    startImport(url)
                }
                Button("Cancel", role: .cancel) { pendingImportURL = nil; importPreview = nil }
            } message: {
                if let importPreview {
                    Text("\(importPreview.objectCounts.values.reduce(0, +)) objects, \(importPreview.objectCounts["entryPins", default: 0]) pins, \(importPreview.objectCounts["entryFollowUps", default: 0]) follow-ups")
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
            .alert("Reminders", isPresented: Binding(
                get: { reminderMessage != nil },
                set: { if !$0 { reminderMessage = nil } }
            )) {
                if reminderAlertOffersSettings {
                    Button("Open iOS Settings", action: openSystemSettings)
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(reminderMessage ?? "")
            }
            .onDisappear {
                transferTask?.cancel()
                cleanupExport()
            }
        }
    }

    private var dailyReminderTime: Binding<Date> {
        reminderTimeBinding(minutes: $dailyReminderMinutes)
    }

    private var weeklyReminderTime: Binding<Date> {
        reminderTimeBinding(minutes: $weeklyReminderMinutes)
    }

    private func reminderTimeBinding(minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func updateDailyReminder(requestPermission: Bool) {
        dailyReminderTask?.cancel()
        dailyReminderTask = Task {
            do {
                let result = try await LocalReminderScheduler().updateDaily(
                    enabled: dailyReminderEnabled,
                    minutesAfterMidnight: dailyReminderMinutes,
                    requestPermission: requestPermission
                )
                handleReminderResult(result) { dailyReminderEnabled = false }
            } catch is CancellationError {
                return
            } catch {
                dailyReminderEnabled = false
                showReminderError()
            }
        }
    }

    private func updateWeeklyReminder(requestPermission: Bool) {
        weeklyReminderTask?.cancel()
        weeklyReminderTask = Task {
            do {
                let result = try await LocalReminderScheduler().updateWeekly(
                    enabled: weeklyReminderEnabled,
                    weekday: weeklyReminderWeekday,
                    minutesAfterMidnight: weeklyReminderMinutes,
                    requestPermission: requestPermission
                )
                handleReminderResult(result) { weeklyReminderEnabled = false }
            } catch is CancellationError {
                return
            } catch {
                weeklyReminderEnabled = false
                showReminderError()
            }
        }
    }

    private func handleReminderResult(
        _ result: ReminderUpdateResult,
        disable: () -> Void
    ) {
        switch result {
        case .scheduled:
            notificationPermissionDenied = false
        case .removed:
            break
        case .permissionDenied:
            disable()
            notificationPermissionDenied = true
            reminderAlertOffersSettings = true
            reminderMessage = String(
                localized: "Notifications are disabled. You can enable them in iOS Settings."
            )
        case .permissionRequired:
            disable()
            reminderAlertOffersSettings = false
            reminderMessage = String(localized: "Turn the reminder on again to allow notifications.")
        }
    }

    private func showReminderError() {
        reminderAlertOffersSettings = false
        reminderMessage = String(localized: "The reminder could not be updated. Please try again.")
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                exportLease = try await importExportService.exportPackage(inbox: captureManagementInbox(mediaStore: mediaStore))
                try Task.checkCancellation()
                if (exportLease?.pendingShareCount ?? 0) > 0 { isConfirmingPendingExclusion = true }
                else { isSharing = true }
            } catch is CancellationError {
                cleanupExport()
                transferMessage = String(localized: "Export cancelled. Temporary files were removed.")
            } catch {
                transferMessage = transferErrorMessage(error)
            }
        }
    }

    private func previewImport(_ url: URL) {
        isTransferring = true
        pendingImportURL = nil
        importPreview = nil
        transferTask = Task {
            defer { isTransferring = false; transferTask = nil }
            do {
                let preview = try await SecurityScopedFileAccess.perform(to: url) {
                    try await importExportService.previewPackage(from: url)
                }
                try Task.checkCancellation()
                importPreview = preview
                pendingImportURL = url
            } catch {
                pendingImportURL = nil
                importPreview = nil
                transferMessage = transferErrorMessage(error)
            }
        }
    }

    private func startImport(_ selectedURL: URL) {
        transferTask?.cancel()
        isTransferring = true
        transferTask = Task {
            defer {
                isTransferring = false
                transferTask = nil
            }
            do {
                let restored = try await SecurityScopedFileAccess.perform(to: selectedURL) {
                    try await importExportService.importPackage(from: selectedURL)
                }
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
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image ?? fallbackImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
                .accessibilityLabel("Large photo")
        }
        .overlay(alignment: .topTrailing) {
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

struct PinnedEntrySummary: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title ?? entry.body ?? String(localized: "Entry")).lineLimit(2)
            Text(entry.occurredAt, style: .date).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("pinned-entry-\(entry.id)")
    }
}

private struct PinnedEntriesView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Query private var pins: [EntryPin]
    @Query private var entries: [Entry]

    var body: some View {
        List(EntryPinOrdering.entries(pins: pins, entries: entries)) { entry in
            NavigationLink {
                EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
            } label: { PinnedEntrySummary(entry: entry) }
        }
        .navigationTitle("Pinned Entries")
    }
}


@MainActor
private func captureManagementInbox(mediaStore: MediaStore) throws -> ShareInbox {
    if AppConfiguration.current().launchMode == .uiTesting {
        return ShareInbox(root: mediaStore.rootURL.appendingPathComponent("UITestInbox"))
    }
    return try ShareInbox.shared()
}

private struct CaptureInboxView: View {
    let mediaStore: MediaStore
    @Environment(\.modelContext) private var context
    @State private var items: [CaptureInboxItem] = []
    @State private var hasStateRecoveryNotice = false
    @State private var selectedDiscard: CaptureInboxItem?
    @State private var busy = false
    @State private var failure = false
    @State private var diagnostic: FailureDiagnostic?

    var body: some View {
        List {
            if hasStateRecoveryNotice {
                Text(CaptureInboxSnapshot.recoveryMessage)
                    .accessibilityIdentifier("pending-state-recovery-notice")
            }
            if items.isEmpty {
                Text("No pending shares")
            }
            ForEach(items) { item in
                Section {
                    if let date = item.createdAt { Text(date, style: .date) }
                    Text(verbatim: String(item.id.prefix(8))).font(.caption).foregroundStyle(.secondary)
                    Text(item.reason.title)
                    if let diagnostic = item.diagnostic {
                        Button("Copy Diagnostic Report") { UIPasteboard.general.string = diagnostic.report }
                    }
                    if item.isDeferred { Text("Kept for later").foregroundStyle(.secondary) }
                    if item.isCommitted {
                        Text("The entry is already saved. These actions only remove the remaining Inbox copy.")
                            .font(.caption)
                    }
                    Button("Retry") { perform { try await $0.retry(item.id) } }
                    Button("Keep for Later") { perform { try await $0.keepForLater([item.id]) } }
                    Button(item.isCommitted ? "Remove Pending Copy" : "Discard Share", role: .destructive) {
                        selectedDiscard = item
                    }
                    .accessibilityIdentifier("pending-discard-\(item.id)")
                }
            }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .navigationTitle("Pending Shares")
        .task { await refresh() }
        .alert("Remove this pending share?", isPresented: Binding(
            get: { selectedDiscard != nil }, set: { if !$0 { selectedDiscard = nil } }
        ), presenting: selectedDiscard) { item in
            Button(item.isCommitted ? "Remove Pending Copy" : "Discard Share", role: .destructive) {
                perform { try await $0.discardPending(item.id) }
            }
            Button("Cancel", role: .cancel) { selectedDiscard = nil }
        } message: { item in
            Text(item.isCommitted
                ? "The saved entry will remain. Only this Inbox copy will be removed."
                : "This share has not been imported. Its pending content will be permanently removed.")
        }
        .alert("Import needs attention", isPresented: $failure) {
            Button("OK", role: .cancel) {}
            if let diagnostic {
                Button("Copy Diagnostic Report") { UIPasteboard.general.string = diagnostic.report }
            }
        } message: {
            Text("The shared files are retained. You can retry when storage is available or after updating the app.")
        }
    }

    private func importer() throws -> ExternalCaptureImporter {
        ExternalCaptureImporter(container: context.container, mediaStore: mediaStore,
            inbox: try captureManagementInbox(mediaStore: mediaStore))
    }

    private func recordFailure(_ error: Error) {
        diagnostic = (error as? AppDiagnosticFailure)?.diagnostic ?? FailureDiagnostic(error: error, stage: .inboxState)
        diagnostic?.log()
        failure = true
    }

    private func refresh() async {
        do {
            let snapshot = try await importer().pendingSnapshot()
            items = snapshot.items
            hasStateRecoveryNotice = snapshot.hasStateRecoveryNotice
        }
        catch { recordFailure(error) }
    }

    private func perform(_ operation: @escaping (ExternalCaptureImporter) async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(importer()) }
            catch { recordFailure(error) }
            await refresh()
        }
    }
}
