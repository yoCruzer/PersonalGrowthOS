import Foundation
import Observation
import SwiftData
import SwiftUI
import Charts
import UIKit

@MainActor @Observable final class InvestmentEditorState: Identifiable {
    let id: UUID
    var participantID: UUID
    var activityID: UUID
    var values: InvestmentValues
    var durationText: String
    var editingSessionID: UUID?
    var editingRevision: Int?
    var operationRevision: Int?
    var timerConfirmation: Bool
    var error: String?
    var duplicate = false
    var showDuplicateDialog = false
    var finished = false
    private(set) var pendingExactInterval: InvestmentValues?
    private var exactBaseline: InvestmentValues?
    init(id: UUID = UUID(), participantID: UUID, activityID: UUID, values: InvestmentValues,
         editingSessionID: UUID? = nil, editingRevision: Int? = nil, operationRevision: Int? = nil,
         timerConfirmation: Bool = false, durationText: String? = nil) {
        self.id = id; self.participantID = participantID; self.activityID = activityID; self.values = values
        self.editingSessionID = editingSessionID; self.editingRevision = editingRevision
        self.operationRevision = operationRevision; self.timerConfirmation = timerConfirmation
        self.durationText = durationText ?? InvestmentFormatting.minutes(values.seconds)
    }
    @discardableResult func requestExactInterval(start: Date,end: Date,now: Date) throws -> Bool {
        var proposed=values
        proposed.spans=[.init(start:start,end:end)];proposed.seconds=end.timeIntervalSince(start)
        proposed.day=ImportantCivilDay(start,timeZone:TimeZone(identifier:values.timeZoneID)!).identifier
        proposed.evidence = .intervals
        if proposed.source == .timer {proposed.corrected=true}
        try proposed.validate(now:now)
        if values.spans.count > 1 {exactBaseline=values;pendingExactInterval=proposed;return false}
        cancelExactIntervalReplacement()
        values=proposed;durationText=InvestmentFormatting.minutes(values.seconds)
        return true
    }
    func cancelExactIntervalReplacement() {pendingExactInterval=nil;exactBaseline=nil}
    func confirmExactIntervalReplacement(now: Date) throws {
        guard let proposed=pendingExactInterval,exactBaseline == values else {throw InvestmentFailure.conflict}
        try proposed.validate(now:now)
        values=proposed;durationText=InvestmentFormatting.minutes(values.seconds)
        cancelExactIntervalReplacement()
    }
    var hasValidDuration: Bool {
        guard values.seconds.isFinite, values.seconds > 0,
              let minutes = Double(durationText), minutes.isFinite, minutes > 0 else { return false }
        return abs(minutes * 60 - values.seconds) < 0.01
    }
    @discardableResult func persist(_ context: ModelContext,commit: ((ModelContext) throws -> Void)? = nil) -> Bool {
        guard !finished else { return true }
        do {
            let save: (ModelContext) throws -> Void = commit ?? {context in
#if DEBUG
                try InvestmentReviewTestSupport.draftCommit(context)
#else
                try context.save()
#endif
            }
            operationRevision = try InvestmentService(context:context,commit:save).storeDraft(id:id,participantID:participantID,
                activityID:activityID,values:values,durationText:durationText,editingSessionID:editingSessionID,
                editingRevision:editingRevision,expectedRevision:operationRevision,timerConfirmation:timerConfirmation)
            error = nil;return true
        } catch { self.error = error.localizedDescription;return false }
    }
}

