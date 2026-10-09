import SwiftData
import SwiftUI
import UIKit

extension TodoFilter {
    var label: String {
        switch self {
        case .today: return String(localized: "Today")
        case .upcoming: return String(localized: "Upcoming")
        case .all: return String(localized: "All Todos")
        case .completed: return String(localized: "Completed")
        case .canceled: return String(localized: "Canceled")
        case .completedToday: return String(localized: "Completed Today")
        case .completedWeek: return String(localized: "Completed This Week")
        case .open: return String(localized: "Open Todos")
        case .overdue: return String(localized: "Past Hard Deadline")
        }
    }
}

struct TodoHubView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.modelContext) private var context
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Query private var tasks: [TodoTask]
    @Query(sort: \TodoList.createdAt) private var lists: [TodoList]
    @State private var filter: TodoFilter
    @State private var statusFilter: TodoStatusFilter = .open
    @State private var listID: UUID?
    @State private var unclassifiedOnly = false
    @State private var query = ""
    @State private var adding = false
    @State private var managingLists = false
    @State private var message: String?
    @State private var undoID: UUID?
    @State private var referenceDate = Date()
    @Environment(\.scenePhase) private var scenePhase

    init(mediaStore: MediaStore, thumbnailStore: ThumbnailStore, initialFilter: TodoFilter = .today) {
        self.mediaStore = mediaStore; self.thumbnailStore = thumbnailStore
        _filter = State(initialValue: initialFilter)
    }
    private var visible: [TodoTask] {
        TodoQuery.sorted(tasks.filter {
            TodoQuery.matches($0, filter: filter, now: referenceDate, status: statusFilter,
                              listID: listID, unclassifiedOnly: unclassifiedOnly, keyword: query)
        })
    }

    var body: some View {
        List {
            Section("Task Summary") {
                statistic(.completedToday, id: "todo-stat-today")
                statistic(.completedWeek, id: "todo-stat-week")
                statistic(.open, id: "todo-stat-open")
                statistic(.overdue, id: "todo-stat-overdue")
            }
            Section {
                Picker("View", selection: $filter) {
                    ForEach([TodoFilter.today, .upcoming, .all], id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                    if ![TodoFilter.today, .upcoming, .all].contains(filter) {
                        Text(filter.label).tag(filter)
                    }
                }.accessibilityIdentifier("todo-filter")
                if filter == .all {
                    Picker("Task Status", selection: $statusFilter) {
                        ForEach(TodoStatusFilter.allCases, id: \.self) { value in Text(value.label).tag(value) }
                    }.pickerStyle(.menu).accessibilityIdentifier("todo-status-filter")
                }
                Menu {
                    Button("All Lists") { listID = nil; unclassifiedOnly = false }
                    Button("Unclassified") { listID = nil; unclassifiedOnly = true }
                    ForEach(lists) { list in Button(list.name) { listID = list.id; unclassifiedOnly = false } }
                    Button("Manage Lists") { managingLists = true }
                } label: {
                    LabeledContent("List", value: unclassifiedOnly ? String(localized: "Unclassified") : lists.first { $0.id == listID }?.name ?? String(localized: "All Lists"))
                }.accessibilityIdentifier("todo-list-filter")
            }
            Section(filter == .all ? "\(filter.label) · \(statusFilter.label)" : filter.label) {
                if visible.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(query.isEmpty ? String(localized: "No tasks in this view") : String(localized: "No matching tasks"))
                        if filter == .today || filter == .upcoming {
                            Text("Undated tasks are in All Todos. Add a planned day to see them in Today or Upcoming.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if filter == .all {
                            Text("Change the status, list or search to see other tasks.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Add Todo") { adding = true }.accessibilityIdentifier("todo-empty-add")
                    }
                }
                ForEach(visible) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            change(task)
                        } label: {
                            Image(systemName: task.state == .completed ? "checkmark.circle.fill" : task.state == .canceled ? "arrow.uturn.backward.circle" : "circle")
                                .font(.title2).frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(task.state == .open ? String(localized: "Complete Todo") : String(localized: "Reopen Todo"))
                        .accessibilityIdentifier("todo-toggle-\(task.id.uuidString)")
                        NavigationLink {
                            TodoDetailView(taskID: task.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
                        } label: { TodoTaskRow(task: task, now: referenceDate) }
                    }
                }
            }
            if let undoID {
                Button("Undo Completion") { perform { try TodoTaskService(context: context).transition(id: undoID, to: .open); self.undoID = nil } }
                    .accessibilityIdentifier("todo-undo")
            }
        }
        .navigationTitle("Todos")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Task title or notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Todo").accessibilityIdentifier("todo-add")
            }
        }
        .sheet(isPresented: $adding) { TodoEditorView { _ in adding = false } }
        .sheet(isPresented: $managingLists) { TodoListsView() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in referenceDate = Date() }
        .onChange(of: scenePhase) { _, value in if value == .active { referenceDate = Date() } }
        .onChange(of: filter) { _, value in if value == .all { statusFilter = .open } }
        .onChange(of: lists.map(\.id)) { _, ids in if let listID, !ids.contains(listID) { self.listID = nil } }
        .alert("Todo Update", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func statistic(_ kind: TodoFilter, id: String) -> some View {
        let count = tasks.filter { TodoQuery.matches($0, filter: kind, now: referenceDate) }.count
        return NavigationLink {
            TodoHubView(mediaStore: mediaStore, thumbnailStore: thumbnailStore, initialFilter: kind)
        } label: { LabeledContent(kind.label, value: String(count)) }
        .accessibilityIdentifier(id)
        .accessibilityValue(String(count))
    }
    private func change(_ task: TodoTask) {
        let wasOpen = task.state == .open
        perform { try TodoTaskService(context: context).transition(id: task.id, to: wasOpen ? .completed : .open)
            undoID = wasOpen ? task.id : nil }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); Task { await reminders.reconcile(context: context) } }
        catch { message = error.localizedDescription }
    }
}

