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
    var importantDayID: UUID? = nil
    var importantDayOccurrence: ImportantCivilDay? = nil
    var importantDayOperation: ImportantDayAssociationOperation? = nil
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
    @State private var selectingList = false
    @State private var referenceDate=Date()
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
                    Button { focusedField = nil; selectingList = true } label: {
                        LabeledContent("List", value: lists.first { $0.id == draft.listID }?.name ?? String(localized: "Unclassified")).frame(maxWidth:.infinity,minHeight:44).contentShape(.rect)
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
                        Picker("Reminder method",selection:Binding(get:{draft.reminderChannel ?? .notification},set:{draft.reminderChannel=$0})) {
                            ForEach(TodoReminderChannel.allCases,id:\.self) {Text($0.label).tag($0)}
                        }.accessibilityIdentifier("todo-reminder-method")
                        if draft.reminderChannel == .alarm {Text("A stronger system alarm. Requires iOS 26 and alarm permission; stopping it does not complete the todo.").font(.caption)}
                        Text("Permission is requested when you save a reminder. Delivery depends on iOS settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Repeat") {
                    if importantDayID == nil && task?.seriesID == nil && (task == nil || task?.state == .open) {
                        Picker("Repeat", selection: $draft.frequency) {
                            Text("Does not repeat").tag(nil as TodoFrequency?)
                            ForEach(TodoFrequency.allCases, id: \.self) { frequency in Text(frequency.label).tag(Optional(frequency)) }
                        }.accessibilityIdentifier("todo-repeat")
                        if draft.frequency == .customWeekdays {TodoWeekdayPicker(selection:$draft.weekdays)}
                        if let frequency=draft.frequency {
                            Text(TodoRepeatDescription.summary(frequency:frequency,mask:try? TodoWeekdayRule.mask(draft.weekdays)))
                                .accessibilityIdentifier("todo-repeat-summary")
                            if frequency == .customWeekdays && draft.weekdays.isEmpty {
                                Text("Choose at least one weekday.").foregroundStyle(.orange)
                            } else if let anchor=draft.plannedDay ?? draft.deadlineDay,
                                      let next=try? TodoRecurrence.nextIndex(anchor:anchor,frequency:frequency,after:0,today:TodoDay(date:referenceDate),weekdaysMask:try? TodoWeekdayRule.mask(draft.weekdays)),
                                      let day=try? TodoRecurrence.day(anchor:anchor,frequency:frequency,index:next,weekdaysMask:try? TodoWeekdayRule.mask(draft.weekdays)) {
                                Text("Next occurrence: \(day.description)").font(.caption).accessibilityIdentifier("todo-next-occurrence")
                            }
                            Text("Weekday rules do not adjust for public holidays or make-up workdays. The current occurrence keeps its chosen date.").font(.caption)
                        }
                    } else if task?.seriesID != nil {
                        Toggle("Apply title, notes, list and reminder time to future occurrences", isOn: $futureSeries).accessibilityIdentifier("todo-edit-future")
                        Text("Also updates importance and all generated open successors, replacing their individual template edits. Completed and canceled successors keep their history.").font(.caption)
                        Text("Dates change only this occurrence. The original repeat rule stays fixed.").font(.caption)
                    } else {
                        Text("Does not repeat")
                        if importantDayID == nil { Text("Reopen this task before converting it to a repeating series.").font(.caption) }
                    }
                    if draft.frequency != nil && draft.plannedDay == nil && draft.deadlineDay == nil {
                        Text("Choose a planned day or hard deadline for the first occurrence before saving.").foregroundStyle(.orange).accessibilityIdentifier("todo-repeat-needs-day")
                    }
                    if importantDayID == nil {
                    Text("Missed dates are skipped. Completing this occurrence creates the next future one.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("How repeating reminders work") {
                        Text("For example, a reminder the evening before stays the evening before each occurrence.").font(.caption)
                        Text("Repeating reminders keep their calendar-day offset from the fixed anchor, using the planned day first, otherwise the deadline. The supported range is 366 days before or after.").font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let error { Text(error).foregroundStyle(.red).padding(.horizontal).accessibilityIdentifier("todo-editor-error") }
                    if savedNotice { Label("Saved. Ready for another todo.", systemImage: "checkmark").padding(.horizontal).accessibilityIdentifier("todo-saved-another") }
                    if task == nil {
                        Button("Save and Add Another") { save(another: true) }
                            .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.frequency == .customWeekdays && draft.weekdays.isEmpty))
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal)
                            .background(.bar).accessibilityIdentifier("todo-save-another")
                    }
                }.background(.bar)
            }
            .safeAreaInset(edge: .top) { TodoReminderFeedbackView() }
            .navigationTitle(task == nil ? String(localized: "Add Todo") : String(localized: "Edit Todo"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-PGOSUITesting"),ProcessInfo.processInfo.arguments.contains("-PGOSUsageTodoRouteTest") {
                    ToolbarItem(placement:.bottomBar) {
                        Button("Perform synthetic Todo open intent") {
                            Task {if #available(iOS 26.0, *) {_ = try? await OpenTodoAlarmIntent(taskID:"40000000-1111-4222-8333-444444444444").perform()}}
                        }.accessibilityIdentifier("todo-editor-test-open-intent")
                    }
                }
                #endif
                ToolbarItemGroup(placement: .confirmationAction) {
                    if focusedField != nil {
                        Button { focusedField = nil } label: { Image(systemName: "keyboard.chevron.compact.down").frame(minWidth:44,minHeight:44) }
                            .accessibilityLabel("Done").accessibilityIdentifier("todo-dismiss-keyboard")
                    }
                    Button("Save") { save(another: false) }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.frequency == .customWeekdays && draft.weekdays.isEmpty))
                        .accessibilityIdentifier("todo-save")
                }
            }
            .task {
                guard !loaded else { return }; loaded = true
                if let task {
                    do {draft=try TodoTaskService(context:context).draft(id:task.id)}
                    catch {self.error=error.localizedDescription}
                }
                else if let sourceEntry {
                    draft.title = sourceEntry.title ?? sourceEntry.body?.components(separatedBy: .newlines).first ?? ""
                    draft.notes = sourceEntry.body ?? ""
                }
                focusedField = .title
            }
            .onReceive(NotificationCenter.default.publisher(for:.NSCalendarDayChanged)) {_ in referenceDate=Date()}
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)) {_ in referenceDate=Date()}
            .sheet(isPresented: $selectingList) { TodoListSelectionView(selection: $draft.listID) }
            .onChange(of: lists.map(\.id)) { _, ids in
                if let selected = draft.listID, !ids.contains(selected) { draft.listID = nil }
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
            try draft.validateReminderForSave(now: Date(), existingReminder: task?.remindAt,
                usesExistingFutureTemplate: futureSeries && task?.seriesID != nil)
            let service = TodoTaskService(context: context)
            let id: UUID
            if let task { try service.edit(id: task.id, draft: draft, futureSeries: futureSeries); id = task.id }
            else if let importantDayOperation { id = try importantDayOperation.createTodo(draft, id: submissionID, context: context).id }
            else { id = try service.create(draft, sourceEntryID: sourceEntry?.id, id: submissionID, importantDayID: importantDayID, importantDayOccurrence: importantDayOccurrence).id }
            let saved = try service.task(id: id)
            var affectedOpenSuccessor: TodoTask?
            if futureSeries, saved.state != .open, let seriesID = saved.seriesID {
                affectedOpenSuccessor = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
                    .first { $0.state == .open }
            }
            reminders.reportSavedTask(saved, affectedOpenSuccessor: affectedOpenSuccessor)
            let channel=draft.reminderChannel ?? .notification
            let ask=draft.remindAt != nil
            Task {await reminders.reconcile(context:context,requestPermission:ask && channel == .notification,requestAlarmPermission:ask && channel == .alarm)}
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
        case .weekdays: return String(localized:"Every Monday through Friday")
        case .weekends: return String(localized:"Every Saturday and Sunday")
        case .customWeekdays: return String(localized:"Selected weekdays")
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
    @Query private var seriesPreferences: [TodoSeriesPreferences]
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
                                if let frequency=TodoFrequency(rawValue:rule.frequencyRawValue) {
                                    Text(TodoRepeatDescription.summary(frequency:frequency,mask:seriesPreferences.first {$0.id == rule.id}?.weekdaysMask))
                                    Text(rule.anchorDay).font(.caption)
                                } else {Text("Unknown repeat rule") }
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
                            TodoReminderControls(taskID:taskID,statusIdentifier:"todo-reminder-status")
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

struct TodoListSelectionView: View {
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoList.createdAt) private var lists: [TodoList]
    @State private var creating = false
    @State private var createdID: UUID?
    @State private var managing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Unclassified") { selection = nil; dismiss() }.accessibilityIdentifier("todo-select-unclassified")
                    ForEach(lists) { list in
                        Button { selection = list.id; dismiss() } label: {
                            HStack { Text(list.name); Spacer(); if selection == list.id { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("todo-select-list-\(list.id)")
                    }
                }
                Section {
                    Button("New List") { creating = true }.accessibilityIdentifier("todo-editor-new-list")
                    Button("Manage Lists") { managing = true }.accessibilityIdentifier("todo-editor-manage-lists")
                }
            }.navigationTitle("List")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $creating, onDismiss: {
                if createdID != nil { dismiss() }
            }) {
                TodoNewListView { id in selection = id; createdID = id; creating = false }
            }
            .sheet(isPresented: $managing) { TodoListsView() }
            .onChange(of: lists.map(\.id)) { _, ids in
                if let selection, !ids.contains(selection) { self.selection = nil }
            }
        }
    }
}