@MainActor @Observable final class InvestmentWorkspace {
    var participants: [InvestmentParticipantTransfer] = []
    var activities: [InvestmentActivityTransfer] = []
    var sessions: [InvestmentSessionTransfer] = []
    var operations: [InvestmentOperationSnapshot] = []
    var editors: [UUID: InvestmentEditorState] = [:]
    var error: String?
    var reference = Date()
    var me: UUID? { participants.first(where: \.isDefault)?.id }
    var myActivities: [InvestmentActivityTransfer] { activities.filter { $0.participantID == me }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var unfinished: [InvestmentOperationSnapshot] { operations.filter { $0.participantID == me && $0.timer.state.unfinished } }
    var drafts: [InvestmentOperationSnapshot] { operations.filter { $0.participantID == me && $0.timer.state == .draft } }
    func refresh(_ context: ModelContext) {
        do {
            let read = ModelContext(context.container)
            let p = try read.fetch(FetchDescriptor<InvestmentParticipant>()).map(InvestmentParticipantTransfer.init)
            let a = try read.fetch(FetchDescriptor<InvestmentActivity>()).map(InvestmentActivityTransfer.init)
            let s = try read.fetch(FetchDescriptor<InvestmentSession>()).map(InvestmentSessionTransfer.init)
            let o = try read.fetch(FetchDescriptor<InvestmentOperation>()).map(InvestmentOperationSnapshot.init)
            let erasedIDs=Set(o.filter {$0.timer.erasesContent}.map(\.id))
            for (id,editor) in editors where erasedIDs.contains(id) || editor.editingSessionID.map({erasedIDs.contains($0)}) == true {
                editor.finished=true
                editor.values=InvestmentTimer(state:.discarded,values:editor.values,target:nil,checkpointAt:Date()).erasingConsumedContent().values
                editor.durationText="";editors.removeValue(forKey:id)
            }
            participants = p; activities = a; sessions = s; operations = o; reference = Date(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func checkpoint(_ context: ModelContext) {
        let service = InvestmentService(context:context)
        do {
            for op in try service.operations() where op.timer.state == .running {
                try service.command(.checkpoint,id:op.id,revision:op.revision)
            }
            for editor in editors.values where !editor.finished {
                guard editor.persist(context) else {throw InvestmentEditorPersistenceFailure(message:editor.error ?? InvestmentFailure.invalid.localizedDescription)}
            }
            refresh(context)
        } catch { self.error = error.localizedDescription }
    }
    func resume(id: UUID, context: ModelContext, clock: @escaping () -> InvestmentClock = InvestmentClock.current) throws {
        // Explicitly continuing consumes the old confirmation editor, after preserving its feedback.
        if let editor = editors[id], !editor.finished {
            editor.persist(context)
            if let error = editor.error { throw InvestmentEditorPersistenceFailure(message:error) }
        }
        refresh(context)
        guard let op = operations.first(where: { $0.id == id }) else { throw InvestmentFailure.missing }
        try InvestmentService(context:context,clock:clock).command(.resume,id:id,revision:op.revision)
        editors[id]?.finished = true
        editors.removeValue(forKey:id)
        refresh(context)
    }
    func editor(for op: InvestmentOperationSnapshot) -> InvestmentEditorState {
        if let existing = editors[op.id], !existing.finished { return existing }
        let timer = op.timer
        let editor = InvestmentEditorState(id:op.id,participantID:op.participantID,activityID:op.activityID,values:timer.values,
            editingSessionID:timer.editingSessionID,editingRevision:timer.editingRevision,operationRevision:op.revision,
            timerConfirmation:timer.state != .draft,durationText:timer.durationText)
        editors[op.id] = editor; return editor
    }
    func edit(_ session: InvestmentSessionTransfer) -> InvestmentEditorState {
        if let existing = editors.values.first(where: { $0.editingSessionID == session.id && !$0.finished }) { return existing }
        let editor = InvestmentEditorState(participantID:session.participantID,activityID:session.activityID,values:session.values,
            editingSessionID:session.id,editingRevision:session.revision)
        editors[editor.id] = editor; return editor
    }
    func newEditor(activityID: UUID) throws -> InvestmentEditorState {
        guard let a = activities.first(where: { $0.id == activityID }), !a.isArchived else { throw InvestmentFailure.archived }
        let editor = InvestmentEditorState(participantID:a.participantID,activityID:a.id,
            values:.init(day:ImportantCivilDay(Date()).identifier,timeZoneID:TimeZone.current.identifier,
                seconds:2700,evidence:.dateDuration,source:.manual))
        editors[editor.id] = editor; return editor
    }
    func contributions() throws -> [InvestmentContribution] {
        guard let me else { return [] }
        return try InvestmentReview.contributions(sessions:sessions,participantID:me)
    }
    func name(_ id: UUID) -> String { activities.first { $0.id == id }?.name ?? String(localized:"Investment activity") }
}

struct InvestmentEditorPersistenceFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum InvestmentFormatting {
    static func minutes(_ seconds: Double) -> String {
        var text = String(format:"%.8f",locale:Locale(identifier:"en_US_POSIX"),seconds / 60)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        if seconds > 0, Double(text) == 0 {
            return String(max(seconds / 60,Double.leastNonzeroMagnitude))
        }
        return text
    }
    static func span(_ span: InvestmentSpan, zoneID: String, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date:.numeric,time:.standard)
        style.timeZone = TimeZone(identifier:zoneID) ?? .current; style.locale = locale
        return span.start.formatted(style) + " → " + span.end.formatted(style)
    }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        if seconds > 0 && seconds < 1 { return String(localized:"Less than 1 second") }
        let total = Int(seconds.rounded(.down))
        return String(format:"%d:%02d:%02d",total / 3600,(total / 60) % 60,total % 60)
    }
    static func state(_ state: InvestmentTimerState) -> String {
        switch state {
        case .running: String(localized:"Timer running")
        case .paused: String(localized:"Timer paused")
        case .targetReached: String(localized:"Target reached — confirm time")
        case .pendingSave: String(localized:"Finished — waiting to save")
        case .recoveryRequired: String(localized:"Recovered time — review required")
        case .draft: String(localized:"Unsaved activity draft")
        case .saved: String(localized:"Saved")
        case .discarded, .deleted: String(localized:"Discarded")
        }
    }
    static func evidence(_ value: InvestmentEvidence) -> String {
        switch value {
        case .intervals: String(localized:"Effective time intervals")
        case .dateDuration: String(localized:"Date and duration only")
        case .correctedDuration: String(localized:"Corrected duration — no exact interval")
        }
    }
}

struct InvestmentTodaySection: View {
    @Environment(InvestmentWorkspace.self) private var workspace
    var body: some View {
        if !workspace.unfinished.isEmpty {
            Section {
                NavigationLink { InvestmentHubView() } label: {
                    Label("Unfinished time investment",systemImage:"timer")
                }.accessibilityIdentifier("today-investment")
            }
        }
    }
}

struct InvestmentHubView: View {
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @AppStorage("investment.introductionDismissed") private var introduced = false
    @State private var search = ""
    @State private var activityName = ""
    @FocusState private var activityNameFocused: Bool
    @State private var target = 0
    @State private var operationID: UUID?
    @State private var editor: InvestmentEditorState?
    @State private var editingActivity: InvestmentActivityTransfer?
    @State private var rename = ""
    @State private var showArchived = false
    @State private var error: String?
    private var active: [InvestmentActivityTransfer] { workspace.myActivities.filter { (showArchived || !$0.isArchived) && (search.isEmpty || $0.name.localizedStandardContains(search)) } }
    var body: some View {
        List {
            if !introduced {
                Section {
                    Text("You can lock the screen or use other apps while timing. This records self-reported investment, not proof of participation.")
                    Button("Got it") { introduced = true }
                }
            }
            if let message = error ?? workspace.error { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("investment-error") } }
            if !workspace.unfinished.isEmpty {
                Section("Unfinished timer") {
                    ForEach(workspace.unfinished) { op in
                        Button { operationID = op.id } label: {
                            VStack(alignment:.leading) { Text(workspace.name(op.activityID)); Text(InvestmentFormatting.state(op.timer.state)).font(.caption) }
                        }.accessibilityIdentifier("investment-unfinished")
                    }
                }
            }
            if !workspace.drafts.isEmpty {
                Section("Activity drafts") {
                    ForEach(workspace.drafts) { op in Button(workspace.name(op.activityID)) { editor = workspace.editor(for:op) } }
                }
            }
            Section {
                NavigationLink { InvestmentHistoryView() } label: { Label("History and review",systemImage:"chart.bar") }
                    .accessibilityIdentifier("investment-history")
            }
            Section("Activities") {
                Picker("Countdown target",selection:$target) {
                    Text("Stopwatch").tag(0); Text("25 min").tag(25); Text("40 min").tag(40); Text("60 min").tag(60)
                }.accessibilityIdentifier("investment-target")
                Toggle("Include archived activities",isOn:$showArchived)
                ForEach(active,id:\.id) { activity in
                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            Text(activity.name).font(.headline); Spacer()
                            Button { editingActivity = activity; rename = activity.name } label: { Image(systemName:"ellipsis").frame(minWidth:44,minHeight:44) }
                                .accessibilityLabel("Edit activity").accessibilityIdentifier("investment-edit-activity-\(activity.id)")
                        }
                        let total = (try? workspace.contributions().filter { $0.activityID == activity.id }.reduce(0) { $0 + $1.seconds }) ?? 0
                        Text(InvestmentFormatting.duration(total)).monospacedDigit().accessibilityLabel("Total recorded investment")
                        if activity.isArchived { Text("Archived").font(.caption) }
                        else {
                            ViewThatFits(in:.horizontal) {
                                HStack { startButton(activity); recordButton(activity) }
                                VStack(alignment:.leading) { startButton(activity); recordButton(activity) }
                            }
                        }
                    }.padding(.vertical,4)
                }
            }
            Section("New activity") {
                TextField("Activity name",text:$activityName).focused($activityNameFocused).accessibilityIdentifier("investment-activity-name")
                if workspace.myActivities.contains(where: { $0.name.localizedStandardCompare(activityName.trimmingCharacters(in:.whitespacesAndNewlines)) == .orderedSame }) {
                    Text("An activity with a similar name already exists. You can still create a separate activity.").font(.caption)
                }
                Button("Create activity") { run { _ = try InvestmentService(context:context).createActivity(name:activityName); activityName = ""; activityNameFocused = false } }
                    .accessibilityIdentifier("investment-create-activity").disabled(activityName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                if workspace.myActivities.isEmpty {
                    ForEach([String(localized:"Reading"),String(localized:"Learning"),String(localized:"Exercise"),String(localized:"Coding")],id:\.self) { name in
                        Button(name) { run { _ = try InvestmentService(context:context).createActivity(name:name) } }
                    }
                }
            }
        }
        .navigationTitle("Time investment").accessibilityIdentifier("investment-hub")
        .searchable(text:$search,prompt:"Find activities")
        .task {
#if DEBUG
            do {try InvestmentReviewTestSupport.seedSegmentsIfRequested(context)} catch {workspace.error=error.localizedDescription}
#endif
            workspace.refresh(context)
        }
        .sheet(isPresented:Binding(get:{operationID != nil},set:{if !$0 {operationID = nil}})) {
            if let operationID { NavigationStack { InvestmentTimerView(id:operationID) } }
        }
        .sheet(item:$editor) { editor in NavigationStack { InvestmentEditorView(editor:editor) } }
        .alert("Edit activity",isPresented:Binding(get:{editingActivity != nil},set:{if !$0 {editingActivity = nil}})) {
            TextField("Activity name",text:$rename)
            Button("Save name") { if let activity = editingActivity { run { try InvestmentService(context:context).updateActivity(id:activity.id,name:rename,archived:activity.isArchived) } }; editingActivity = nil }
            Button(editingActivity?.isArchived == true ? "Restore activity" : "Archive activity") {
                if let activity = editingActivity { run { try InvestmentService(context:context).updateActivity(id:activity.id,name:activity.name,archived:!activity.isArchived) } }; editingActivity = nil
            }
            Button("Cancel",role:.cancel) { editingActivity = nil }
        }
    }
    private func startButton(_ activity: InvestmentActivityTransfer) -> some View {
        Button { let id = UUID(); run { try InvestmentService(context:context).start(activityID:activity.id,participantID:activity.participantID,operationID:id,target:target == 0 ? nil : Double(target*60)); operationID = id } } label: { Label("Start timing",systemImage:"play.fill").frame(minHeight:44) }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("investment-start-\(activity.id)")
    }
    private func recordButton(_ activity: InvestmentActivityTransfer) -> some View {
        Button { run { editor = try workspace.newEditor(activityID:activity.id); editor?.persist(context) } } label: { Label("Record activity",systemImage:"square.and.pencil").frame(minHeight:44) }
            .buttonStyle(.bordered).accessibilityIdentifier("investment-record-\(activity.id)")
    }
    private func run(_ action: () throws -> Void) { do { try action(); error = nil; workspace.refresh(context) } catch { self.error = error.localizedDescription; workspace.refresh(context) } }
}