struct TodoTaskRow: View {
    let task: TodoTask
    var now = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title).font(.body).fixedSize(horizontal: false, vertical: true)
            if task.isImportant { Label("Important", systemImage: "star.fill").font(.caption) }
            if task.state == .completed { Label("Completed", systemImage: "checkmark").font(.caption) }
            if task.state == .canceled { Label("Canceled", systemImage: "xmark").font(.caption) }
            if let day = task.plannedDay {
                Label { Text("Planned: \(day)") } icon: { Image(systemName: "calendar") }.font(.caption)
                if task.state == .open && day < TodoDay(date: now).description { Text("Plan not handled").font(.caption).foregroundStyle(.secondary) }
            }
            if let day = task.deadlineDay {
                Label { Text("Hard deadline: \(day)") } icon: { Image(systemName: "flag") }.font(.caption)
                if TodoQuery.matches(task, filter: .overdue, now: now) { Label("Past Hard Deadline", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            if task.seriesID != nil { Label("Repeating occurrence", systemImage: "repeat").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("todo-row-\(task.id.uuidString)")
    }
}

struct TodoEditorView: View {
    var task: TodoTask? = nil
    var sourceEntry: Entry? = nil
    let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Query(sort: \TodoList.createdAt) private var lists: [TodoList]
    @State private var draft = TodoDraft()
    @State private var submissionID = UUID()
    @State private var loaded = false
    @State private var futureSeries = false
    @State private var error: String?
    @State private var savedNotice = false
    private enum Field: Hashable { case title, notes }
    @FocusState private var focusedField: Field?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $draft.title, axis: .vertical)
                        .focused($focusedField, equals: .title).accessibilityIdentifier("todo-title")
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .focused($focusedField, equals: .notes).accessibilityIdentifier("todo-notes")
                    Toggle("Important", isOn: $draft.isImportant).accessibilityIdentifier("todo-important")
                    Picker("List", selection: $draft.listID) {
                        Text("Unclassified").tag(nil as UUID?)
                        ForEach(lists) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("todo-editor-list")
                }
                Section("Schedule") {
                    Toggle("Planned Day", isOn: dayEnabled(\.plannedDay)).accessibilityIdentifier("todo-planned-toggle")
                    if draft.plannedDay != nil { DatePicker("Planned Day", selection: dayBinding(\.plannedDay), displayedComponents: .date).accessibilityIdentifier("todo-planned-day") }
                    Toggle("Hard Deadline", isOn: dayEnabled(\.deadlineDay)).accessibilityIdentifier("todo-deadline-toggle")
                    if draft.deadlineDay != nil { DatePicker("Hard Deadline", selection: dayBinding(\.deadlineDay), displayedComponents: .date) }
                    Toggle("Reminder", isOn: Binding(get: { draft.remindAt != nil }, set: { draft.remindAt = $0 ? Date().addingTimeInterval(3600) : nil }))
                        .accessibilityIdentifier("todo-reminder-toggle")
                    if draft.remindAt != nil {
                        DatePicker("Reminder Time", selection: Binding(get: { draft.remindAt ?? Date() }, set: { draft.remindAt = $0 }))
                        Text("Permission is requested when you save a reminder. Delivery depends on iOS settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Repeat") {
                    if task?.seriesID == nil && (task == nil || task?.state == .open) {
                        Picker("Repeat", selection: $draft.frequency) {
                            Text("Does not repeat").tag(nil as TodoFrequency?)
                            ForEach(TodoFrequency.allCases, id: \.self) { frequency in Text(frequency.label).tag(Optional(frequency)) }
                        }.accessibilityIdentifier("todo-repeat")
                    } else if task?.seriesID != nil {
                        Toggle("Apply title, notes, list and reminder time to future occurrences", isOn: $futureSeries).accessibilityIdentifier("todo-edit-future")
                        Text("Also updates importance and all generated open successors, replacing their individual template edits. Completed and canceled successors keep their history.").font(.caption)
                        Text("Dates change only this occurrence. The original repeat rule stays fixed.").font(.caption)
                    } else {
                        Text("Does not repeat")
                        Text("Reopen this task before converting it to a repeating series.").font(.caption)
                    }
                    if draft.frequency != nil && draft.plannedDay == nil && draft.deadlineDay == nil {
                        Text("Choose a planned day or hard deadline for the first occurrence before saving.").foregroundStyle(.orange).accessibilityIdentifier("todo-repeat-needs-day")
                    }
                    Text("Repeating reminders keep their calendar-day offset from the fixed anchor, using the planned day first, otherwise the deadline. The supported range is 366 days before or after.").font(.caption).foregroundStyle(.secondary)
                    Text("Fixed calendar repeats use the original anchor. Missed dates are skipped; completion creates the first future occurrence.").font(.caption).foregroundStyle(.secondary)
                }
                if savedNotice { Label("Saved. Ready for another todo.", systemImage: "checkmark").accessibilityIdentifier("todo-saved-another") }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let error { Text(error).foregroundStyle(.red).padding(.horizontal).accessibilityIdentifier("todo-editor-error") }
                    if task == nil {
                        Button("Save and Add Another") { save(another: true) }
                            .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal)
                            .background(.bar).accessibilityIdentifier("todo-save-another")
                    }
                }.background(.bar)
            }
            .safeAreaInset(edge: .top) { TodoReminderFeedbackView() }
            .navigationTitle(task == nil ? String(localized: "Add Todo") : String(localized: "Edit Todo"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if focusedField != nil {
                        Button { focusedField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                            .accessibilityLabel("Done").accessibilityIdentifier("todo-dismiss-keyboard")
                    }
                    Button("Save") { save(another: false) }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo-save")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
            }
            .task {
                guard !loaded else { return }; loaded = true
                if let task { draft = TodoDraft(task) }
                else if let sourceEntry {
                    draft.title = sourceEntry.title ?? sourceEntry.body?.components(separatedBy: .newlines).first ?? ""
                    draft.notes = sourceEntry.body ?? ""
                }
                focusedField = .title
            }
            .environment(\.calendar, WeeklyReviewCalendarPolicy.calendar())
        }
    }
    private func dayEnabled(_ path: WritableKeyPath<TodoDraft, String?>) -> Binding<Bool> {
        Binding(get: { draft[keyPath: path] != nil }, set: { draft[keyPath: path] = $0 ? TodoDay(date: Date()).description : nil })
    }
    private func dayBinding(_ path: WritableKeyPath<TodoDraft, String?>) -> Binding<Date> {
        Binding(get: { draft[keyPath: path].flatMap(TodoDay.init)?.date() ?? Date() }, set: { draft[keyPath: path] = TodoDay(date: $0).description })
    }
    private func save(another: Bool) {
        do {
            if let reminder = draft.remindAt, reminder <= Date(), task?.remindAt != reminder { throw TodoFailure.invalidReminder }
            let service = TodoTaskService(context: context)
            let id: UUID
            if let task { try service.edit(id: task.id, draft: draft, futureSeries: futureSeries); id = task.id }
            else { id = try service.create(draft, sourceEntryID: sourceEntry?.id, id: submissionID).id }
            let saved = try service.task(id: id)
            reminders.reportSavedTask(saved)
            let ask = draft.remindAt != nil
            Task { await reminders.reconcile(context: context, requestPermission: ask) }
            error = nil
            if another { let selectedList = draft.listID; draft = TodoDraft(listID: selectedList); submissionID = UUID(); savedNotice = true; focusedField = .title }
            else { focusedField = nil; onSaved(id) }
        } catch { self.error = error.localizedDescription }
    }
}

