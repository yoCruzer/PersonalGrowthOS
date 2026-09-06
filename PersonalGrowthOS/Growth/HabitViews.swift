import SwiftData
import SwiftUI
import UIKit

struct GrowthView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query private var habits: [Habit]
    @Query private var goals: [Goal]
    @Query private var weightRecords: [WeightRecord]

    var body: some View {
        List {
            NavigationLink {
                HabitsView(
                    mediaStore: mediaStore,
                    thumbnailStore: thumbnailStore
                )
            } label: {
                HStack {
                    Label("Habits", systemImage: "repeat")
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                    Text("\(habits.count)")
                }
            }
            .accessibilityIdentifier("growth-habits")
            NavigationLink {
                GoalsView(
                    mediaStore: mediaStore,
                    thumbnailStore: thumbnailStore
                )
            } label: {
                HStack {
                    Label("Goals and Flags", systemImage: "target")
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                    Text("\(goals.count)")
                }
            }
            .accessibilityIdentifier("growth-goals")
            NavigationLink {
                WeightHistoryView()
            } label: {
                HStack {
                    Label("Weight", systemImage: "scalemass")
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                    Text("\(weightRecords.count)")
                }
            }
            .accessibilityIdentifier("growth-weight")
        }
        .navigationTitle("Growth")
        .accessibilityIdentifier("growth-view")
    }
}

struct GrowthEmptyStateAddButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .contentShape(.rect)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

struct RepeatableHabitCounter: View {
    let habitName: String
    let progress: HabitTodayProgress
    let accessibilityIdentifierPrefix: String
    var showsHabitName = true
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsHabitName {
                Text(habitName)
                    .lineLimit(2)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            controls
        }
        .frame(minHeight: 52)
    }

    private var controls: some View {
        ZStack {
            Capsule()
                .fill(.quaternary)
                .frame(height: 30)
            Capsule()
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                .frame(height: 30)
            HStack(spacing: 0) {
                Button(action: decrease) {
                    Image(systemName: "minus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .disabled(progress.count == 0)
                .accessibilityLabel("Decrease \(habitName)")
                .accessibilityValue("Current count: \(progress.count)")
                .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-decrease")

                Text(countText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Current count")
                    .accessibilityValue("\(progress.count)")
                    .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-count")

                Button(action: increase) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Increase \(habitName)")
                .accessibilityValue("Current count: \(progress.count)")
                .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-increase")
            }
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var countText: String {
        if let target = progress.settings.dailyTargetCount {
            return "\(progress.count)/\(target)"
        }
        return "\(progress.count)"
    }
}

struct HabitsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @Query private var planRevisions: [HabitPlanRevision]
    @Query private var configurations: [HabitConfiguration]
    @Query private var allLogs: [HabitLog]
    @Query private var allLogDayMetadata: [HabitLogDayMetadata]
    @Query private var lifecycleEvents: [HabitLifecycleEvent]
    @State private var isCreatingHabit = false

    private var mainHabits: [Habit] {
        habits.filter { $0.status != .archived }
    }

    private var archivedHabits: [Habit] {
        habits.filter { $0.status == .archived }
    }

    private func section(for habit: Habit) -> String {
        let plan = HabitPlanResolver.currentPlan(for: habit.id, plans: planRevisions)
        return switch plan?.period {
        case .week: "This Week"
        case .month: "This Month"
        case .trackingOnly: "Tracking Only"
        default: "Today"
        }
    }

    var body: some View {
        List {
            if mainHabits.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView {
                            Label("No Habits", systemImage: "repeat")
                        } description: {
                            Text("Add a habit you want to practice. Pauses and restarts are part of growth.")
                        }
                        GrowthEmptyStateAddButton(
                            title: "Add Habit",
                            systemImage: "plus",
                            action: { isCreatingHabit = true }
                        )
                        .accessibilityIdentifier("add-habit")
                    }
                } footer: {
                    Text("Use a specific, actionable name. You can change it later without losing check-ins.")
                }
            } else {
                ForEach(["Today", "This Week", "This Month", "Tracking Only"], id: \.self) { title in
                    let grouped = mainHabits.filter { section(for: $0) == title }
                    if !grouped.isEmpty {
                        Section(title) {
                            ForEach(grouped) { habit in
                                HabitOverviewRow(
                                    habit: habit,
                                    plan: HabitPlanResolver.currentPlan(for: habit.id, plans: planRevisions),
                                    settings: HabitRuntimeResolver.settings(
                                        for: habit.id,
                                        plans: planRevisions,
                                        legacyConfigurations: configurations
                                    ),
                                    logs: allLogs.filter { $0.habitID == habit.id },
                                    dayMetadata: allLogDayMetadata,
                                    analytics: HabitAnalyticsSnapshotBuilder.summary(
                                        habit: habit,
                                        logs: allLogs,
                                        dayMetadata: allLogDayMetadata,
                                        plans: planRevisions,
                                        lifecycleEvents: lifecycleEvents,
                                        legacyConfigurations: configurations
                                    ),
                                    mediaStore: mediaStore,
                                    thumbnailStore: thumbnailStore
                                )
                            }
                        }
                    }
                }
            }
            if !archivedHabits.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedHabitsView(
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        LabeledContent("Archived", value: "\(archivedHabits.count)")
                    }
                    .accessibilityIdentifier("archived-habits")
                }
            }
        }
        .navigationTitle("Habits")
        .toolbar {
            if !mainHabits.isEmpty {
                Button {
                    isCreatingHabit = true
                } label: {
                    Label("Add Habit", systemImage: "plus")
                }
                .accessibilityIdentifier("add-habit")
            }
        }
        .sheet(isPresented: $isCreatingHabit) {
            HabitEditorView(
                habit: nil,
                settings: HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil),
                plan: nil,
                pendingEffectiveDay: nil,
                didSave: { isCreatingHabit = false }
            )
        }
    }
}