struct InvestmentTimerView: View {
    let id: UUID
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editor: InvestmentEditorState?
    @State private var error: String?
    @State private var discard = false
    private var op: InvestmentOperationSnapshot? { workspace.operations.first { $0.id == id } }
    var body: some View {
        Form {
            if let op {
                Section {
                    Text(workspace.name(op.activityID)).font(.title2)
                    TimelineView(.periodic(from:.now,by:1)) { _ in
                        let current = op.timer.projected(at:InvestmentClock.current())
                        VStack(alignment:.leading,spacing:12) {
                            Text(InvestmentFormatting.duration(current.values.seconds)).font(.largeTitle).monospacedDigit().accessibilityIdentifier("investment-timer-duration")
                            Text(InvestmentFormatting.state(current.state)).accessibilityIdentifier("investment-timer-state")
                            if current.state == .running { Button("Pause") { command(.pause) }.accessibilityIdentifier("investment-pause") }
                            if [.paused,.targetReached,.pendingSave,.recoveryRequired].contains(current.state) {
                                Button("Continue from now") { command(.resume) }.accessibilityIdentifier("investment-resume")
                            }
                            if [.running,.paused].contains(current.state) {
                                Button("Finish timing") { command(.finish); openConfirmation() }.accessibilityIdentifier("investment-finish")
                            } else if current.state.unfinished {
                                Button("Review and save") { command(.checkpoint); openConfirmation() }.accessibilityIdentifier("investment-review-save")
                            }
                        }.buttonStyle(.bordered)
                    }
                    if op.timer.state == .recoveryRequired { Text("Only the last trusted checkpoint is suggested. Review or correct it; time since the checkpoint is not added automatically.").font(.caption) }
                }
                if op.timer.state.unfinished { Section { Button("Discard timer",role:.destructive) { discard = true } } }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Timer")
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Close") { dismiss() } } }
        .confirmationDialog("Discard this unfinished timer?",isPresented:$discard,titleVisibility:.visible) {
            Button("Discard timer",role:.destructive) { command(.discard); if error == nil { dismiss() } }
        }
        .sheet(item:$editor) { editor in NavigationStack { InvestmentEditorView(editor:editor) } }
        .task { workspace.checkpoint(context) }
    }
    private func command(_ action: InvestmentService.Command) {
        guard let op else { return }
        do {
            if case .resume = action { try workspace.resume(id:id,context:context) }
            else { try InvestmentService(context:context).command(action,id:id,revision:op.revision) }
            error = nil; workspace.refresh(context)
        }
        catch { self.error = error.localizedDescription; workspace.refresh(context) }
    }
    private func openConfirmation() { if error == nil, let op, [.pendingSave,.targetReached,.recoveryRequired].contains(op.timer.state) { editor = workspace.editor(for:op) } }
}

private struct InvestmentDateField: View {
    let title: LocalizedStringKey
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: LocalizedStringKey, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.date,.hourAndMinute]) {
        self.title = title; _selection = selection; self.displayedComponents = displayedComponents
    }
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment:.leading) {
                Text(title)
                DatePicker(title,selection:$selection,displayedComponents:displayedComponents)
                    .labelsHidden().datePickerStyle(.wheel).frame(maxWidth:.infinity)
            }
        } else {
            DatePicker(title,selection:$selection,displayedComponents:displayedComponents)
        }
    }
}