private struct TodoNewListView: View {
    let onCreated: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("List name", text: $name).accessibilityIdentifier("todo-new-list-name")
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("New List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create List") {
                        do { onCreated(try TodoTaskService(context: context).createList(name: name).id) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("todo-new-list-create")
                }
            }
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


struct TodoFeedbackMedia {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
}
extension EnvironmentValues {
    @Entry var todoFeedbackMedia: TodoFeedbackMedia? = nil
}

/// Lives both in the editor (continuous input) and shell (after sheet dismissal).
struct TodoReminderFeedbackView: View {
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Environment(\.todoFeedbackMedia) private var media
    @State private var showingTask = false
    var body: some View {
        if reminders.hasPendingCancellation {
            VStack(alignment:.leading,spacing:8) {
                Text("Old reminders may still sound until cancellation is confirmed.").font(.subheadline)
                Button("Recheck reminder cancellation") {Task {await reminders.reconcile(context:context)}}
                    .accessibilityIdentifier("todo-global-cancellation-recheck")
            }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.bar)
        }
        if let id = reminders.savedTaskID ?? reminders.savedFactID, let task = tasks.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Todo saved").font(.headline)
                TodoReminderControls(taskID:task.id,statusIdentifier:"todo-saved-reminder-status")
                HStack {
                    if media != nil {
                        Button("View Todo") { showingTask = true }.accessibilityIdentifier("todo-feedback-view-task")
                    }
                    Spacer()
                    Button("Got it") { reminders.savedTaskID = nil; reminders.savedFactID = nil }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("todo-reminder-feedback-dismiss")
                }.frame(minHeight: 44)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("todo-saved-reminder-feedback")
            .sheet(isPresented: $showingTask) {
                if let media {
                    NavigationStack {
                        TodoDetailView(taskID: id, mediaStore: media.mediaStore, thumbnailStore: media.thumbnailStore)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTask = false } } }
                    }
                }
            }
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


