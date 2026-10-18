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
    private(set) var duplicateValues: InvestmentValues?
    private(set) var duplicateActivity: UUID?
    private(set) var duplicateDuration: String?
    var duplicateIDs: [UUID] = []
    func showDuplicates(_ ids: [UUID]) {
        duplicateIDs=ids;duplicateValues=values;duplicateActivity=activityID;duplicateDuration=durationText
        duplicate=true;showDuplicateDialog=true
    }
    func clearDuplicateCandidates() {
        duplicateValues=nil;duplicateActivity=nil;duplicateDuration=nil
        duplicateIDs=[];duplicate=false;showDuplicateDialog=false
    }
    func eraseConsumedContent() {
        finished=true
        values=InvestmentTimer(state:.discarded,values:values,target:nil,checkpointAt:Date()).erasingConsumedContent().values
        durationText="";clearDuplicateCandidates();cancelExactIntervalReplacement()
    }
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
        if duplicate && (duplicateValues != values || duplicateActivity != activityID || duplicateDuration != durationText) {
            clearDuplicateCandidates()
        }
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
    private(set) var participants: [InvestmentParticipantTransfer] = []
    private(set) var activities: [InvestmentActivityTransfer] = []
    private(set) var operations: [InvestmentOperationSnapshot] = []
    var editors: [UUID: InvestmentEditorState] = [:]
    var error: String?
    var reference = Date()
    private(set) var review: InvestmentReviewSnapshot?
    private(set) var reviewError: String?
    private(set) var reviewGeneration = 0
    var me: UUID? { participants.first(where: \.isDefault)?.id }
    var myActivities: [InvestmentActivityTransfer] { activities.filter { $0.participantID == me }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var unfinished: [InvestmentOperationSnapshot] { operations.filter { $0.participantID == me && $0.timer.state.unfinished } }
    var drafts: [InvestmentOperationSnapshot] { operations.filter { $0.participantID == me && $0.timer.state == .draft } }
    let reader: InvestmentUIReader
    private var storeID: ObjectIdentifier?
    private var seenSequence = -1
    private var factsVersion = -1
    private var metadataVersion = -1
    private var operationsVersion = -1
    init(reader: InvestmentUIReader? = nil) {self.reader=reader ?? InvestmentUIReader()}
    private var metadataError: String?
    private var operationsError: String?
    func refresh(_ context: ModelContext, retry: Bool = false) {
        let container=context.container,version=InvestmentChanges.version(context.container)
        let newStore=storeID != ObjectIdentifier(container),previousMe=me
        if newStore {
            participants=[];activities=[];operations=[];review=nil
            metadataError=nil;operationsError=nil;reviewError=nil
            metadataVersion = -1;factsVersion = -1;operationsVersion = -1;seenSequence = -1
            storeID=ObjectIdentifier(container)
        }
        if metadataVersion != version.metadata || (retry && metadataError != nil) {
            metadataVersion=version.metadata
            do {let (p,a)=try reader.metadata(container);participants=p;activities=a;metadataError=nil}
            catch {participants=[];activities=[];metadataError=error.localizedDescription}
        }
        let ids=Set(version.operationIDs.filter {$0.value > seenSequence}.map(\.key))
        let full=operationsVersion != version.operations || (retry && operationsError != nil)
        if full || (!ids.isEmpty && operationsError == nil) {
            operationsVersion=version.operations
            do {
                let update=try reader.operations(container,ids:full ? nil:ids)
                let removed=full ? Set(operations.map(\.id)):ids
                operations.removeAll {removed.contains($0.id)};operations += update.active
                for (id,editor) in editors where update.erased.contains(id) || editor.editingSessionID.map({update.erased.contains($0)}) == true {
                    editor.eraseConsumedContent();editors.removeValue(forKey:id)
                }
                operationsError=nil
            } catch {operationsError=error.localizedDescription}
        }
        if factsVersion != version.facts || previousMe != me || (retry && review == nil) {
            // Record the attempted version even on failure. Draft events cannot implicitly
            // retry an expensive failed history scan; explicit Retry or new formal facts can.
            factsVersion=version.facts;reviewGeneration += 1
            do {
                if let metadataError {throw InvestmentEditorPersistenceFailure(message:metadataError)}
                review=try reader.review(container,participantID:me);reviewError=nil
            } catch {review=nil;reviewError=error.localizedDescription}
        }
        seenSequence=version.sequence;reference=Date()
        error=metadataError ?? operationsError ?? reviewError
    }
    func receive(_ notification: Notification, context: ModelContext) {
        guard notification.object as? ModelContainer === context.container else {return}
        refresh(context)
    }
    func session(id: UUID,context: ModelContext) throws -> InvestmentSessionTransfer? {
        try reader.page(context.container,ids:[id],detail:true).first
    }
    func checkpoint(_ context: ModelContext, clock: @escaping () -> InvestmentClock = InvestmentClock.current) {
        let service = InvestmentService(context:context,clock:clock)
        do {
            refresh(context)
            guard operationsError == nil else {return}
            for op in operations where op.timer.state == .running {
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
        guard let review else { throw InvestmentEditorPersistenceFailure(message:reviewError ?? String(localized:"Unable to read investment statistics")) }
        return review.contributions
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
    static func accumulated(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        if seconds < 1 && seconds > 0 { return String(localized: "Less than 1 second") }
        let total = Int(seconds.rounded(.down))
        if total < 60 { return String(localized: "\(total) sec") }
        return String(localized: "\(total / 3600) h \((total / 60) % 60) min")
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
        case .intervals: String(localized:"Includes start and end times")
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
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let op = workspace.unfinished.first {
                            ModuleEntryRow(title: workspace.name(op.activityID),
                                subtitle: InvestmentFormatting.state(op.timer.projected(at: InvestmentClock.current()).state), systemImage: "timer")
                        }
                    }
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
            if let message = error ?? workspace.error {
                Section {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("investment-error")
                    Button("Retry") {workspace.refresh(context,retry:true)}
                }
            }
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
                        if let review = workspace.review {
                            Text("Total recorded: \(InvestmentFormatting.accumulated(review.activitySeconds[activity.id,default:0]))").monospacedDigit().accessibilityLabel("Total recorded investment")
                        } else {
                            Text(workspace.reviewError ?? String(localized:"Unable to read investment statistics")).foregroundStyle(.red)
                            Button("Retry") { workspace.refresh(context,retry:true) }
                        }
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
            do {
                try InvestmentReviewTestSupport.seedUsageHistoryIfRequested(context)
                try InvestmentReviewTestSupport.seedSegmentsIfRequested(context)
            } catch {workspace.error=error.localizedDescription}
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
        .toolbar { ToolbarItem(placement:.confirmationAction) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Button(closeLabel) { dismiss() }.accessibilityIdentifier("investment-collapse-timer")
            }
        } }
        .confirmationDialog("Discard this unfinished timer?",isPresented:$discard,titleVisibility:.visible) {
            Button("Discard timer",role:.destructive) { command(.discard); if error == nil { dismiss() } }
        }
        .sheet(item:$editor) { editor in NavigationStack { InvestmentEditorView(editor:editor) } }
        .task { workspace.checkpoint(context) }
    }
    private var closeLabel: String {
        guard let state = op?.timer.projected(at: InvestmentClock.current()).state else { return String(localized: "Close") }
        switch state {
        case .running: return String(localized: "Collapse timer")
        case .paused: return String(localized: "Keep paused")
        default: return String(localized: "Confirm later")
        }
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
    @FocusState private var inputFocused: Bool
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
                TextField("Duration in minutes",text:$editor.durationText).focused($inputFocused).keyboardType(.decimalPad).accessibilityIdentifier("investment-duration")
                    .onChange(of:editor.durationText) { _, text in
                        if let minutes = Double(text), minutes.isFinite, minutes >= 0, minutes <= 527040 { editor.values.changeDuration(minutes * 60) }
                        persist()
                    }
                Text(InvestmentFormatting.evidence(editor.values.evidence)).font(.caption)
                DisclosureGroup("Time details") { Text(editor.values.timeZoneID).font(.caption).foregroundStyle(.secondary) }
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
                TextField("What did you do or feel?",text:$editor.values.note,axis:.vertical).focused($inputFocused).lineLimit(3...8)
                    .accessibilityIdentifier("investment-note").onChange(of:editor.values.note) { _, _ in persist() }
            }
            if let error = editor.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("investment-save-error") } }
            if editor.duplicate {
                InvestmentSessionPage(selection:.init(rows:[],daySeconds:[:],orderedSessionIDs:editor.duplicateIDs),generation:workspace.reviewGeneration,key:editor.id.uuidString,title:"Possible matching records",showsContribution:false)
            }
            Section {
                Button("Save activity") { save(false) }.accessibilityIdentifier("investment-save")
                Button(editor.timerConfirmation ? "Confirm later" : "Keep draft") { if persist(isClosing:true) {dismiss()} }.accessibilityIdentifier("investment-keep-draft")
                if !editor.timerConfirmation { Button("Cancel draft",role:.destructive) { cancel = true } }
            }
        }.navigationTitle(editor.timerConfirmation ? "Confirm time investment" : "Record activity")
        .interactiveDismissDisabled(!editor.finished)
        .toolbar {
            ToolbarItem(placement:.confirmationAction) {
                if inputFocused {
                    Button { inputFocused=false } label: { Image(systemName:"keyboard.chevron.compact.down").frame(minWidth:44,minHeight:44) }
                        .accessibilityLabel("Done").accessibilityIdentifier("investment-dismiss-keyboard")
                }
            }
        }
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
        } catch InvestmentFailure.duplicate {
            do {editor.showDuplicates(try InvestmentService(context:context).matchingSessionIDs(values:editor.values,participantID:editor.participantID,excluding:editor.editingSessionID ?? editor.id))}
            catch {editor.error=error.localizedDescription;return}
            editor.error = InvestmentFailure.duplicate.localizedDescription
        }
        catch { editor.error = error.localizedDescription }
    }
}