struct InvestmentEditorView: View {
    @Bindable var editor: InvestmentEditorState
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var cancel = false
    @State private var confirmExact = false
    @State private var start = Date().addingTimeInterval(-2700)
    @State private var end = Date()
    private var zone: TimeZone { TimeZone(identifier:editor.values.timeZoneID) ?? .current }
    var body: some View {
        Form {
            Section {
                Picker("Investment activity",selection:$editor.activityID) {
                    ForEach(workspace.myActivities.filter { !$0.isArchived || $0.id == editor.activityID },id:\.id) { Text($0.name).tag($0.id) }
                }.disabled(editor.timerConfirmation)
                InvestmentDateField("Occurrence date",selection:Binding(get:{ImportantCivilDay(identifier:editor.values.day)?.instant(minutes:720,timeZone:zone) ?? Date()},set:{ editor.values.day = ImportantCivilDay($0,timeZone:zone).identifier; if editor.values.evidence == .intervals { editor.values.spans = []; editor.values.evidence = .correctedDuration; editor.values.corrected = true }; persist() }),displayedComponents:.date)
                    .environment(\.timeZone,zone).accessibilityIdentifier("investment-date")
                TextField("Duration in minutes",text:$editor.durationText).keyboardType(.decimalPad).accessibilityIdentifier("investment-duration")
                    .onChange(of:editor.durationText) { _, text in
                        if let minutes = Double(text), minutes.isFinite, minutes >= 0, minutes <= 527040 { editor.values.changeDuration(minutes * 60) }
                        persist()
                    }
                Text(InvestmentFormatting.evidence(editor.values.evidence)).font(.caption)
                Text(editor.values.timeZoneID).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Optional exact interval") {
                    if editor.values.spans.count > 1 {
                        Text("This record contains separate effective segments. A continuous interval may include paused time.").font(.caption)
                        ForEach(Array(editor.values.spans.enumerated()),id:\.offset) {_,span in Text(InvestmentFormatting.span(span,zoneID:editor.values.timeZoneID)).font(.caption)}
                    }
                    InvestmentDateField("Start",selection:$start).environment(\.timeZone,zone)
                    InvestmentDateField("End",selection:$end).environment(\.timeZone,zone)
                    Button("Use this exact interval") {
                        do {if try editor.requestExactInterval(start:start,end:end,now:Date()) {persist()} else {confirmExact=true}}
                        catch {editor.error=error.localizedDescription}
                    }
                }
            }
            Section("Experience (optional)") {
                Picker("Experience",selection:Binding(get:{editor.values.feeling ?? 0},set:{editor.values.feeling = $0 == 0 ? nil : $0; persist()})) {
                    Text("Not filled").tag(0)
                    ForEach(1...5,id:\.self) { Text(SleepFormatting.feeling($0)).tag($0) }
                }.accessibilityIdentifier("investment-feeling")
                TextField("What did you do or feel?",text:$editor.values.note,axis:.vertical).lineLimit(3...8)
                    .accessibilityIdentifier("investment-note").onChange(of:editor.values.note) { _, _ in persist() }
            }
            if let error = editor.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("investment-save-error") } }
            if editor.duplicate {
                Section("Possible matching records") {
                    ForEach(workspace.sessions.filter { record in
                        guard record.participantID == editor.participantID, record.id != editor.editingSessionID else { return false }
                        let a = editor.values, b = record.values
                        if a.evidence == .intervals && b.evidence == .intervals { return a.spans.contains { x in b.spans.contains { y in x.start < y.end && y.start < x.end } } }
                        return a.day == b.day && a.seconds == b.seconds
                    },id:\.id) { record in
                        NavigationLink { InvestmentSessionDetailView(id:record.id) } label: { Text(workspace.name(record.activityID) + " · " + record.values.day + " · " + InvestmentFormatting.duration(record.values.seconds)) }
                    }
                }
            }
            Section {
                Button("Save activity") { save(false) }.accessibilityIdentifier("investment-save")
                Button(editor.timerConfirmation ? "Close and keep pending" : "Close and keep draft") { if persist(isClosing:true) {dismiss()} }
                if !editor.timerConfirmation { Button("Cancel draft",role:.destructive) { cancel = true } }
            }
        }.navigationTitle(editor.timerConfirmation ? "Confirm time investment" : "Record activity")
        .interactiveDismissDisabled(!editor.finished)
        .toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) } } }
        .confirmationDialog("Cancel this draft?",isPresented:$cancel,titleVisibility:.visible) {
            Button("Cancel draft",role:.destructive) {
                do {
                    if let revision = editor.operationRevision { try InvestmentService(context:context).command(.discard,id:editor.id,revision:revision) }
                    editor.finished = true; workspace.refresh(context); dismiss()
                } catch { editor.error = error.localizedDescription }
            }
        }
        .sheet(isPresented:$confirmExact,onDismiss:{editor.cancelExactIntervalReplacement()}) {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text("Replace effective segments?").font(.title2).bold()
                        Text("A continuous interval replaces all effective segments and may include paused time. Your original segments remain until you confirm.")
                        Text(InvestmentFormatting.duration(editor.values.seconds)+" \u{2192} "+InvestmentFormatting.duration(editor.pendingExactInterval?.seconds ?? editor.values.seconds))
                            .monospacedDigit().accessibilityIdentifier("investment-interval-change")
                        Button("Keep effective segments",role:.cancel) {
                            editor.cancelExactIntervalReplacement();confirmExact=false
                        }.buttonStyle(.borderedProminent)
                        Button("Replace effective segments",role:.destructive) {
                            do {try editor.confirmExactIntervalReplacement(now:Date());persist()}
                            catch {editor.error=error.localizedDescription;editor.cancelExactIntervalReplacement()}
                            confirmExact=false
                        }.buttonStyle(.bordered)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding()
                }.navigationTitle("Optional exact interval").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
        }
        .confirmationDialog("Review possible duplicate time",isPresented:$editor.showDuplicateDialog,titleVisibility:.visible) {
            Button("Save anyway") { save(true) }
            Button("Keep editing",role:.cancel) { }
        } message: { Text("Matching records remain unchanged. You can close this form and inspect History before deciding.") }
        .onChange(of:editor.activityID) { _, _ in persist() }
        .onChange(of:phase) { _, value in if value == .background { persist() } }
        .onDisappear { editor.cancelExactIntervalReplacement();persist() }
        .task {
            if let first = editor.values.spans.first, let last = editor.values.spans.last { start = first.start; end = last.end }
        }
    }
    @discardableResult private func persist(isClosing: Bool = false) -> Bool {
#if DEBUG
        if isClosing {return editor.persist(context,commit:InvestmentReviewTestSupport.closeCommit)}
#endif
        return editor.persist(context)
    }
    private func save(_ confirmed: Bool) {
        guard editor.hasValidDuration else { editor.error = InvestmentFailure.invalid.localizedDescription; return }
        do {
            let service = InvestmentService(context:context)
            if editor.timerConfirmation {
                guard let revision = editor.operationRevision else { throw InvestmentFailure.missing }
                try service.saveTimer(id:editor.id,revision:revision,values:editor.values,confirmDuplicate:confirmed)
            } else {
                try service.saveManual(id:editor.editingSessionID ?? editor.id,participantID:editor.participantID,activityID:editor.activityID,
                    values:editor.values,expectedRevision:editor.editingRevision,confirmDuplicate:confirmed,draftID:editor.operationRevision == nil ? nil : editor.id)
            }
            editor.finished = true; workspace.refresh(context); dismiss()
        } catch InvestmentFailure.duplicate { editor.duplicate = true; editor.showDuplicateDialog = true; editor.error = InvestmentFailure.duplicate.localizedDescription }
        catch { editor.error = error.localizedDescription }
    }
}