enum TodoRepeatDescription {
    static func weekday(_ iso: Int, locale: Locale = .current) -> String {
        let formatter=DateFormatter();formatter.calendar=Calendar(identifier:.gregorian);formatter.locale=locale
        return formatter.weekdaySymbols[iso % 7]
    }
    static func summary(frequency: TodoFrequency,mask: Int?) -> String {
        guard frequency == .customWeekdays else {return frequency.label}
        guard let mask,let days=try? TodoWeekdayRule.weekdays(mask) else {return String(localized:"Choose at least one weekday.")}
        return String(localized:"Selected weekdays") + ": " + days.sorted().map {weekday($0)}.joined(separator:", ")
    }
}
private struct TodoWeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.dynamicTypeSize) private var typeSize
    private let order=Array(1...7)
    var body: some View {
        LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum:140))],alignment:.leading) {
            ForEach(order,id:\.self) {day in
                Button {
                    if selection.contains(day) {selection.remove(day)} else {selection.insert(day)}
                } label: {
                    HStack {
                        Text(TodoRepeatDescription.weekday(day)).fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:4)
                        Image(systemName:selection.contains(day) ? "checkmark.circle.fill" : "circle")
                    }.frame(maxWidth:.infinity,minHeight:44).contentShape(.rect)
                }.buttonStyle(.bordered).accessibilityIdentifier("todo-weekday-\(day)")
                    .accessibilityValue(selection.contains(day) ? String(localized:"Selected") : String(localized:"Not selected"))
            }
        }
    }
}

