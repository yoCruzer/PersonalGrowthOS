import SwiftData
import SwiftUI

struct GoalsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Goal.normalizedTitle, order: .forward),
        SortDescriptor(\Goal.id, order: .forward)
    ]) private var goals: [Goal]
    @State private var title = ""
    @State private var kind: GoalKind = .standard
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("New Goal or Flag") {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("new-goal-title")
                Picker("Kind", selection: $kind) {
                    Text("Goal").tag(GoalKind.standard)
                    Text("Flag").tag(GoalKind.flag)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("new-goal-kind")
                Button("Add") { create() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("add-goal")
            }
            Section("Goals and Flags") {
                if goals.isEmpty {
                    Text("Goals can guide attention without becoming a daily task list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(
                                goal: goal,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            LabeledContent {
                                Text(goal.statusRawValue.capitalized)
                            } label: {
                                Label(
                                    goal.title,
                                    systemImage: goal.kind == .flag ? "flag" : "target"
                                )
                            }
                        }
                        .accessibilityIdentifier("goal-\(goal.normalizedTitle)")
                    }
                }
            }
        }
        .navigationTitle("Goals and Flags")
        .alert("Could Not Update Goals", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func create() {
        do {
            _ = try GoalService(context: modelContext).create(title: title, kind: kind)
            title = ""
            kind = .standard
        } catch {
            errorMessage = "The Goal or Flag was not created."
        }
    }
}

struct GoalDetailView: View {
    let goal: Goal
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var links: [ObjectLink]
    @Query private var habits: [Habit]
    @Query private var entries: [Entry]
    @Query(sort: [
        SortDescriptor(\GoalLifecycleEvent.occurredAt, order: .reverse),
        SortDescriptor(\GoalLifecycleEvent.id, order: .forward)
    ]) private var allEvents: [GoalLifecycleEvent]
    @State private var isManagingHabits = false
    @State private var isManagingEntries = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var events: [GoalLifecycleEvent] {
        allEvents.filter { $0.goalID == goal.id }
    }

    private var supportingHabits: [Habit] {
        let ids = Set(links.filter {
            $0.kind == .habitSupportsGoal && $0.targetID == goal.id
        }.map(\.sourceID))
        return habits.filter { ids.contains($0.id) }
    }