struct InvestmentHistoryView: View {
    @Environment(InvestmentWorkspace.self) private var workspace
    @State private var days = 0
    @State private var activity: UUID?
    @State private var selectedDay: String?
    private var rows: [InvestmentContribution] {
        InvestmentReview.window((try? workspace.contributions()) ?? [],days:days == 0 ? nil : days,
            today:ImportantCivilDay(workspace.reference),activityID:activity)
    }
    private var totals: [(day:String,seconds:Double)] {
        let grouped = Dictionary(grouping:rows,by:\.day)
        return grouped.keys.sorted().map { ($0,grouped[$0]!.reduce(0) { $0 + $1.seconds }) }
    }
    private var visibleSessions: [InvestmentSessionTransfer] {
        let ids = Set(rows.filter { selectedDay == nil || $0.day == selectedDay }.map(\.sessionID))
        return workspace.sessions.filter { ids.contains($0.id) }.sorted { a,b in a.values.day == b.values.day ? a.createdAt > b.createdAt : a.values.day > b.values.day }
    }
    var body: some View {
        List {
            Section {
                Picker("Review period",selection:$days) { Text("All time").tag(0); Text("7 days").tag(7); Text("30 days").tag(30) }
                    .pickerStyle(.segmented).accessibilityIdentifier("investment-review-period")
                Picker("Activity filter",selection:$activity) {
                    Text("All activities").tag(nil as UUID?)
                    ForEach(workspace.myActivities,id:\.id) { Text($0.name).tag(Optional($0.id)) }
                }
                Text("Recorded investment is not a measure of skill. Days without records mean no record, not proven zero effort.").font(.caption)
                let chosen = selectedDay.map { day in rows.filter { $0.day == day } } ?? rows
                LabeledContent("Recorded duration",value:InvestmentFormatting.duration(chosen.reduce(0) { $0 + $1.seconds }))
                    .accessibilityIdentifier("investment-review-total")
                LabeledContent("Sessions",value:String(InvestmentReview.count(chosen))).accessibilityIdentifier("investment-review-count")
            }
            if !totals.isEmpty {
                Section("Daily recorded investment") {
                    Chart(totals.suffix(30),id:\.day) { value in
                        BarMark(x:.value("Day",value.day),y:.value("Minutes",value.seconds/60))
                    }.frame(height:180).accessibilityLabel("Daily recorded investment")
                    Text("Select a day below to inspect its contribution. Cross-day sessions count once in each review period.").font(.caption)
                    if selectedDay != nil { Button("Show whole period") { selectedDay = nil } }
                    ForEach(totals.reversed(),id:\.day) { value in
                        Button { selectedDay = selectedDay == value.day ? nil : value.day } label: {
                            ViewThatFits(in:.horizontal) {
                                HStack { Text(value.day); Spacer(); Text(InvestmentFormatting.duration(value.seconds)).monospacedDigit() }
                                VStack(alignment:.leading,spacing:4) {
                                    Text(value.day)
                                    Text(InvestmentFormatting.duration(value.seconds)).monospacedDigit()
                                }
                            }
                        }.accessibilityIdentifier("investment-day-\(value.day)")
                    }
                }
            }
            Section("Saved sessions") {
                if visibleSessions.isEmpty { Text("No records in this selection") }
                ForEach(visibleSessions,id:\.id) { session in
                    NavigationLink { InvestmentSessionDetailView(id:session.id) } label: {
                        VStack(alignment:.leading) {
                            Text(workspace.name(session.activityID)); Text(session.values.day + " · " + InvestmentFormatting.duration(session.values.seconds)).font(.caption)
                            let contribution = rows.filter { $0.sessionID == session.id && (selectedDay == nil || $0.day == selectedDay) }.reduce(0) { $0 + $1.seconds }
                            if abs(contribution-session.values.seconds) > 0.001 { Text("Contribution in selection: \(InvestmentFormatting.duration(contribution))").font(.caption) }
                        }
                    }.accessibilityIdentifier("investment-session-\(session.id)")
                }
            }
        }.navigationTitle("History and review")
        .onChange(of:days) { _, _ in selectedDay = nil }
        .onChange(of:activity) { _, _ in selectedDay = nil }
        .onChange(of:workspace.sessions) { _, _ in if let selectedDay, !rows.contains(where: { $0.day == selectedDay }) { self.selectedDay = nil } }
    }
}