struct InvestmentHistoryView: View {
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @State private var days = 0
    @State private var activity: UUID?
    @State private var selectedDay: String?
    @State private var browseDate = Date()
    @State private var earlierMonth = false
    private var today: ImportantCivilDay { ImportantCivilDay(workspace.reference) }
    private var previewBounds: (ImportantCivilDay,ImportantCivilDay) {
        if days != 0 { return (today.adding(days:1-days)!,today) }
        if earlierMonth {
            let chosen = ImportantCivilDay(browseDate)
            let first = ImportantCivilDay(year:chosen.year,month:chosen.month,day:1)
            let next = ImportantCivilDay.utcCalendar.date(byAdding:.month,value:1,to:first.date!)!
            return (first,ImportantCivilDay(next,timeZone:TimeZone(secondsFromGMT:0)!).adding(days:-1)!)
        }
        return (today.adding(days:-29)!,today)
    }
    private func moveMonth(_ delta: Int) {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .current
        if let next = calendar.date(byAdding:.month,value:delta,to:browseDate) { browseDate=next }
    }
    var body: some View {
        List {
            Section {
                Picker("Review period",selection:Binding(get:{days},set:{days=$0;selectedDay=nil})) { Text("All time").tag(0); Text("7 days").tag(7); Text("30 days").tag(30) }
                    .pickerStyle(.segmented).accessibilityIdentifier("investment-review-period")
                Picker("Activity filter",selection:$activity) {
                    Text("All activities").tag(nil as UUID?)
                    ForEach(workspace.myActivities,id:\.id) { Text($0.name).tag(Optional($0.id)) }
                }
                Text("Recorded investment is not a measure of skill. Days without records mean no record, not proven zero effort.").font(.caption)
            }
            if let review = workspace.review {
                let selection = review.selection(days:days == 0 ? nil : days,today:today,activityID:activity,day:selectedDay)
                Section(selectedDay ?? String(localized:"Current period")) {
                    LabeledContent("Recorded duration",value:InvestmentFormatting.duration(selection.seconds)).accessibilityIdentifier("investment-review-total")
                    LabeledContent("Sessions",value:String(selection.count)).accessibilityIdentifier("investment-review-count")
                    if selectedDay != nil { Button("Show whole period") { selectedDay = nil }.accessibilityIdentifier("investment-clear-day") }
                    InvestmentDateField("Inspect date",selection:$browseDate,displayedComponents:.date).accessibilityIdentifier("investment-inspect-date")
                    Button("Inspect selected date") {
                        let chosen=ImportantCivilDay(browseDate)
                        let period=InvestmentReview.periodForInspection(days:days,day:chosen,today:today)
                        if period != days {days=period;earlierMonth=true}
                        selectedDay=chosen.identifier
                    }
                }
                Section("Daily recorded investment") {
                    if days == 0 {
                        Toggle("Preview selected month",isOn:$earlierMonth)
                        if earlierMonth {
                            Button("Previous month") { moveMonth(-1) }.accessibilityIdentifier("investment-previous-month")
                            Button("Next month") { moveMonth(1) }.accessibilityIdentifier("investment-next-month")
                        }
                    }
                    let bounds = previewBounds
                    Text(bounds.0.identifier + " → " + bounds.1.identifier).font(.caption).accessibilityIdentifier("investment-preview-range")
                    Text("The chart previews this date range. All-time totals include the complete saved history.").font(.caption)
                    let dates = selection.daySeconds.keys.sorted().filter { $0 >= bounds.0.identifier && $0 <= bounds.1.identifier }
                    Chart(dates,id:\.self) { day in
                        let parts = day.split(separator:"-").compactMap { Int($0) }
                        if parts.count == 3, let date = ImportantCivilDay(year:parts[0],month:parts[1],day:parts[2]).date {
                            BarMark(x:.value("Day",date),y:.value("Minutes",selection.daySeconds[day,default:0]/60))
                        }
                    }.chartXScale(domain:bounds.0.date!...bounds.1.adding(days:1)!.date!)
                        .chartXAxis { AxisMarks(values:.stride(by:.day,count:days == 7 ? 1 : 7)) { _ in AxisGridLine(); AxisValueLabel(format:.dateTime.month().day(),centered:true) } }
                        .environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                        .frame(height:180).accessibilityLabel("Daily recorded investment")
                    Text("Select a day below to inspect its contribution. Cross-day sessions count once in each review period.").font(.caption)
                    if dates.isEmpty { Text("No records in this selection") }
                    ForEach(dates.reversed(),id:\.self) { day in
                        Button { selectedDay = day } label: {
                            ViewThatFits(in:.horizontal) {
                                HStack { Text(day); Spacer(); Text(InvestmentFormatting.duration(selection.daySeconds[day,default:0])).monospacedDigit() }
                                VStack(alignment:.leading,spacing:4) { Text(day); Text(InvestmentFormatting.duration(selection.daySeconds[day,default:0])).monospacedDigit() }
                            }.frame(minHeight:44).contentShape(.rect)
                        }.accessibilityIdentifier("investment-day-\(day)")
                    }
                }
                InvestmentSessionPage(selection:selection,generation:workspace.reviewGeneration,key:"\(today.identifier)-\(days)-\(activity?.uuidString ?? "all")-\(selectedDay ?? "period")")
            } else {
                Section {
                    Text(workspace.reviewError ?? String(localized:"Unable to read investment statistics")).foregroundStyle(.red)
                    Button("Retry") { workspace.refresh(context,retry:true) }
                }
            }
        }.navigationTitle("History and review")
        .onReceive(NotificationCenter.default.publisher(for:.NSCalendarDayChanged)) { _ in workspace.reference=Date() }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)) { _ in workspace.reference=Date() }
        .onChange(of:activity) { _, _ in selectedDay = nil }
    }
}