    private var relatedEntries: [Entry] {
        let ids = Set(links.filter {
            $0.kind == .entryRelatesGoal && $0.targetID == goal.id
        }.map(\.sourceID))
        return entries.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            Section("Goal") {
                LabeledContent("Kind", value: goal.kind == .flag ? "Flag" : "Goal")
                LabeledContent("Status", value: goal.statusRawValue.capitalized)
                if let completedAt = goal.completedAt {
                    LabeledContent("Completed", value: completedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("Relationships") {
                ForEach(supportingHabits) { habit in
                    Label("\(habit.name) supports this Goal", systemImage: "repeat")
                }
                ForEach(relatedEntries) { entry in
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        Label(entry.title ?? entry.body ?? "Entry", systemImage: "doc.text")
                    }
                }
                Button("Manage Supporting Habits") { isManagingHabits = true }
                    .accessibilityIdentifier("goal-manage-habits")
                Button("Manage Related Entries") { isManagingEntries = true }
                    .accessibilityIdentifier("goal-manage-entries")
            }
            Section("Lifecycle History") {
                ForEach(events) { event in
                    LabeledContent(
                        event.kindRawValue.capitalized,
                        value: event.occurredAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
        }
        .navigationTitle(goal.title)
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
            .accessibilityIdentifier("goal-actions")
        }
        .sheet(isPresented: $isManagingHabits) {
            GoalHabitEditor(goal: goal)
        }
        .sheet(isPresented: $isManagingEntries) {
            GoalEntryEditor(goal: goal)
        }
        .alert("Delete this Goal permanently?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { permanentlyDelete() }
        } message: {
            Text("Its lifecycle history and relationships will be deleted. Entries and Habits will remain.")
        }
        .alert("Could Not Update Goal", isPresented: Binding(
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
        switch goal.status {
        case .active:
            Button("Pause", systemImage: "pause") { transition(to: .paused) }
            Button("Complete", systemImage: "checkmark") { transition(to: .completed) }
            Button("Abandon", systemImage: "xmark") { transition(to: .abandoned) }
            Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
        case .paused:
            Button("Resume", systemImage: "play") { transition(to: .active) }
            Button("Complete", systemImage: "checkmark") { transition(to: .completed) }
            Button("Abandon", systemImage: "xmark") { transition(to: .abandoned) }
            Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
        case .completed, .abandoned, .archived:
            Button("Reactivate", systemImage: "arrow.clockwise") { transition(to: .active) }
            if goal.status != .archived {
                Button("Archive", systemImage: "archivebox") { transition(to: .archived) }
            }
        }
    }

    private func transition(to status: GoalStatus) {
        do {
            try GoalService(context: modelContext).transition(goal, to: status)
        } catch {
            errorMessage = "The Goal status was not changed."
        }
    }

    private func permanentlyDelete() {
        do {
            try GoalService(context: modelContext).permanentlyDelete(goal)
            dismiss()
        } catch {
            errorMessage = "The Goal was not deleted. Its history and relationships are unchanged."
        }
    }
}

struct EntryRelationshipsEditor: View {
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Habit.normalizedName)]) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Goal.normalizedTitle)]) private var goals: [Goal]
    @Query private var links: [ObjectLink]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Habits") {
                    ForEach(habits) { habit in
                        relationButton(habit.name, linked: isLinked(to: habit)) {
                            try CoreLinkService(context: modelContext).setEntry(
                                entry, relatesTo: habit, linked: !isLinked(to: habit)
                            )
                        }
                    }
                }
                Section("Goals and Flags") {
                    ForEach(goals) { goal in
                        relationButton(goal.title, linked: isLinked(to: goal)) {
                            try CoreLinkService(context: modelContext).setEntry(
                                entry, relatesTo: goal, linked: !isLinked(to: goal)
                            )
                        }
                    }
                }
            }
            .navigationTitle("Entry Relationships")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Could Not Update Relationships", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func relationButton(_ title: String, linked: Bool, action: @escaping () throws -> Void) -> some View {
        Button {
            do { try action() } catch { errorMessage = "The relationship was not changed." }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if linked { Image(systemName: "checkmark") }
            }
        }
        .foregroundStyle(.primary)
    }

    private func isLinked(to habit: Habit) -> Bool {
        links.contains { $0.kind == .entryRelatesHabit && $0.sourceID == entry.id && $0.targetID == habit.id }
    }

    private func isLinked(to goal: Goal) -> Bool {
        links.contains { $0.kind == .entryRelatesGoal && $0.sourceID == entry.id && $0.targetID == goal.id }
    }
}

private struct GoalHabitEditor: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Habit.normalizedName)]) private var habits: [Habit]
    @Query private var links: [ObjectLink]
    @State private var errorMessage: String?

    var body: some View {
        relationList(title: "Supporting Habits", items: habits) { habit in
            let linked = isLinked(habit)
            return (habit.name, linked, {
                try CoreLinkService(context: modelContext).setHabit(habit, supports: goal, linked: !linked)
            })
        }
    }

    private func isLinked(_ habit: Habit) -> Bool {
        links.contains { $0.kind == .habitSupportsGoal && $0.sourceID == habit.id && $0.targetID == goal.id }
    }

    private func relationList<Item: Identifiable>(
        title: String,
        items: [Item],
        row: @escaping (Item) -> (String, Bool, () throws -> Void)
    ) -> some View {
        NavigationStack {
            List(items) { item in
                let value = row(item)
                Button {
                    do { try value.2() } catch { errorMessage = "The relationship was not changed." }
                } label: {
                    HStack { Text(value.0); Spacer(); if value.1 { Image(systemName: "checkmark") } }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(title)
            .toolbar { Button("Done") { dismiss() } }
            .alert("Could Not Update Relationships", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Please try again.") }
        }
    }
}

private struct GoalEntryEditor: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Entry.occurredAt, order: .reverse)]) private var entries: [Entry]
    @Query private var links: [ObjectLink]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                let linked = links.contains {
                    $0.kind == .entryRelatesGoal && $0.sourceID == entry.id && $0.targetID == goal.id
                }
                Button {
                    do {
                        try CoreLinkService(context: modelContext).setEntry(entry, relatesTo: goal, linked: !linked)
                    } catch { errorMessage = "The relationship was not changed." }
                } label: {
                    HStack {
                        Text(entry.title ?? entry.body ?? "Entry")
                        Spacer()
                        if linked { Image(systemName: "checkmark") }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Related Entries")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Could Not Update Relationships", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Please try again.") }
        }
    }
}