struct InvestmentSessionDetailView: View {
    let id: UUID
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editor: InvestmentEditorState?
    @State private var deleting = false
    @State private var error: String?
    private var session: InvestmentSessionTransfer? { workspace.sessions.first { $0.id == id } }
    var body: some View {
        List {
            if let session {
                Section {
                    Text(workspace.name(session.activityID)).font(.title2)
                    Text(session.values.day); Text(InvestmentFormatting.duration(session.values.seconds)).monospacedDigit()
                    Text(InvestmentFormatting.evidence(session.values.evidence)); Text(session.values.timeZoneID).font(.caption)
                    Text(session.values.source == .timer ? "Recorded with timer" : "Manually recorded").font(.caption)
                    if session.values.corrected { Text("Time evidence was explicitly corrected").font(.caption) }
                    if session.values.day > ImportantCivilDay(Date(),timeZone:TimeZone(identifier:session.values.timeZoneID)!).identifier {
                        Text("This fact is later than the current clock; it is retained as recorded.").font(.caption)
                    }
                    if let feeling = session.values.feeling { Text(SleepFormatting.feeling(feeling)) } else { Text("Experience not filled") }
                    if !session.values.note.isEmpty { Text(session.values.note).textSelection(.enabled) }
                }
                if !session.values.spans.isEmpty {
                    Section("Effective time intervals") {
                        ForEach(Array(session.values.spans.enumerated()),id:\.offset) { _, span in
                            Text(InvestmentFormatting.span(span,zoneID:session.values.timeZoneID))
                        }
                    }.environment(\.timeZone,TimeZone(identifier:session.values.timeZoneID)!)
                }
                Section("Contribution by original local day") {
                    let contributions = (try? InvestmentReview.contributions(id:id,activityID:session.activityID,values:session.values)) ?? []
                    ForEach(contributions) { row in LabeledContent(row.day,value:InvestmentFormatting.duration(row.seconds)) }
                }
                Section {
                    Button("Edit record") { editor = workspace.edit(session); editor?.persist(context) }.accessibilityIdentifier("investment-edit-session")
                    Button("Delete record",role:.destructive) { deleting = true }.accessibilityIdentifier("investment-delete-session")
                }
            } else { Text("This item is no longer available.") }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Time investment detail")
        .sheet(item:$editor) { editor in NavigationStack { InvestmentEditorView(editor:editor) } }
        .confirmationDialog("Delete this time investment record?",isPresented:$deleting,titleVisibility:.visible) {
            Button("Delete record",role:.destructive) {
                if let session {
                    do { try InvestmentService(context:context).delete(id:id,revision:session.revision); workspace.refresh(context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
}

#if DEBUG
@MainActor private enum InvestmentReviewTestSupport {
    static var closeFailureConsumed=false
    static func draftCommit(_ context: ModelContext) throws {
        let args=ProcessInfo.processInfo.arguments
        if args.contains("-PGOSUITesting"),args.contains("-PGOSInvestmentCloseWriteFailure"),!closeFailureConsumed {throw CocoaError(.fileWriteOutOfSpace)}
        try context.save()
    }
    static func closeCommit(_ context: ModelContext) throws {
        let args=ProcessInfo.processInfo.arguments
        if args.contains("-PGOSUITesting"),args.contains("-PGOSInvestmentCloseWriteFailure"),!closeFailureConsumed {
            closeFailureConsumed=true
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try context.save()
    }
    static func seedSegmentsIfRequested(_ context: ModelContext) throws {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("-PGOSUITesting"),args.contains("-PGOSInvestmentSegmentReview") else {return}
        let id=UUID(uuidString:"20000000-1111-4222-8333-444444444444")!
        guard !(try context.fetch(FetchDescriptor<InvestmentOperation>()).contains {$0.id == id}) else {return}
        var clock=InvestmentClock(wall:Date().addingTimeInterval(-1800),uptime:1000,processID:"synthetic-review-process")
        let service=InvestmentService(context:context,clock:{clock})
        let activity=try service.createActivity(name:"Synthetic segment review")
        let participant=try context.fetch(FetchDescriptor<InvestmentParticipant>()).first!.id
        try service.start(activityID:activity,participantID:participant,operationID:id,zone:TimeZone(identifier:"Asia/Shanghai")!)
        func command(_ action: InvestmentService.Command) throws {
            let op=try service.operations().first {$0.id == id}!
            try service.command(action,id:id,revision:op.revision)
        }
        clock.wall.addTimeInterval(600);clock.uptime += 600;try command(.pause)
        clock.wall.addTimeInterval(300);clock.uptime += 300;try command(.resume)
        clock.wall.addTimeInterval(600);clock.uptime += 600;try command(.finish)
        let pending=try service.operations().first {$0.id == id}!
        try service.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
    }
}
#endif
