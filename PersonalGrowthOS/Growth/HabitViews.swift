import SwiftData
import SwiftUI
import UIKit

struct GrowthView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query private var habits: [Habit]
    @Query private var goals: [Goal]

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
        }
        .navigationTitle("Growth")
        .accessibilityIdentifier("growth-view")
    }
}

struct HabitsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @State private var isCreatingHabit = false

    var body: some View {
        List {
            Section {
                Button {
                    isCreatingHabit = true
                } label: {
                    Label("Add Habit", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("add-habit")
            } footer: {
                Text("Use a specific, actionable name. You can change it later without losing check-ins.")
            }
            Section("Habits") {
                if habits.isEmpty {
                    Text("Add a habit you want to practice. Pauses and restarts are part of growth.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(habits) { habit in
                        NavigationLink {
                            HabitDetailView(
                                habit: habit,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            LabeledContent(
                                habit.name,
                                value: habit.status.localizedName
                            )
                        }
                        .accessibilityIdentifier("habit-\(habit.normalizedName)")
                    }
                }
            }
        }
        .navigationTitle("Habits")
        .sheet(isPresented: $isCreatingHabit) {
            HabitEditorView(
                habit: nil,
                settings: HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil),
                didSave: { isCreatingHabit = false }
            )
        }
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
    @Query private var configurations: [HabitConfiguration]
    @Query private var entries: [Entry]
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
        HabitSettingsResolver.settings(for: habit.id, configurations: configurations)
    }

    private var checkedInToday: Bool {
        logs.contains { Calendar.current.isDateInToday($0.occurredAt) }
    }

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Status", value: habit.status.localizedName)
                LabeledContent("Recording Mode", value: settings.recordingMode.localizedName)
                if let target = settings.dailyTargetCount {
                    LabeledContent("Daily Target", value: "\(target)")
                }
            }
            if habit.status == .active {
                Section {
                    Button {
                        simpleCheckIn()
                    } label: {
                        Label(
                            settings.recordingMode == .oncePerDay && checkedInToday
                                ? "Completed Today"
                                : "Check In",
                            systemImage: settings.recordingMode == .oncePerDay && checkedInToday
                                ? "checkmark.circle.fill"
                                : "checkmark.circle"
                        )
                    }
                    .disabled(isCoolingDown || (settings.recordingMode == .oncePerDay && checkedInToday))
                    .accessibilityIdentifier("habit-check-in")

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
                } header: {
                    Text("Check In")
                } footer: {
                    Text("A simple check-in saves only a structured fact. Text and photos are saved in a linked Entry.")
                }
            }
            Section("History") {
                if logs.isEmpty {
                    Text("No check-ins yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        if let linkedEntryID = log.linkedEntryID,
                           let entry = entriesByID[linkedEntryID] {
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
                didSave: { isEditing = false }
            )
        }
        .safeAreaInset(edge: .bottom) {
            if let recentCheckIn {
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

    private func registerSuccessfulCheckIn(_ log: HabitLog) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        transientMessage = nil
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

private struct HabitEditorView: View {
    let habit: Habit?
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var recordingMode: HabitRecordingMode
    @State private var dailyTarget = ""
    @State private var errorMessage: String?

    init(
        habit: Habit?,
        settings: HabitSettings,
        didSave: @escaping () -> Void
    ) {
        self.habit = habit
        self.didSave = didSave
        _name = State(initialValue: habit?.name ?? "")
        _recordingMode = State(initialValue: settings.recordingMode)
        _dailyTarget = State(initialValue: settings.dailyTargetCount.map(String.init) ?? "")
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

                    if recordingMode == .multiplePerDay {
                        TextField("Daily target (optional)", text: $dailyTarget)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("habit-daily-target")
                    }
                } header: {
                    Text("Check-In Frequency")
                } footer: {
                    Text(recordingMode == .oncePerDay
                        ? String(localized: "Choose this when completing the Habit once is enough for the day.")
                        : String(localized: "Choose this for Habits you may record several times each day. The target is optional."))
                }

                if habit != nil {
                    Section {
                        Text("Changing the name does not affect history. If the Habit itself has changed, consider archiving it and creating a new one.")
                            .foregroundStyle(.secondary)
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
        if recordingMode == .multiplePerDay, !trimmedTarget.isEmpty {
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
            if let habit {
                try service.update(
                    habit,
                    name: name,
                    recordingMode: recordingMode,
                    dailyTargetCount: target
                )
            } else {
                _ = try service.create(
                    name: name,
                    recordingMode: recordingMode,
                    dailyTargetCount: target
                )
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
}

struct RecentHabitCheckIn: Equatable {
    let habitID: UUID
    let logID: UUID
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