extension TodoFrequency {
    var label: String {
        switch self {
        case .daily: return String(localized: "Every Day")
        case .weekly: return String(localized: "Every Week")
        case .monthly: return String(localized: "Every Month")
        case .yearly: return String(localized: "Every Year")
        }
    }
}

struct TodoDetailView: View {
    let taskID: UUID
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Query private var tasks: [TodoTask]
    @Query private var events: [TodoTaskEvent]
    @Query private var sources: [TodoTaskSource]
    @Query private var entries: [Entry]
    @Query private var series: [TodoSeries]
    @State private var editing = false
    @State private var deleting = false
    @State private var stopping = false
    @State private var error: String?
    private var task: TodoTask? { tasks.first { $0.id == taskID } }
    var body: some View {
        Group {
            if let task {
                List {
                    Section { TodoTaskRow(task: task); if !task.notes.isEmpty { Text(task.notes).textSelection(.enabled) } }
                    Section {
                        Button(task.state == .open ? String(localized: "Complete Todo") : String(localized: "Reopen Todo")) {
                            perform { try TodoTaskService(context: context).transition(id: taskID, to: task.state == .open ? .completed : .open) }
                        }.accessibilityIdentifier("todo-detail-toggle")
                        if task.state != .canceled {
                            Button("Cancel Todo") { perform { try TodoTaskService(context: context).transition(id: taskID, to: .canceled) } }
                                .accessibilityIdentifier("todo-cancel")
                        }
                        Button("Edit Todo") { editing = true }.accessibilityIdentifier("todo-edit")
                    }
                    if task.seriesID != nil {
                        Section("Repeat") {
                            if let rule = series.first(where: { $0.id == task.seriesID }) {
                                Text(rule.isStopped ? String(localized: "Series stopped") : String(localized: "Fixed calendar series"))
                                Text(verbatim: "\(TodoFrequency(rawValue: rule.frequencyRawValue)?.label ?? "") · \(rule.anchorDay)")
                                if task.state == .open && !rule.isStopped {
                                    Button("Skip This Occurrence") { perform { try TodoTaskService(context: context).transition(id: taskID, to: .canceled, skip: true) } }
                                        .accessibilityIdentifier("todo-skip")
                                }
                                if !rule.isStopped { Button("Stop Entire Series", role: .destructive) { stopping = true }.accessibilityIdentifier("todo-stop-series") }
                            }
                            ForEach(TodoQuery.sorted(tasks.filter { $0.seriesID == task.seriesID && $0.id != taskID })) { sibling in
                                NavigationLink { TodoDetailView(taskID: sibling.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: { TodoTaskRow(task: sibling) }
                            }
                        }
                    }
                    if task.remindAt != nil {
                        Section("Reminder") {
                            if let date = task.remindAt { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                            Text(reminders.status(for: task).label).accessibilityIdentifier("todo-reminder-status")
                            Button("Retry Reminder") { Task { await reminders.reconcile(context: context, requestPermission: true) } }
                            if reminders.status(for: task) == .denied {
                                Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            }
                        }
                    }
                    if let source = sources.first(where: { $0.taskID == taskID }), let entry = entries.first(where: { $0.id == source.entryID }) {
                        Section("Source Entry") {
                            NavigationLink { EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: {
                                Label(entry.title ?? entry.body ?? String(localized: "Entry"), systemImage: "doc.text")
                            }.accessibilityIdentifier("todo-source-entry")
                        }
                    }
                    Section("Task History") {
                        ForEach(events.filter { $0.taskID == taskID }.sorted { $0.sequence > $1.sequence }) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TodoEventKind(rawValue: event.kindRawValue)?.label ?? String(localized: "Unknown"))
                                Text(event.occurredAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                if let after = try? JSONDecoder().decode(TodoEventValue.self, from: event.afterValue) {
                                    if let planned = after.plannedDay { Text("Planned: \(planned)").font(.caption) }
                                    if let deadline = after.deadlineDay { Text("Hard deadline: \(deadline)").font(.caption) }
                                }
                            }
                        }
                    }
                    Section {
                        Button("Delete Todo Permanently", role: .destructive) { deleting = true }.accessibilityIdentifier("todo-delete")
                    }
                }
                .sheet(isPresented: $editing) { TodoEditorView(task: task) { _ in editing = false } }
            } else { ContentUnavailableView("Task unavailable", systemImage: "checklist") }
        }
        .navigationTitle("Todo")
        .alert("Delete Todo Permanently?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { perform { try TodoTaskService(context: context).delete(id: taskID); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the task and its events. A repeating series will stop. The source entry is kept.") }
        .alert("Stop Entire Series?", isPresented: $stopping) {
            Button("Stop Entire Series", role: .destructive) { perform { try TodoTaskService(context: context).stopSeries(taskID: taskID) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The current occurrence and history stay. No further occurrences will be created.") }
        .alert("Todo Update", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); Task { await reminders.reconcile(context: context) } }
        catch { self.error = error.localizedDescription }
    }
}

extension TodoEventKind {
    var label: String {
        switch self {
        case .created: return String(localized: "Todo created")
        case .edited: return String(localized: "Todo edited or rescheduled")
        case .completed: return String(localized: "Todo completed")
        case .reopened: return String(localized: "Todo reopened")
        case .canceled: return String(localized: "Todo canceled")
        case .skipped: return String(localized: "Occurrence skipped")
        case .successorWithdrawn: return String(localized: "Successor withdrawn after undo")
        case .seriesStopped: return String(localized: "Series stopped")
        case .convertedToSeries: return String(localized: "Converted to repeating series")
        }
    }
}

struct TodoListsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoList.createdAt) private var lists: [TodoList]
    @State private var name = ""
    @State private var renaming: TodoList?
    @State private var deleting: TodoList?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("New List") {
                    TextField("List name", text: $name).accessibilityIdentifier("todo-list-name")
                    Button("Create List") { perform { _ = try TodoTaskService(context: context).createList(name: name); name = "" } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("todo-list-create")
                }
                Section("Lists") {
                    ForEach(lists) { list in
                        VStack(alignment: .leading) {
                            Text(list.name)
                            HStack {
                                Button("Rename") { renaming = list }.accessibilityIdentifier("todo-list-rename-\(list.id)")
                                Spacer()
                                Button("Delete", role: .destructive) { deleting = list }.accessibilityIdentifier("todo-list-delete-\(list.id)")
                            }.buttonStyle(.borderless).frame(minHeight: 44)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Manage Lists")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $renaming) { list in TodoListRenameView(listID: list.id, name: list.name) }
            .alert("Delete List?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { list in
                Button("Delete", role: .destructive) { perform { try TodoTaskService(context: context).deleteList(id: list.id); deleting = nil } }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { _ in Text("Tasks stay and become unclassified.") }
        }
    }
    private func perform(_ operation: () throws -> Void) { do { try operation(); error = nil } catch { self.error = error.localizedDescription } }
}

private struct TodoListRenameView: View {
    let listID: UUID
    @State var name: String
    @State private var error: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("List name", text: $name).accessibilityIdentifier("todo-list-rename-name")
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Rename List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try TodoTaskService(context: context).renameList(id: listID, name: name); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("todo-list-rename-save")
                }
            }
        }
    }
}


/// Lives both in the editor (continuous input) and shell (after sheet dismissal).
struct TodoReminderFeedbackView: View {
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    var body: some View {
        if let id = reminders.savedTaskID, let task = tasks.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Todo saved").font(.headline)
                Text(reminders.status(for: task).label).accessibilityIdentifier("todo-saved-reminder-status")
                HStack {
                    if reminders.status(for: task) == .denied {
                        Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else if [.permissionRequired, .failed, .queueFull].contains(reminders.status(for: task)) {
                        Button("Retry Reminder") { Task { await reminders.reconcile(context: context, requestPermission: true) } }
                    }
                    Spacer()
                    Button("Dismiss") { reminders.savedTaskID = nil }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("todo-reminder-feedback-dismiss")
                }.frame(minHeight: 44)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("todo-saved-reminder-feedback")
        }
    }
}


extension TodoStatusFilter {
    var label: String {
        switch self {
        case .open: return String(localized: "Incomplete")
        case .all: return String(localized: "All States")
        case .completed: return String(localized: "Completed")
        case .canceled: return String(localized: "Canceled")
        }
    }
}