private struct HabitOverviewRow: View {
    let habit: Habit
    let plan: HabitPlan?
    let settings: HabitSettings
    let logs: [HabitLog]
    let dayMetadata: [HabitLogDayMetadata]
    let analytics: HabitAnalyticsSummary
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.modelContext) private var modelContext

    private var isScheduledToday: Bool {
        plan.map { HabitPlanResolver.isScheduled($0, on: Date()) } ?? true
    }

    private var checkedInToday: Bool {
        progress.isCompletedForOncePerDay
    }

    private var progress: HabitTodayProgress {
        HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            dayMetadata: dayMetadata,
            settings: settings
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                HabitDetailView(
                    habit: habit,
                    mediaStore: mediaStore,
                    thumbnailStore: thumbnailStore
                )
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                    Text(periodProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("habit-\(habit.normalizedName)")

            if habit.status == .active && isScheduledToday {
                if settings.recordingMode == .multiplePerDay {
                    RepeatableHabitCounter(
                        habitName: habit.name,
                        progress: progress,
                        accessibilityIdentifierPrefix: "habit-overview-counter",
                        showsHabitName: false,
                        decrease: decrement,
                        increase: increment
                    )
                } else {
                    Button(action: checkIn) {
                        Image(systemName: checkedInToday ? "checkmark.circle.fill" : "checkmark.circle")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(checkedInToday)
                    .accessibilityLabel("Check in \(habit.name)")
                    .accessibilityIdentifier("habit-overview-check-in")
                }
            }
        }
    }

    private var periodProgressText: String {
        guard let current = analytics.current else { return habit.status.localizedName }
        if current.period == .trackingOnly || current.target == nil {
            return current.actual == 1 ? "1 recorded" : "\(current.actual) recorded"
        }
        let remaining = max((current.target ?? 0) - current.actual, 0)
        let scope: String = switch current.period {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .trackingOnly: ""
        }
        if current.outcome == .notEvaluated(.notScheduled) {
            return current.actual > 0 ? "\(current.actual) recorded · Rest day" : "Rest day"
        }
        return remaining > 0
            ? "\(current.actual)/\(current.target ?? 0) \(scope) · \(remaining) remaining"
            : "\(current.actual)/\(current.target ?? 0) \(scope)"
    }

    private func checkIn() {
        _ = try? HabitCheckInService(context: modelContext, mediaStore: mediaStore).checkIn(habit)
    }

    private func increment() {
        _ = try? HabitCheckInService(context: modelContext, mediaStore: mediaStore).incrementCount(habit)
    }

    private func decrement() {
        _ = try? HabitCheckInService(context: modelContext, mediaStore: mediaStore)
            .removeLatestStructuredCheckIn(habitID: habit.id)
    }
}

