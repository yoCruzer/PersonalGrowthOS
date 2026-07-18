import SwiftData
import SwiftUI

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
                LabeledContent {
                    Text("\(habits.count)")
                } label: {
                    Label("Habits", systemImage: "repeat")
                }
            }
            .accessibilityIdentifier("growth-habits")
            NavigationLink {
                GoalsView(
                    mediaStore: mediaStore,
                    thumbnailStore: thumbnailStore
                )
            } label: {
                LabeledContent {
                    Text("\(goals.count)")
                } label: {
                    Label("Goals and Flags", systemImage: "target")
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

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Habit.normalizedName, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]) private var habits: [Habit]
    @State private var newHabitName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("New Habit") {
                HStack {
                    TextField("Habit name", text: $newHabitName)
                        .accessibilityIdentifier("new-habit-name")
                    Button("Add") { createHabit() }
                        .disabled(newHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("add-habit")
                }
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
                            LabeledContent(habit.name, value: habit.statusRawValue.capitalized)
                        }
                        .accessibilityIdentifier("habit-\(habit.normalizedName)")
                    }
                }
            }
        }
        .navigationTitle("Habits")
        .alert("Could Not Update Habits", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func createHabit() {
        do {
            _ = try HabitService(context: modelContext).create(name: newHabitName)
            newHabitName = ""
        } catch {
            errorMessage = "The Habit was not created."
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
    @Query private var entries: [Entry]
    @State private var isAddingInsight = false
    @State private var isLoggingDetails = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var logs: [HabitLog] {
        allLogs.filter { $0.habitID == habit.id }
    }

    private var entriesByID: [UUID: Entry] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Habit", value: habit.statusRawValue.capitalized)
            }
            if habit.status == .active {
                Section {
                    Button {
                        simpleCheckIn()
                    } label: {
                        Label("Check In", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("habit-check-in")

                    Button {
                        isLoggingDetails = true
                    } label: {
                        Label("Log Details", systemImage: "list.bullet.clipboard")
                    }
                    .accessibilityIdentifier("habit-log-details")

                    Button {
                        isAddingInsight = true
                    } label: {
                        Label("Check In with Insight", systemImage: "square.and.pencil")
                    }
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
                _ = try HabitCheckInService(
                    context: modelContext,
                    mediaStore: mediaStore
                ).checkIn(habit, draft: draft)
            }
        }
        .sheet(isPresented: $isAddingInsight) {
            QuickCaptureView(
                mediaStore: mediaStore,
                navigationTitle: "Habit Insight",
                saveDraft: { draft in
                    try HabitCheckInService(
                        context: modelContext,
                        mediaStore: mediaStore
                    ).checkInWithInsight(habit, entryDraft: draft).entry
                },
                didSave: { _ in isAddingInsight = false }
            )
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
            Text(errorMessage ?? "Please try again.")
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
            _ = try HabitCheckInService(
                context: modelContext,
                mediaStore: mediaStore
            ).checkIn(habit)
        } catch {
            errorMessage = "The check-in was not saved."
        }
    }

    private func transition(to status: HabitStatus) {
        do {
            try HabitService(context: modelContext).transition(habit, to: status)
        } catch {
            errorMessage = "The Habit status was not changed."
        }
    }

    private func permanentlyDelete() {
        do {
            try HabitService(context: modelContext).permanentlyDelete(habit)
            dismiss()
        } catch {
            errorMessage = "The Habit was not deleted. Its check-ins and links are unchanged."
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
                    log.isCompleted ? "Completed" : "Not Completed",
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
            errorMessage = "Quantity must be a number."
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
            errorMessage = "The check-in was not saved."
        }
    }
}