private struct TodoReminderControls: View {
    let taskID: UUID
    let statusIdentifier: String
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(TodoReminderCoordinator.self) private var reminders
    @State private var snapshot: TodoReminderDisplaySnapshot?
    @State private var failed=false
    @State private var settingTime=false
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if failed {
                Text("Could not read reminder settings.").foregroundStyle(.red)
                Button("Retry") {load()}
            } else if let snapshot {
                if let date=snapshot.task.remindAt {Text(date,format:.dateTime.year().month().day().hour().minute()).font(.subheadline)}
                Text(snapshot.channel.label).font(.caption)
                TimelineView(.periodic(from:.now,by:30)) {_ in
                    let status=reminders.status(for:snapshot.task,cancellationUnverified:snapshot.cancellationUnverified,inactive:!snapshot.active)
                    VStack(alignment:.leading,spacing:8) {
                        Text(status.label).accessibilityIdentifier(statusIdentifier)
                        if status == .cancellationPending {
                            Button("Recheck reminder cancellation") {recheck()}.accessibilityIdentifier("todo-reminder-recheck-cancellation")
                            settingsButton
                        } else if snapshot.active {
                            switch status {
                            case .elapsed,.stopped:
                                Button("Set reminder again") {settingTime=true}.accessibilityIdentifier("todo-reminder-reset")
                            case .permissionRequired,.alarmPermissionRequired:
                                Button("Enable reminder") {retry(snapshot)}.accessibilityIdentifier("todo-reminder-enable")
                            case .denied,.alarmDenied:
                                settingsButton
                                Button("Change reminder method or time") {settingTime=true}.accessibilityIdentifier("todo-reminder-reset")
                            case .failed:
                                Button("Retry setting reminder") {retry(snapshot)}.accessibilityIdentifier("todo-reminder-retry")
                            case .confirmationRequired:
                                Button("Recheck reminder") {recheck()}
                                Button("Set reminder again") {settingTime=true}.accessibilityIdentifier("todo-reminder-reset")
                            case .queueFull,.alarmQueueFull:
                                Button("Recheck available slots") {recheck()}
                            case .unsupportedAlarm:
                                Button("Change reminder method or time") {settingTime=true}.accessibilityIdentifier("todo-reminder-reset")
                            default:
                                Button("Modify reminder time") {settingTime=true}.accessibilityIdentifier("todo-reminder-reset")
                            }
                        }
                    }
                }
            }
            if let error {Text(error).foregroundStyle(.red)}
        }.frame(maxWidth:.infinity,alignment:.leading)
        .onAppear {load()}
        .task {await reminders.reconcile(context:context);load()}
        .onReceive(NotificationCenter.default.publisher(for:ModelContext.didSave).receive(on:RunLoop.main)) {_ in load()}
        .onChange(of:phase) {_,new in if new == .active {recheck()}}
        .sheet(isPresented:$settingTime,onDismiss:{load()}) {NavigationStack {TodoReminderRescheduleView(taskID:taskID)}}
    }
    private var settingsButton: some View {
        Button("Open iOS Settings") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}
    }
    private func load() {
        do {snapshot=try TodoReminderDisplaySnapshot.read(id:taskID,container:context.container);failed=false}
        catch {failed=true}
    }
    private func recheck() {Task {await reminders.reconcile(context:context);load()}}
    private func retry(_ value: TodoReminderDisplaySnapshot) {
        guard let fire=value.task.remindAt,fire > Date() else {settingTime=true;return}
        do {
            try TodoTaskService(context:context).rescheduleReminder(id:taskID,to:fire,channel:value.channel,expectedRevision:value.task.revision)
            Task {await reminders.reconcile(context:context,requestPermission:value.channel == .notification,requestAlarmPermission:value.channel == .alarm);load()}
        } catch {self.error=error.localizedDescription;load()}
    }
}
extension TodoReminderChannel {
    var label: String {self == .alarm ? String(localized:"Alarm reminder") : String(localized:"Notification reminder")}
}
private struct TodoReminderRescheduleView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var snapshot: TodoReminderDisplaySnapshot?
    @State private var channel: TodoReminderChannel = .notification
    @State private var chosen=Date().addingTimeInterval(3600)
    @State private var error: String?
    @State private var busy=false
    var body: some View {
        Form {
            if let snapshot,snapshot.active {
                Section {
                    Text("This changes only this occurrence's reminder. Its plan, deadline and future series stay the same.").font(.caption)
                    Picker("Reminder method",selection:$channel) {ForEach(TodoReminderChannel.allCases,id:\.self) {Text($0.label).tag($0)}}.accessibilityIdentifier("todo-reminder-method")
                    if channel == .alarm {Text("A stronger system alarm. Requires iOS 26 and alarm permission; stopping it does not complete the todo.").font(.caption)}
                }
                Section("Set reminder again") {
                    Button("In 10 minutes") {save(Date().addingTimeInterval(600))}.accessibilityIdentifier("todo-reminder-ten-minutes")
                    if TodoRescheduleDate.tomorrow(reminder:snapshot.task.remindAt,wallMinutes:snapshot.task.reminderMinutes,now:Date(),zone:.current) != nil {
                        Button("Tomorrow at the same reminder time") {saveTomorrow()}.accessibilityIdentifier("todo-reminder-tomorrow")
                    }
                    Text("Tomorrow follows Gregorian local days. Missing clock times move to the next valid time; repeated times use the first occurrence.").font(.caption)
                }
                Section("Choose reminder time") {
                    if typeSize.isAccessibilitySize {
                        Text("Reminder Time")
                        DatePicker("Reminder Time",selection:$chosen,in:Date()...,displayedComponents:[.date,.hourAndMinute]).labelsHidden().datePickerStyle(.wheel)
                    } else {DatePicker("Reminder Time",selection:$chosen,in:Date()...,displayedComponents:[.date,.hourAndMinute])}
                    Button("Use selected time") {save(chosen)}.accessibilityIdentifier("todo-reminder-use-time")
                }
            } else {
                Text("This todo is no longer open for reminders. Refresh its details.")
            }
            if let error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("todo-reminder-edit-error")
                Button("Reload reminder settings") {load()}
            }
        }.navigationTitle("Set reminder again")
        .disabled(busy)
        .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Cancel") {dismiss()}}}
        .task {load()}
    }
    private func load() {
        do {snapshot=try TodoReminderDisplaySnapshot.read(id:taskID,container:context.container);channel=snapshot?.channel ?? .notification;error=nil}
        catch {self.error=error.localizedDescription}
    }
    private func saveTomorrow() {
        do {
            guard let value=try TodoReminderDisplaySnapshot.read(id:taskID,container:context.container),
                  value.task.revision == snapshot?.task.revision,
                  let date=TodoRescheduleDate.tomorrow(reminder:value.task.remindAt,wallMinutes:value.task.reminderMinutes,now:Date(),zone:.current) else {throw TodoFailure.staleTask}
            save(date)
        } catch {self.error=error.localizedDescription}
    }
    private func save(_ date: Date) {
        guard !busy else {return};busy=true
        do {
            try TodoTaskService(context:context).rescheduleReminder(id:taskID,to:date,channel:channel,expectedRevision:snapshot?.task.revision)
            let selected=channel
            Task {await reminders.reconcile(context:context,requestPermission:selected == .notification,requestAlarmPermission:selected == .alarm)}
            dismiss()
        } catch {self.error=error.localizedDescription;busy=false}
    }
}