private struct ArchivedHabitsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]

    private var archivedHabits: [Habit] {
        habits.filter { $0.status == .archived }
    }

    var body: some View {
        Group {
            if archivedHabits.isEmpty {
                ContentUnavailableView(
                    "No Archived Habits",
                    systemImage: "archivebox",
                    description: Text("Archived habits are hidden from Today and the main Habits list. Their history is kept and they can be restored.")
                )
            } else {
                List(archivedHabits) { habit in
                    NavigationLink {
                        HabitDetailView(
                            habit: habit,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        LabeledContent(habit.name, value: habit.status.localizedName)
                    }
                    .accessibilityIdentifier("archived-habit-\(habit.normalizedName)")
                }
            }
        }
        .navigationTitle("Archived")
        .safeAreaInset(edge: .bottom) {
            Text("Archived habits are hidden from Today and the main Habits list. Their history is kept and they can be restored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .accessibilityIdentifier("archived-habits-view")
    }
}

struct HabitDetailView: View {
    let habit: Habit
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\HabitLog.occurredAt, order: .reverse),
        SortDescriptor(\HabitLog.createdAt, order: .reverse),
        SortDescriptor(\HabitLog.id, order: .forward)
    ]) private var allLogs: [HabitLog]
    @Query private var allLogDayMetadata: [HabitLogDayMetadata]
    @Query private var configurations: [HabitConfiguration]
    @Query private var planRevisions: [HabitPlanRevision]
    @Query private var lifecycleEvents: [HabitLifecycleEvent]
    @Query private var entries: [Entry]
    @Query private var links: [ObjectLink]
    @Query private var goals: [Goal]
    @State private var isAddingInsight = false
    @State private var isLoggingDetails = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isCoolingDown = false
    @State private var recentCheckIn: RecentHabitCheckIn?
    @State private var transientMessage: String?
    @State private var errorMessage: String?

    private var logs: [HabitLog] {
        allLogs.filter { $0.habitID == habit.id }
    }

    private var entriesByID: [UUID: Entry] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var settings: HabitSettings {
        HabitRuntimeResolver.settings(
            for: habit.id,
            plans: planRevisions,
            legacyConfigurations: configurations
        )
    }

    private var currentPlan: HabitPlan? {
        HabitPlanResolver.currentPlan(
            for: habit.id,
            plans: planRevisions
        )
    }

    private var pendingPlanRevision: HabitPlanRevision? {
        HabitPlanResolver.pendingPlanRevision(
            for: habit.id,
            plans: planRevisions
        )
    }

    private var checkedInToday: Bool {
        todayProgress.isCompletedForOncePerDay
    }

    private var todayProgress: HabitTodayProgress {
        HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            dayMetadata: allLogDayMetadata,
            settings: settings
        )
    }

    private var analytics: HabitAnalyticsSummary {
        HabitAnalyticsSnapshotBuilder.summary(
            habit: habit,
            logs: logs,
            dayMetadata: allLogDayMetadata,
            plans: planRevisions,
            lifecycleEvents: lifecycleEvents,
            legacyConfigurations: configurations
        )
    }

    private var relatedInsights: [Entry] {
        let entryIDs = Set(links.compactMap { link -> UUID? in
            link.targetTypeRawValue == LinkObjectType.habit.rawValue && link.targetID == habit.id
                && link.sourceTypeRawValue == LinkObjectType.entry.rawValue ? link.sourceID : nil
        })
        return entries.filter { entryIDs.contains($0.id) }
    }

    private var relatedGoals: [Goal] {
        let goalIDs = Set(links.compactMap { link -> UUID? in
            link.sourceTypeRawValue == LinkObjectType.habit.rawValue && link.sourceID == habit.id
                && link.targetTypeRawValue == LinkObjectType.goal.rawValue ? link.targetID : nil
        })
        return goals.filter { goalIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                if let current = analytics.current {
                    LabeledContent("Progress", value: progressText(current))
                }
                LabeledContent("Status", value: habit.status.localizedName)
                if habit.status == .active {
                    if settings.recordingMode == .multiplePerDay {
                        RepeatableHabitCounter(
                            habitName: habit.name,
                            progress: todayProgress,
                            accessibilityIdentifierPrefix: "habit-detail-counter",
                            decrease: decrementRepeatable,
                            increase: incrementRepeatable
                        )
                    } else {
                        Button {
                            simpleCheckIn()
                        } label: {
                            Label(
                                checkedInToday ? "Completed Today" : "Check In",
                                systemImage: checkedInToday
                                    ? "checkmark.circle.fill"
                                    : "checkmark.circle"
                            )
                        }
                        .disabled(isCoolingDown || checkedInToday)
                        .accessibilityIdentifier("habit-check-in")
                    }

                    Button {
                        isLoggingDetails = true
                    } label: {
                        Label("Log Details", systemImage: "list.bullet.clipboard")
                    }
                    .disabled(isCoolingDown || (settings.recordingMode == .oncePerDay && checkedInToday))
                    .accessibilityIdentifier("habit-log-details")

                    Button {
                        isAddingInsight = true
                    } label: {
                        Label("Check In with Insight", systemImage: "square.and.pencil")
                    }
                    .disabled(isCoolingDown || (settings.recordingMode == .oncePerDay && checkedInToday))
                    .accessibilityIdentifier("habit-check-in-insight")
                }
                if let adherence = analytics.adherence {
                    LabeledContent("Adherence", value: adherence.formatted(.percent.precision(.fractionLength(0))))
                }
                if let currentStreak = analytics.currentStreak,
                   let unit = analytics.streakUnit {
                    LabeledContent("Current Streak", value: streakText(currentStreak, unit: unit))
                    LabeledContent("Best Streak", value: streakText(analytics.bestStreak ?? 0, unit: unit))
                }
            } header: {
                Text("Now")
            } footer: {
                Text("A simple check-in saves only a structured fact. Text and photos are saved in a linked Entry.")
            }
            HabitAnalyticsDashboard(
                summary: analytics,
                habitName: habit.name,
                plans: planRevisions.filter { $0.habitID == habit.id },
                lifecycleEvents: lifecycleEvents.filter { $0.habitID == habit.id },
                insights: relatedInsights,
                goals: relatedGoals,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
            Section("Recent Activity") {
                if logs.isEmpty {
                    Text("No check-ins yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs.prefix(5)) { log in
                        HabitActivityRow(
                            log: log,
                            entry: log.linkedEntryID.flatMap { entriesByID[$0] },
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    }
                    NavigationLink("View All Activity") {
                        HabitHistoryView(
                            habitName: habit.name,
                            logs: logs,
                            entriesByID: entriesByID,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    }
                }
            }
        }
        .navigationTitle(habit.name)
        .toolbar {
            Button("Edit") {
                isEditing = true
            }
            .accessibilityIdentifier("habit-edit")
            Menu {
                lifecycleActions
                Divider()
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("habit-actions")
        }
        .sheet(isPresented: $isLoggingDetails) {
            DetailedHabitCheckInView { draft in
                let log = try HabitCheckInService(
                    context: modelContext,
                    mediaStore: mediaStore
                ).checkIn(habit, draft: draft)
                registerSuccessfulCheckIn(log)
            }
        }
        .sheet(isPresented: $isAddingInsight) {
            QuickCaptureView(
                mediaStore: mediaStore,
                navigationTitle: String(localized: "Habit Insight"),
                saveDraft: { draft in
                    let result = try HabitCheckInService(
                        context: modelContext,
                        mediaStore: mediaStore
                    ).checkInWithInsight(habit, entryDraft: draft)
                    registerSuccessfulCheckIn(result.log)
                    return result.entry
                },
                didSave: { _ in isAddingInsight = false }
            )
        }
        .sheet(isPresented: $isEditing) {
            HabitEditorView(
                habit: habit,
                settings: settings,
                plan: pendingPlanRevision?.plan ?? currentPlan,
                pendingEffectiveDay: pendingPlanRevision.flatMap {
                    HabitLocalDay($0.effectiveLocalDay)
                },
                didSave: { isEditing = false }
            )
        }
        .safeAreaInset(edge: .bottom) {
            if settings.recordingMode == .oncePerDay, let recentCheckIn {
                HabitCheckInUndoBar {
                    undo(recentCheckIn)
                }
            } else if let transientMessage {
                Text(transientMessage)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
        .alert("Delete this Habit permanently?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { permanentlyDelete() }
        } message: {
            Text("Its structured check-ins will be deleted. Linked Entries will remain.")
        }
        .alert("Could Not Update Habit", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
    }

    private func progressText(_ evaluation: HabitPeriodEvaluation) -> String {
        if evaluation.outcome == .notEvaluated(.notScheduled) {
            return evaluation.actual > 0
                ? "Rest day · \(evaluation.actual) recorded"
                : "Rest day"
        }
        guard let target = evaluation.target else { return "\(evaluation.actual) recorded" }
        let scope: String = switch evaluation.period {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .trackingOnly: ""
        }
        return "\(evaluation.actual)/\(target) \(scope)"
    }

    private func streakText(_ count: Int, unit: String) -> String {
        let singular = switch unit {
        case "days": "day"
        case "weeks": "week"
        case "months": "month"
        default: unit
        }
        return "\(count) \(count == 1 ? singular : unit)"
    }

    @ViewBuilder
    private var lifecycleActions: some View {
        switch habit.status {
        case .active:
            Button("Pause", systemImage: "pause") { transition(to: .paused) }
            Button("Complete", systemImage: "checkmark") { transition(to: .completed) }
            Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
        case .paused:
            Button("Resume", systemImage: "play") { transition(to: .active) }
            Button("Complete", systemImage: "checkmark") { transition(to: .completed) }
            Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
        case .completed:
            Button("Restart", systemImage: "arrow.clockwise") { transition(to: .active) }
            Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
        case .archived:
            Button("Restore", systemImage: "arrow.uturn.backward") { transition(to: .active) }
        }
    }

    private func simpleCheckIn() {
        do {
            let log = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).checkIn(habit)
            registerSuccessfulCheckIn(log)
        } catch HabitCheckInError.alreadyCheckedInToday {
            showTransientMessage(String(localized: "This Habit is already completed today."))
        } catch HabitCheckInError.recentlyCheckedIn {
            showTransientMessage(String(localized: "Just checked in. Try again in a moment."))
        } catch {
            errorMessage = String(localized: "The check-in was not saved.")
        }
    }

    private func incrementRepeatable() {
        do {
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).incrementCount(habit)
            recentCheckIn = nil
            isCoolingDown = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = String(localized: "The check-in was not saved.")
        }
    }

    private func decrementRepeatable() {
        do {
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).removeLatestStructuredCheckIn(habitID: habit.id)
            recentCheckIn = nil
            isCoolingDown = false
        } catch {
            errorMessage = String(localized: "The latest check-in could not be undone.")
        }
    }

    private func registerSuccessfulCheckIn(_ log: HabitLog) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        transientMessage = nil
        guard settings.recordingMode == .oncePerDay else {
            recentCheckIn = nil
            isCoolingDown = false
            return
        }
        recentCheckIn = RecentHabitCheckIn(habitID: habit.id, logID: log.id)
        isCoolingDown = true
        let logID = log.id
        Task {
            try? await Task.sleep(for: .seconds(HabitCheckInPolicy.duplicatePreventionInterval))
            isCoolingDown = false
            try? await Task.sleep(for: .seconds(
                HabitCheckInPolicy.undoPresentationInterval
                    - HabitCheckInPolicy.duplicatePreventionInterval
            ))
            if recentCheckIn?.logID == logID {
                recentCheckIn = nil
            }
        }
    }

    private func undo(_ checkIn: RecentHabitCheckIn) {
        do {
            try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).undoLatestCheckIn(habitID: checkIn.habitID, logID: checkIn.logID)
            recentCheckIn = nil
            isCoolingDown = false
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

    private func transition(to status: HabitStatus) {
        do {
            try HabitService(context: modelContext).transition(habit, to: status)
        } catch {
            errorMessage = String(localized: "The Habit status was not changed.")
        }
    }

    private func permanentlyDelete() {
        do {
            try HabitService(context: modelContext).permanentlyDelete(habit)
            dismiss()
        } catch {
            errorMessage = String(localized: "The Habit was not deleted. Its check-ins and links are unchanged.")
        }
    }
}

private struct HabitActivityRow: View {
    let log: HabitLog
    let entry: Entry?
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    var body: some View {
        if let entry {
            NavigationLink {
                EntryDetailView(
                    entry: entry,
                    mediaStore: mediaStore,
                    thumbnailStore: thumbnailStore
                )
            } label: {
                HabitLogRow(log: log, hasInsight: true)
            }
        } else {
            HabitLogRow(log: log, hasInsight: false)
        }
    }
}

private struct HabitHistoryView: View {
    let habitName: String
    let logs: [HabitLog]
    let entriesByID: [UUID: Entry]
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    var body: some View {
        List(logs) { log in
            HabitActivityRow(
                log: log,
                entry: log.linkedEntryID.flatMap { entriesByID[$0] },
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
        }
        .navigationTitle("\(habitName) Activity")
    }
}

private struct HabitEditorView: View {
    let habit: Habit?
    let initialPlan: HabitPlan
    let pendingEffectiveDay: HabitLocalDay?
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var recordingMode: HabitRecordingMode
    @State private var dailyTarget = ""
    @State private var goalChoice: HabitGoalChoice
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var errorMessage: String?

    init(
        habit: Habit?,
        settings: HabitSettings,
        plan: HabitPlan?,
        pendingEffectiveDay: HabitLocalDay?,
        didSave: @escaping () -> Void
    ) {
        self.habit = habit
        self.didSave = didSave
        _name = State(initialValue: habit?.name ?? "")
        let initialPlan = plan ?? HabitPlan.legacy(
            mode: settings.recordingMode,
            target: settings.dailyTargetCount
        )
        self.initialPlan = initialPlan
        self.pendingEffectiveDay = pendingEffectiveDay
        let initialChoice = HabitGoalChoice(plan: initialPlan)
        let initialMode = initialPlan.recordingMode
        _recordingMode = State(initialValue: initialMode)
        _dailyTarget = State(initialValue: initialChoice.requiresTarget(for: initialMode)
            ? String(initialPlan.targetCount ?? 1)
            : "")
        _goalChoice = State(initialValue: initialChoice)
        _selectedWeekdays = State(initialValue: initialPlan.weekdays.isEmpty
            ? [2, 3, 4, 5, 6]
            : initialPlan.weekdays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                        .accessibilityIdentifier("habit-editor-name")
                } header: {
                    Text("Habit Name")
                } footer: {
                    Text("Use a specific, actionable name, such as Drink 200 ml of water, Read for 20 minutes, or Sleep before 11 PM. You can change the name later without losing check-ins.")
                }

                Section {
                    Picker("Recording Mode", selection: $recordingMode) {
                        ForEach(HabitRecordingMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("habit-recording-mode")

                    if needsTarget {
                        TextField(goalChoice == .everyDay ? "Daily Target" : "Target", text: $dailyTarget)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("habit-daily-target")
                    }
                    Picker("Goal", selection: $goalChoice) {
                        ForEach(HabitGoalChoice.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .accessibilityIdentifier("habit-goal")

                    if goalChoice == .selectedDays {
                        ForEach(1...7, id: \.self) { weekday in
                            Toggle(weekdayName(weekday), isOn: Binding(
                                get: { selectedWeekdays.contains(weekday) },
                                set: { enabled in
                                    if enabled { selectedWeekdays.insert(weekday) }
                                    else { selectedWeekdays.remove(weekday) }
                                }
                            ))
                        }
                    }
                } header: {
                    Text("Check-In Frequency")
                } footer: {
                    Text(goalChoice == .noGoal
                        ? String(localized: "Tracking Only records activity without a target or missed days.")
                        : (recordingMode == .oncePerDay
                        ? String(localized: "Choose this when completing the Habit once is enough for the day.")
                        : String(localized: "Choose this for Habits you may record several times each day. Set a target you can exceed.")))
                }

                if habit != nil {
                    Section {
                        Text("Changing the name does not affect history. If the Habit itself has changed, consider archiving it and creating a new one.")
                            .foregroundStyle(.secondary)
                        if let pendingEffectiveDay {
                            LabeledContent("Pending Plan", value: "Starts \(pendingEffectiveDay.description)")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(
                habit == nil
                    ? String(localized: "New Habit")
                    : String(localized: "Edit Habit")
            )
            .onChange(of: recordingMode) { _, mode in
                if mode == .multiplePerDay,
                   dailyTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dailyTarget = "2"
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("habit-editor-save")
                }
            }
        }
    }

    private func save() {
        let target: Int?
        let trimmedTarget = dailyTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsTarget {
            guard let value = Int(trimmedTarget), value > 0 else {
                errorMessage = String(localized: "Daily target must be a positive whole number.")
                return
            }
            target = value
        } else {
            target = nil
        }

        do {
            let service = HabitService(context: modelContext)
            let plan = makePlan(target: target)
            if let habit {
                try service.update(
                    habit,
                    name: name,
                    planChange: plan == initialPlan ? nil : plan
                )
            } else {
                _ = try service.create(name: name, plan: plan)
            }
            didSave()
            dismiss()
        } catch HabitValidationError.emptyName {
            errorMessage = String(localized: "Habit name cannot be empty.")
        } catch HabitValidationError.invalidDailyTarget {
            errorMessage = String(localized: "Daily target must be a positive whole number.")
        } catch {
            errorMessage = String(localized: "The Habit was not saved.")
        }
    }

    private func makePlan(target: Int?) -> HabitPlan {
        switch goalChoice {
        case .noGoal: .trackingOnly(recordingMode: recordingMode)
        case .everyDay: HabitPlan(recordingMode: recordingMode, period: .day, goal: .everyDay, targetCount: recordingMode == .oncePerDay ? 1 : target, weekdays: [])
        case .selectedDays: HabitPlan(recordingMode: recordingMode, period: .day, goal: .selectedWeekdays, targetCount: recordingMode == .oncePerDay ? 1 : target, weekdays: selectedWeekdays)
        case .perWeek: HabitPlan(recordingMode: recordingMode, period: .week, goal: .count, targetCount: target ?? 1, weekdays: [])
        case .perMonth: HabitPlan(recordingMode: recordingMode, period: .month, goal: .count, targetCount: target ?? 1, weekdays: [])
        }
    }

    private var needsTarget: Bool {
        goalChoice.requiresTarget(for: recordingMode)
    }

    private func weekdayName(_ weekday: Int) -> String {
        let calendar = Calendar.current
        return calendar.weekdaySymbols[weekday - 1]
    }
}

private enum HabitGoalChoice: String, CaseIterable {
    case noGoal, everyDay, selectedDays, perWeek, perMonth
    var title: String {
        switch self {
        case .noGoal: "No Goal"
        case .everyDay: "Every Day"
        case .selectedDays: "Selected Days"
        case .perWeek: "Times per Week"
        case .perMonth: "Times per Month"
        }
    }

    init(plan: HabitPlan) {
        switch plan.period {
        case .trackingOnly: self = .noGoal
        case .week: self = .perWeek
        case .month: self = .perMonth
        case .day: self = plan.goal == .selectedWeekdays ? .selectedDays : .everyDay
        }
    }

    func requiresTarget(for recordingMode: HabitRecordingMode) -> Bool {
        self != .noGoal && !(self == .everyDay && recordingMode == .oncePerDay)
    }
}

struct RecentHabitCheckIn: Equatable {
    let habitID: UUID
    let logID: UUID
}

private struct HabitAnalyticsDashboard: View {
    let summary: HabitAnalyticsSummary
    let habitName: String
    let plans: [HabitPlanRevision]
    let lifecycleEvents: [HabitLifecycleEvent]
    let insights: [Entry]
    let goals: [Goal]
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    var body: some View {
        if let current = summary.current {
            Section("Progress") {
                if current.period == .day {
                    HabitMonthCalendar(
                        summary: summary,
                        asOf: HabitLocalDay(date: Date())
                    )
                } else {
                    PeriodActivityGrid(evaluation: current, activity: summary.activityByDay)
                }
                if let consistency = summary.consistency {
                    LabeledContent("Consistency", value: consistency.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            Section("Year Activity") {
                let total = summary.activityByDay.values.reduce(0, +)
                LabeledContent("Completed check-ins", value: "\(total)")
                ActivityHeatmap(activity: summary.activityByDay)
                    .accessibilityLabel("Year activity for \(habitName)")
            }
            Section("Trend") {
                let recent = summary.evaluations.suffix(6)
                ForEach(recent) { evaluation in
                    LabeledContent(evaluation.start.description, value: progressText(evaluation))
                }
            }
            Section("Weekday Pattern") {
                let pattern = HabitWeekdayPatternBuilder.make(
                    period: current.period,
                    evaluations: summary.evaluations,
                    activityByDay: summary.activityByDay
                )
                Text(pattern.metric == .scheduledDaySuccessRate
                    ? "Success rate on scheduled days"
                    : "Activity distribution by weekday")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WeekdayPatternView(pattern: pattern)
            }
            Section("Journey") {
                let items = HabitJourneyBuilder.items(
                    plans: plans,
                    lifecycleEvents: lifecycleEvents
                )
                if items.isEmpty {
                    Text("No changes yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        switch item.kind {
                        case .plan(let plan):
                            LabeledContent(item.day.description, value: planDescription(plan))
                        case .lifecycle(let kind):
                            LabeledContent(item.day.description, value: lifecycleDescription(kind))
                        }
                    }
                }
            }
            if !insights.isEmpty || !goals.isEmpty {
                Section("Context") {
                    ForEach(insights) { entry in
                        NavigationLink {
                            EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                        } label: {
                            Label(entry.title ?? entry.body ?? "Insight", systemImage: "doc.text")
                        }
                    }
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal: goal, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                        } label: {
                            Label(goal.title, systemImage: "target")
                        }
                    }
                }
            }
            if summary.coverageStart != nil {
                Section {
                    Text("Earlier activity remains visible. Strict adherence begins with trusted plan coverage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func planDescription(_ plan: HabitPlan) -> String {
        if plan.isTrackingOnly { return "Tracking Only" }
        switch plan.period {
        case .day: return plan.goal == .selectedWeekdays ? "Selected Days" : "Daily \(plan.targetCount ?? 1)"
        case .week: return "\(plan.targetCount ?? 0) per week"
        case .month: return "\(plan.targetCount ?? 0) per month"
        case .trackingOnly: return "Tracking Only"
        }
    }

    private func progressText(_ evaluation: HabitPeriodEvaluation) -> String {
        guard let target = evaluation.target else { return "\(evaluation.actual) recorded" }
        return "\(evaluation.actual)/\(target)"
    }

    private func lifecycleDescription(_ kind: HabitLifecycleEventKind) -> String {
        switch kind {
        case .migrationBaseline: return "Migration Baseline"
        case .created: return "Created"
        case .paused: return "Paused"
        case .resumed: return "Resumed"
        case .completed: return "Completed"
        case .archived: return "Archived"
        case .restarted: return "Restarted"
        case .restored: return "Restored"
        }
    }
}

private struct HabitMonthCalendar: View {
    let summary: HabitAnalyticsSummary
    let asOf: HabitLocalDay

    private var cells: [HabitCalendarDayCell] {
        HabitMonthCalendarBuilder.cells(
            containing: asOf,
            evaluations: summary.evaluations,
            activityByDay: summary.activityByDay
        )
    }

    private var leadingPlaceholders: Int {
        guard let first = cells.first?.day.date() else { return 0 }
        return WeeklyReviewCalendarPolicy.calendar().component(.weekday, from: first) - 1
    }

    var body: some View {
        let calendar = WeeklyReviewCalendarPolicy.calendar()
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(calendar.veryShortWeekdaySymbols.indices, id: \.self) { index in
                    Text(calendar.veryShortWeekdaySymbols[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 6
            ) {
                ForEach(0..<leadingPlaceholders, id: \.self) { _ in
                    Color.clear.frame(height: 28)
                }
                ForEach(cells) { cell in
                    VStack(spacing: 2) {
                        Text("\(cell.day.day)")
                        ZStack {
                            Circle()
                                .fill(color(for: cell.state))
                                .frame(width: 9, height: 9)
                            if cell.activityCount > 0 && cell.state != .achieved {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1.5)
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: cell))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Month calendar")
    }

    private func color(for state: HabitCalendarDayState) -> Color {
        switch state {
        case .achieved: .green
        case .missed: .red
        case .open: .accentColor
        case .rest: .secondary.opacity(0.2)
        case .neutral: .orange.opacity(0.35)
        case .beforeCoverage: .secondary.opacity(0.35)
        case .future: .secondary.opacity(0.1)
        }
    }

    private func accessibilityLabel(for cell: HabitCalendarDayCell) -> String {
        let state: String = switch cell.state {
        case .achieved: "achieved"
        case .missed: "missed"
        case .open: "open"
        case .rest: "rest day"
        case .neutral: "neutral"
        case .beforeCoverage: "before trusted coverage"
        case .future: "future"
        }
        return "\(cell.day.description), \(state), \(cell.activityCount) activities"
    }
}

private struct WeekdayPatternView: View {
    let pattern: HabitWeekdayPattern

    var body: some View {
        let calendar = WeeklyReviewCalendarPolicy.calendar()
        HStack(spacing: 8) {
            ForEach(pattern.buckets) { bucket in
                VStack(spacing: 2) {
                    Text(calendar.veryShortWeekdaySymbols[bucket.weekday - 1])
                    Text(valueText(bucket)).monospacedDigit()
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(bucket, calendar: calendar))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pattern.metric == .scheduledDaySuccessRate
            ? "Weekday scheduled success rate"
            : "Weekday activity distribution")
    }

    private func valueText(_ bucket: HabitWeekdayPatternBucket) -> String {
        switch pattern.metric {
        case .scheduledDaySuccessRate:
            return bucket.successRate?.formatted(.percent.precision(.fractionLength(0))) ?? "—"
        case .activityDistribution:
            return "\(bucket.activityCount)"
        }
    }

    private func accessibilityLabel(_ bucket: HabitWeekdayPatternBucket, calendar: Calendar) -> String {
        let weekday = calendar.weekdaySymbols[bucket.weekday - 1]
        switch pattern.metric {
        case .scheduledDaySuccessRate:
            guard let rate = bucket.successRate else { return "\(weekday), no eligible days" }
            let unit = bucket.eligibleCount == 1 ? "day" : "days"
            return "\(weekday), \(rate.formatted(.percent.precision(.fractionLength(0)))), \(bucket.achievedCount) of \(bucket.eligibleCount) eligible \(unit)"
        case .activityDistribution:
            let unit = bucket.activityCount == 1 ? "activity" : "activities"
            return "\(weekday), \(bucket.activityCount) \(unit)"
        }
    }
}

private struct ActivityHeatmap: View {
    let activity: [HabitLocalDay: Int]

    private var days: [HabitLocalDay] {
        let end = HabitLocalDay(date: Date())
        return (-364...0).compactMap { end.adding(days: $0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7),
                spacing: 3
            ) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill((activity[day, default: 0] > 0 ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("\(day.description): \(activity[day, default: 0])")
                }
            }
        }
        .frame(height: 88)
    }
}

private struct PeriodActivityGrid: View {
    let evaluation: HabitPeriodEvaluation
    let activity: [HabitLocalDay: Int]

    private var days: [HabitLocalDay] {
        var result: [HabitLocalDay] = []
        var day: HabitLocalDay? = evaluation.start
        while let current = day, current <= evaluation.end {
            result.append(current)
            day = current.adding(days: 1)
        }
        return result
    }

    var body: some View {
        if evaluation.period == .trackingOnly {
            Text("Activity is recorded without a goal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: evaluation.period == .month ? 7 : days.count),
                spacing: 4
            ) {
                ForEach(days) { day in
                    VStack(spacing: 2) {
                        Text(dayLabel(day))
                        Circle()
                            .fill(activity[day, default: 0] > 0 ? Color.accentColor : Color.secondary.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                    .font(.caption2)
                    .accessibilityLabel("\(day.description): \(activity[day, default: 0])")
                }
            }
            .accessibilityLabel("Current period activity")
        }
    }

    private func dayLabel(_ day: HabitLocalDay) -> String {
        switch evaluation.period {
        case .day: return "Today"
        case .week:
            guard let date = day.date() else { return day.description }
            return WeeklyReviewCalendarPolicy.calendar().veryShortWeekdaySymbols[
                WeeklyReviewCalendarPolicy.calendar().component(.weekday, from: date) - 1
            ]
        case .month: return "\(day.day)"
        case .trackingOnly: return ""
        }
    }
}

struct HabitCheckInUndoBar: View {
    let undo: () -> Void

    var body: some View {
        HStack {
            Label("Checked in", systemImage: "checkmark.circle.fill")
            Spacer()
            Button("Undo", action: undo)
                .accessibilityIdentifier("habit-check-in-undo")
        }
        .padding()
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }
}

extension HabitRecordingMode {
    var localizedName: String {
        switch self {
        case .oncePerDay:
            String(localized: "Once per day")
        case .multiplePerDay:
            String(localized: "Multiple times per day")
        }
    }
}

extension HabitStatus {
    var localizedName: String {
        switch self {
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .completed: String(localized: "Completed")
        case .archived: String(localized: "Archived")
        }
    }
}

private struct HabitLogRow: View {
    let log: HabitLog
    let hasInsight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    log.isCompleted
                        ? String(localized: "Completed")
                        : String(localized: "Not Completed"),
                    systemImage: log.isCompleted ? "checkmark.circle.fill" : "circle"
                )
                Spacer()
                Text(log.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let quantity = log.quantity {
                Text("\(quantity.formatted())\(log.unit.map { " \($0)" } ?? "")")
                    .font(.subheadline)
            }
            if let result = log.result {
                Text(result)
                    .font(.subheadline)
            }
            if hasInsight {
                Label("Linked Entry", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailedHabitCheckInView: View {
    let save: (HabitLogDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var occurredAt = Date()
    @State private var isCompleted = true
    @State private var quantity = ""
    @State private var unit = ""
    @State private var result = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fact") {
                    Toggle("Completed", isOn: $isCompleted)
                    DatePicker("Occurred", selection: $occurredAt)
                    TextField("Quantity (optional)", text: $quantity)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("habit-log-quantity")
                    TextField("Unit (optional)", text: $unit)
                    TextField("Simple result (optional)", text: $result)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Habit Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCheckIn() }
                        .accessibilityIdentifier("habit-log-save")
                }
            }
        }
    }

    private func saveCheckIn() {
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedQuantity: Double?
        if trimmedQuantity.isEmpty {
            parsedQuantity = nil
        } else if let value = Double(trimmedQuantity) {
            parsedQuantity = value
        } else {
            errorMessage = String(localized: "Quantity must be a number.")
            return
        }

        do {
            try save(HabitLogDraft(
                occurredAt: occurredAt,
                isCompleted: isCompleted,
                quantity: parsedQuantity,
                unit: unit,
                result: result
            ))
            dismiss()
        } catch {
            errorMessage = String(localized: "The check-in was not saved.")
        }
    }
}