/// Only the IDs on this page are fetched again as full formal records. A missing selected day stays empty.
private struct InvestmentSessionPage: View {
    let selection: InvestmentReviewSelection
    let generation: Int
    let key: String
    var title: LocalizedStringKey = "Saved sessions"
    var showsContribution = true
    @Environment(InvestmentWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @State private var offset = 0
    @State private var records: [InvestmentSessionTransfer] = []
    @State private var loadedKey: String?
    @State private var error: String?
    @State private var retry = 0
    private var loadKey: String { "\(generation)-\(key)-\(offset)-\(retry)" }
    var body: some View {
        Section(title) {
            Text("Newest first · 20 records per page").font(.caption).task(id:loadKey) { load() }
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { retry += 1 } }
            else if loadedKey != loadKey { ProgressView() }
            else if records.isEmpty { Text("No records in this selection") }
            else {
                ForEach(records,id:\.id) { session in
                    NavigationLink { InvestmentSessionDetailView(id:session.id) } label: {
                        VStack(alignment:.leading) {
                            Text(workspace.name(session.activityID))
                            Text(session.values.day + " · " + InvestmentFormatting.duration(session.values.seconds)).font(.caption)
                            let contribution = selection.rows.filter { $0.sessionID == session.id }.reduce(0) { $0 + $1.seconds }
                            if showsContribution && abs(contribution-session.values.seconds) > 0.001 { Text("Contribution in selection: \(InvestmentFormatting.duration(contribution))").font(.caption) }
                        }
                    }.accessibilityIdentifier("investment-session-\(session.id)")
                }
            }
            if offset > 0 { Button("Previous page") { offset = max(0,offset-20) } }
            if offset+20 < selection.count { Button("Next page") { offset += 20 } }
        }.onChange(of:key) { _,_ in offset = 0 }
        .onChange(of:generation) { _,_ in offset = 0 }
    }
    private func load() {
        do {
            let ids = selection.pageIDs(offset:offset)
            records=try workspace.reader.page(context.container,ids:ids)
            error = nil; loadedKey = loadKey
        } catch { records = []; self.error = error.localizedDescription; loadedKey = loadKey }
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
    @State private var session: InvestmentSessionTransfer?
    @State private var readError: String?
    @State private var retry = 0
    var body: some View {
        List {
            if let session {
                Section {
                    Text(workspace.name(session.activityID)).font(.title2)
                    Text(session.values.day); Text(InvestmentFormatting.duration(session.values.seconds)).monospacedDigit()
                    Text(InvestmentFormatting.evidence(session.values.evidence))
                    DisclosureGroup("Time details") { Text(session.values.timeZoneID).font(.caption) }
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
                    if let review = workspace.review {
                        ForEach(review.contributions.filter { $0.sessionID == id }) { row in
                            LabeledContent(row.day,value:InvestmentFormatting.duration(row.seconds)).accessibilityIdentifier("investment-original-day-\(row.day)")
                        }
                    } else {
                        Text(workspace.reviewError ?? String(localized:"Unable to read investment statistics")).foregroundStyle(.red)
                        Button("Retry") { workspace.refresh(context,retry:true) }
                    }
                }
                Section {
                    Button("Edit record") { editor = workspace.edit(session); editor?.persist(context) }.accessibilityIdentifier("investment-edit-session")
                    Button("Delete record",role:.destructive) { deleting = true }.accessibilityIdentifier("investment-delete-session")
                }
            } else if let readError {Text(readError).foregroundStyle(.red);Button("Retry") {retry += 1}}
            else {Text("This item is no longer available.")}
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Time investment detail")
        .task(id:"\(id)-\(workspace.reviewGeneration)-\(retry)") {
            do {session=try workspace.session(id:id,context:context);readError=nil}
            catch {session=nil;readError=error.localizedDescription}
        }
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
    static func seedUsageHistoryIfRequested(_ context: ModelContext) throws {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("-PGOSUITesting"),(args.contains("-PGOSInvestmentUsageHistory") || args.contains("-PGOSInvestmentReviewFixDates")) else {return}
        let aid=UUID(uuidString:"30000000-1111-4222-8333-444444444444")!
        guard !(try context.fetch(FetchDescriptor<InvestmentActivity>()).contains {$0.id == aid}) else {return}
        let service=InvestmentService(context:context)
        _=try service.createActivity(name:"Synthetic setup")
        let p=try context.fetch(FetchDescriptor<InvestmentParticipant>()).first!
        let a=InvestmentActivity(id:aid,participantID:p.id,name:"Synthetic history archive");a.isArchived=true;context.insert(a)
        let zone=TimeZone.current,today=ImportantCivilDay(Date())
        func insertFact(_ id: UUID, _ values: InvestmentValues, _ date: Date) throws {
            context.insert(try InvestmentSession(id:id,participantID:p.id,activityID:aid,values:values,now:date))
            context.insert(try InvestmentOperation(id:id,participantID:p.id,activityID:aid,
                timer:.init(state:.saved,values:values,target:nil,checkpointAt:date),now:date))
        }
        if args.contains("-PGOSInvestmentReviewFixDates") {
            a.isArchived=false
            let old=ImportantCivilDay(year:2026,month:9,day:1)
            try insertFact(UUID(uuidString:"30000002-1111-4222-8333-444444444444")!,InvestmentValues(day:old.identifier,timeZoneID:zone.identifier,seconds:2700,evidence:.dateDuration,source:.manual,note:"Synthetic September 1 detail"),Date())
            try insertFact(UUID(),InvestmentValues(day:today.identifier,timeZoneID:zone.identifier,seconds:900,evidence:.dateDuration,source:.manual),Date())
            try context.save();try InvestmentIntegrity.validate(context:ModelContext(context.container))
            InvestmentChanges.publish(.all,container:context.container)
            return
        }
        for index in 0..<50 {
            let day=today.adding(days:-index)!
            let values=InvestmentValues(day:day.identifier,timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual,note:"Synthetic historical day \(index)")
            try insertFact(UUID(),values,day.date!)
        }
        let yesterday=today.adding(days:-1)!,start=yesterday.instant(minutes:1430,timeZone:zone)!
        let cross=InvestmentValues(day:yesterday.identifier,timeZoneID:zone.identifier,seconds:1200,evidence:.intervals,source:.timer,
            spans:[.init(start:start,end:start.addingTimeInterval(300)),.init(start:start.addingTimeInterval(900),end:start.addingTimeInterval(1800))],note:"Synthetic paused cross-day fact")
        try insertFact(UUID(uuidString:"30000001-1111-4222-8333-444444444444")!,cross,Date())
        try context.save();try InvestmentIntegrity.validate(context:ModelContext(context.container));InvestmentChanges.publish(.all,container:context.container)
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
