import Foundation
import Observation
import SwiftData
import SwiftUI
import Charts

@MainActor @Observable final class SleepDraftSession {
    var draft: SleepDraft
    var saving = false
    var error: String?
    init(_ draft: SleepDraft) { self.draft = draft }
}
@MainActor @Observable final class SleepWorkspace {
    private let now: () -> Date
    private(set) var reference: Date
    init(now: @escaping () -> Date = Date.init) { self.now = now; reference = now() }
    func advanceEvaluationClock() { reference = now() }
    func review(windowDays: Int) -> SleepReviewSnapshot {
        .init(records: records, goals: goals, windowDays: windowDays, today: ImportantCivilDay(reference), now: reference)
    }
    var records: [SleepRecordTransfer] = []
    var goals: [SleepGoalRule] = []
    var sessions: [String: SleepDraftSession] = [:]
    var message: String?
    var loadError: String?
    func refresh(_ context: ModelContext) {
        do {
            let timestamp = now()
            try SleepGoalSemantics.observe(context: context, now: timestamp)
            let read = ModelContext(context.container)
            let freshRecords = try read.fetch(FetchDescriptor<SleepRecord>()).map(SleepRecordTransfer.init).sorted { $0.wakeDay > $1.wakeDay }
            let freshGoals = try read.fetch(FetchDescriptor<SleepGoalRule>())
            // Publish complete facts and their evaluation instant in the same main-actor turn.
            records = freshRecords; goals = freshGoals; reference = timestamp
            loadError = nil
        } catch { loadError = SleepFailure.corrupt.localizedDescription }
    }
    func session(day: String) throws -> SleepDraftSession {
        if let existing = sessions[day] { return existing }
        let draft: SleepDraft
        if let record = records.first(where: { $0.wakeDay == day }) { draft = try SleepDraft(record.model()) }
        else { draft = SleepDraft(day: day) }
        let session = SleepDraftSession(draft); sessions[day] = session; return session
    }
}

enum SleepFormatting {
    static func axisHour(_ hour: Int) -> String {
        let day = hour < 0 ? String(localized: "Previous day") : hour < 24 ? String(localized: "Wake day") : String(localized: "Next day")
        return day + "\n" + minute(((hour % 24) + 24) % 24 * 60)
    }
    static func minute(_ minute: Int) -> String { String(format: "%02d:%02d", (minute / 60) % 24, minute % 60) }
    static func range(_ range: SleepRange?) -> String {
        guard let range else { return String(localized: "Unknown") }
        let lower = range.day + " " + minute(range.minute)
        if range.precision == 0 { return lower + " · " + String(localized: "Manually recalled") }
        let end = range.minute + range.precision
        let endDay = end >= 1440 ? ImportantCivilDay(identifier: range.day)!.adding(days: 1)!.identifier + " " : ""
        return lower + "–" + endDay + minute(end)
    }
    static func feeling(_ value: Int) -> String {
        switch value {
        case 5: String(localized: "Very good")
        case 4: String(localized: "Good")
        case 3: String(localized: "Fair")
        case 2: String(localized: "Poor")
        default: String(localized: "Very poor")
        }
    }
    static func interval(_ interval: ClosedRange<TimeInterval>?) -> String {
        guard let interval else { return String(localized: "Unknown or overlapping ranges; interval cannot be estimated.") }
        func duration(_ seconds: TimeInterval) -> String {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes / 60) h \(minutes % 60) min")
        }
        return duration(interval.lowerBound) + "–" + duration(interval.upperBound)
    }
    static func summary(_ record: SleepRecordTransfer?) -> String {
        guard let record else { return String(localized: "Record last night's rest") }
        var parts: [String] = []
        if let b = record.values.bedtime { parts.append(minute(b.minute) + (b.precision == 0 ? "" : "–" + minute(b.minute + b.precision))) }
        if let w = record.values.wake { parts.append(minute(w.minute) + (w.precision == 0 ? "" : "–" + minute(w.minute + w.precision))) }
        if let f = record.values.feeling { parts.append(feeling(f)) }
        if record.values.bedtime == nil || record.values.wake == nil || record.values.feeling == nil { parts.append(String(localized: "Partial record")) }
        return parts.joined(separator: " · ")
    }
}

struct SleepTodaySection: View {
    @Environment(SleepWorkspace.self) private var workspace
    @AppStorage("sleep.showToday") private var showToday = true
    @AppStorage("sleep.introductionDismissed") private var introduced = false
    let open: (String) -> Void
    let referenceDate: Date
    private var day: String { ImportantCivilDay(referenceDate).identifier }
    var body: some View {
        if showToday {
            Section {
                Button { open(day) } label: {
                    HStack(spacing: 8) {
                        ModuleEntryRow(title: String(localized: "Last night's sleep"),
                            subtitle: SleepFormatting.summary(workspace.records.first { $0.wakeDay == day }), systemImage: "moon.zzz")
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("today-sleep")
                if !introduced {
                    HStack(alignment: .top) {
                        Text("Remember when you began trying to sleep and when you got up. No goal or reminder is required.").font(.caption)
                        Button { introduced = true } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Dismiss introduction")
                    }
                }
            }
        }
    }
}

struct SleepEditorLoader: View {
    let day: String
    @Environment(SleepWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @State private var session: SleepDraftSession?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let session { SleepEditorView(session: session, originalDay: day) }
                else if let error { ContentUnavailableView("Unable to open sleep record", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else { ProgressView() }
            }
            .toolbar { if session == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
        }.task {
            workspace.refresh(context)
            do { if let error = workspace.loadError { self.error = error } else { session = try workspace.session(day: day) } }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct SleepEditorView: View {
    @Bindable var session: SleepDraftSession
    let originalDay: String
    @Environment(SleepWorkspace.self) private var workspace
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showDelete = false
    @State private var more = false
    private var zone: TimeZone { TimeZone(identifier: session.draft.timeZoneID) ?? .current }
    private var day: String { session.draft.wakeDay }
    var body: some View {
        Form {
            Section {
                Text("Wake day: \(day)").font(.headline).accessibilityIdentifier("sleep-wake-day")
                Text(SleepFormatting.range(session.draft.values.bedtime) + " → " + SleepFormatting.range(session.draft.values.wake)).font(.caption).foregroundStyle(.secondary)
                Text("Bedtime means beginning to try to sleep. Getting up means ending your main rest and starting your day.").font(.caption)
            }
            Section {
                SleepRangeInput(title: "Bedtime", kind: "bed", range: $session.draft.values.bedtime, day: day, zone: zone)
                SleepRangeInput(title: "Getting up", kind: "wake", range: $session.draft.values.wake, day: day, zone: zone)
                Button("Just got up") {
                    let now = Date(); var c = Calendar(identifier: .gregorian); c.timeZone = zone
                    guard ImportantCivilDay(now, timeZone: zone).identifier == day else { session.error = SleepFailure.invalidDay.localizedDescription; return }
                    session.draft.values.wake = SleepRange(day: day, minute: c.component(.hour, from: now) * 60 + c.component(.minute, from: now), precision: 0)
                }.accessibilityIdentifier("sleep-just-up")
            }
            Section("Overall feeling") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 4) {
                    ForEach((1...5).reversed(), id: \.self) { value in
                        Button { session.draft.values.feeling = value } label: {
                            Text(SleepFormatting.feeling(value)).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                                .background(session.draft.values.feeling == value ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityIdentifier("sleep-feeling-\(value)").accessibilityAddTraits(session.draft.values.feeling == value ? .isSelected : [])
                    }
                    Button("Unknown") { session.draft.values.feeling = nil }.frame(minHeight: 44).accessibilityIdentifier("sleep-feeling-unknown")
                }
            }
            Section {
                Button("Save sleep record") { save() }.disabled(session.saving || !session.draft.values.hasContent)
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("sleep-save")
                if session.draft.values.bedtime != nil && session.draft.values.wake != nil {
                    if let interval = SleepRules.interval(session.draft.values, zone: zone) {
                        if interval.upperBound > 18 * 3600 { Text("Long interval: check the dates in the original record.").font(.caption) }
                    } else { Text("Unknown or overlapping ranges; interval cannot be estimated.").font(.caption) }
                }
                if let error = session.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("sleep-error")
                    if let saved = workspace.records.first(where: { $0.wakeDay == day }) {
                        DisclosureGroup("Compare with saved record") {
                            Text(SleepFormatting.range(saved.values.bedtime)); Text(SleepFormatting.range(saved.values.wake))
                            Text(saved.values.feeling.map(SleepFormatting.feeling) ?? String(localized: "Unknown"))
                            Text(saved.values.note)
                            Button("Reload saved record and discard this draft", role: .destructive) {
                                do { session.draft = try SleepDraft(saved.model()); session.error = nil }
                                catch { session.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Note and date options", isExpanded: $more) {
                    TextField("Optional note", text: $session.draft.values.note, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("sleep-note")
                    DatePicker("Wake date", selection: Binding(get: { ImportantCivilDay(identifier: day)!.date! }, set: { date in
                        let next = ImportantCivilDay(date, timeZone: TimeZone(secondsFromGMT: 0)!)
                        guard ImportantCivilDay(identifier: next.identifier) != nil, let current = ImportantCivilDay(identifier: day), let delta = current.distance(to: next) else { session.error = SleepFailure.invalidDay.localizedDescription; return }
                        session.draft.wakeDay = next.identifier
                        if let range = session.draft.values.bedtime, let d = ImportantCivilDay(identifier: range.day)?.adding(days: delta) { session.draft.values.bedtime?.day = d.identifier }
                        if session.draft.values.wake != nil { session.draft.values.wake?.day = next.identifier }
                    }), displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    Text("Dates above preview the whole record. An existing wake day cannot be overwritten.").font(.caption)
                    TextField("Recording time zone", text: $session.draft.timeZoneID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Confirm the time zone for recalled dates. Travel does not move saved records.").font(.caption)
                    Button("Discard draft", role: .destructive) { workspace.sessions[originalDay] = nil; dismiss() }
                }
            }
            if session.draft.id != nil {
                Section("Filling evidence") {
                    evidence("Bedtime", exists: session.draft.values.bedtime != nil, stamp: session.draft.values.bedtimeFilledAt)
                    evidence("Getting up", exists: session.draft.values.wake != nil, stamp: session.draft.values.wakeFilledAt)
                    evidence("Overall feeling", exists: session.draft.values.feeling != nil, stamp: session.draft.values.feelingFilledAt)
                    Text(SleepFormatting.interval(SleepRules.interval(session.draft.values, zone: zone)))
                    Text(SleepRules.goal(day: day, zone: zone, values: session.draft.values, rules: workspace.goals).label)
                    Button("Delete sleep record", role: .destructive) { showDelete = true }.accessibilityIdentifier("sleep-delete")
                }
            }
        }
        .navigationTitle("Sleep and Routine").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(session.saving) } }
        .confirmationDialog("Delete this sleep record?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete sleep record", role: .destructive) {
                do {
                    if let id = session.draft.id, let revision = session.draft.expectedRevision { try SleepService(context: context).delete(id: id, revision: revision) }
                    workspace.sessions[originalDay] = nil; workspace.refresh(context); dismiss()
                } catch { session.error = error.localizedDescription }
            }
        }
    }
    private func evidence(_ label: LocalizedStringKey, exists: Bool, stamp: Date?) -> some View {
        LabeledContent(label) { Text(exists ? SleepRules.timing(stamp, day: day, zone: zone).label : String(localized: "Unknown")) }
    }
    private func save() {
        guard !session.saving else { return }; session.saving = true; session.error = nil
        do {
            try SleepService(context: context).save(session.draft)
            workspace.sessions[originalDay] = nil; workspace.refresh(context)
            workspace.message = String(localized: "Sleep record saved.")
            Task { @MainActor in
                await reminders.reconcile(context: context)

            }
            dismiss()
        } catch { workspace.refresh(context); session.error = error.localizedDescription; session.saving = false }
    }
}

private struct SleepRangeInput: View {
    let title: LocalizedStringKey
    let kind: String
    @Binding var range: SleepRange?
    let day: String
    let zone: TimeZone
    @State private var custom = false
    @State private var hour = 23
    @State private var minute = 0
    @State private var width = 0
    @State private var previous = true
    @State private var offset: Int? = nil
    private var isBed: Bool { kind == "bed" }
    private var priorDay: String { ImportantCivilDay(identifier: day)!.adding(days: -1)!.identifier }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("Unknown") { range = nil }
                if isBed {
                    ForEach([1260, 1290, 1320, 1350, 1380, 1410, 1440, 1470, 1500, 1530], id: \.self) { m in choice(m, width: 30) }
                    Menu("60 minute ranges") { ForEach([1260, 1320, 1380, 1440, 1500], id: \.self) { m in choice(m, width: 60) } }
                } else {
                    ForEach(stride(from: 360, through: 600, by: 15).map { $0 }, id: \.self) { m in choice(m, width: 15) }
                }
                Button("Other time or exact minute…") {
                    hour = range.map { $0.minute / 60 } ?? (isBed ? 23 : 7)
                    minute = range.map { $0.minute % 60 } ?? 0
                    width = range?.precision ?? (isBed ? 30 : 15); previous = range.map { $0.day == priorDay } ?? isBed
                    offset = range?.utcOffset; custom = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(SleepFormatting.range(range)).font(.subheadline).foregroundStyle(.secondary)
                    if let range, (try? range.bounds(zone: zone)) == nil { Text("Civil range retained; absolute time is uncertain due to daylight saving.").font(.caption) }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.accessibilityIdentifier("sleep-\(kind)-menu")
            if custom {
                if isBed { Picker("Bedtime date", selection: $previous) { Text(priorDay).tag(true); Text(day).tag(false) } }
                HStack {
                    Picker("Hour", selection: $hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                    Picker("Minute", selection: $minute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                }
                Picker("Precision", selection: $width) {
                    Text("Exact minute · recalled").tag(0)
                    if !isBed { Text("15 minutes").tag(15) }
                    Text("30 minutes").tag(30); Text("60 minutes").tag(60)
                }
                let civil = ImportantCivilDay(identifier: isBed && previous ? priorDay : day)!
                let noon = civil.instant(minutes: 720, timeZone: zone)!
                let offsets = Array(Set([-43200.0, 43200.0].map { zone.secondsFromGMT(for: noon.addingTimeInterval($0)) })).sorted()
                if offsets.count > 1 {
                    Picker("Repeated time occurrence", selection: $offset) {
                        Text("Not confirmed").tag(Int?.none)
                        ForEach(offsets, id: \.self) { Text("UTC offset: \($0 / 60) min").tag(Optional($0)) }
                    }
                }
                Button("Use this time") {
                    range = .init(day: isBed && previous ? priorDay : day, minute: hour * 60 + minute, precision: width, utcOffset: offset); custom = false
                }.accessibilityIdentifier("sleep-\(kind)-apply")
            }
        }
    }
    private func choice(_ minutes: Int, width: Int) -> some View {
        let selectedDay = isBed && minutes < 1440 ? priorDay : day
        let value = SleepRange(day: selectedDay, minute: minutes % 1440, precision: width)
        return Button(SleepFormatting.range(value)) { range = value }.accessibilityIdentifier("sleep-\(kind)-\(minutes)-\(width)")
    }
}

struct SleepHubView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(SleepWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var route: SleepExternalRoute?
    @State private var today = ImportantCivilDay(Date()).identifier
    var body: some View {
        List {
            Section {
                Button("Record last night's rest") { route = .init(id: today) }.accessibilityIdentifier("sleep-add")
                NavigationLink("7 / 30 day review") { SleepReviewView() }.accessibilityIdentifier("sleep-review")
                NavigationLink("Sleep settings") { SleepSettingsView(mediaStore: mediaStore, thumbnailStore: thumbnailStore) }.accessibilityIdentifier("sleep-settings")
            }
            if let error = workspace.loadError { Text(error).foregroundStyle(.red) }
            Section("Sleep history") {
                if workspace.records.isEmpty { Text("No sleep records yet. Partial records are welcome.") }
                ForEach(workspace.records, id: \.id) { record in
                    Button { route = .init(id: record.wakeDay) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.wakeDay).font(.headline); Text(SleepFormatting.summary(record)).font(.subheadline)
                            if let zone = TimeZone(identifier: record.timeZoneID) {
                                let v = record.values
                                let timings = [v.bedtimeFilledAt, v.wakeFilledAt, v.feelingFilledAt].compactMap { $0 }.map { SleepRules.timing($0, day: record.wakeDay, zone: zone) }
                                if timings.contains(.nextDay) || timings.contains(.recalled) { Text("Contains late-filled or recalled fields").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("sleep-history-\(record.wakeDay)")
                }
            }
        }.navigationTitle("Sleep and Routine")
        .sheet(item: $route) { route in SleepEditorLoader(day: route.id) }
        .onAppear { today = ImportantCivilDay(Date()).identifier; workspace.refresh(context) }
        .onChange(of: phase) { _, p in if p == .active { today = ImportantCivilDay(Date()).identifier; workspace.refresh(context) } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = ImportantCivilDay(Date()).identifier }
    }
}

struct SleepReviewView: View {
    @Environment(SleepWorkspace.self) private var workspace
    @State private var window = 7
    @State private var route: SleepExternalRoute?
    @Environment(\.scenePhase) private var phase
    private var snapshot: SleepReviewSnapshot {
        workspace.review(windowDays: window)
    }
    var body: some View {
        List {
            Picker("Review window", selection: $window) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented)
            Section("Coverage and evidence") {
                Text("\(snapshot.recordedDays) recorded wake days / \(window) calendar days")
                ForEach(SleepFieldTiming.allCases, id: \.rawValue) { timing in LabeledContent(timing.label, value: String(snapshot.count(timing: timing))) }
                Text("Counts describe filled fields. Recalled and unknown filling times are excluded separately for each metric. Blank days are unknown, not zero.").font(.caption)
            }
            Section("Time ranges and bedtime–getting-up interval") {
                Text("Bedtime samples: \(snapshot.bedtimeCount) · Getting-up samples: \(snapshot.wakeCount) · Interval samples: \(snapshot.intervalCount)").font(.caption)
                Text("Dates keep the cross-night axis: previous-evening times precede wake-day morning times. This interval includes time awake; it is not measured sleep duration.").font(.caption)
                if snapshot.bedtimeCount + snapshot.wakeCount > 0 {
                    Chart {
                        ForEach(snapshot.nights) { night in
                            if let b = night.bedtime, let axis = night.axis(b) {
                                RuleMark(xStart: .value("Civil hour", Double(axis.lowerBound) / 60), xEnd: .value("Civil hour", Double(axis.upperBound) / 60), y: .value("Wake day", night.record.wakeDay))
                                    .foregroundStyle(by: .value("Field", String(localized: "Bedtime"))).lineStyle(StrokeStyle(lineWidth: 5))
                                PointMark(x: .value("Civil hour", Double(axis.lowerBound) / 60), y: .value("Wake day", night.record.wakeDay)).foregroundStyle(by: .value("Field", String(localized: "Bedtime")))
                            }
                            if let w = night.wake, let axis = night.axis(w) {
                                RuleMark(xStart: .value("Civil hour", Double(axis.lowerBound) / 60), xEnd: .value("Civil hour", Double(axis.upperBound) / 60), y: .value("Wake day", night.record.wakeDay))
                                    .foregroundStyle(by: .value("Field", String(localized: "Getting up"))).lineStyle(StrokeStyle(lineWidth: 5))
                                PointMark(x: .value("Civil hour", Double(axis.lowerBound) / 60), y: .value("Wake day", night.record.wakeDay)).foregroundStyle(by: .value("Field", String(localized: "Getting up")))
                            }
                        }
                    }
                    .chartXScale(domain: snapshot.axisHourDomain)
                    .chartXAxis { AxisMarks(values: [-24, 0, 24]) { value in
                        AxisGridLine(); AxisValueLabel { if let hour = value.as(Int.self) { Text(SleepFormatting.axisHour(hour)).font(.caption2).multilineTextAlignment(.center) } }
                    } }
                    .frame(height: CGFloat(min(440, max(160, snapshot.nights.count * 24))))
                    .accessibilityIdentifier("sleep-time-trend")
                    NavigationLink("Open plotted nights") { SleepReviewSourceList(windowDays: window, matches: { $0.bedtime != nil || $0.wake != nil }) }
                }
                ForEach(snapshot.nights) { night in
                    Button { route = .init(id: night.record.wakeDay) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(night.record.wakeDay).font(.headline)
                            Text(SleepFormatting.range(night.bedtime)); Text(SleepFormatting.range(night.wake))
                            Text(SleepFormatting.interval(night.interval))
                            if let interval = night.interval, interval.upperBound > 18 * 3600 { Text("Long interval: check the dates in the original record.") }
                        }.font(.subheadline).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("sleep-review-night-\(night.record.wakeDay)")
                }
            }
            Section("Subjective feeling distribution") {
                Text("Valid ratings: \(snapshot.feelingCount)")
                ForEach((1...5).reversed(), id: \.self) { feeling in
                    NavigationLink { SleepReviewSourceList(windowDays: window, matches: { $0.feeling == feeling }) } label: {
                        LabeledContent(SleepFormatting.feeling(feeling), value: String(snapshot.count(feeling: feeling)))
                    }.accessibilityIdentifier("sleep-review-feeling-\(feeling)")
                }
            }
            Section("Personal bedtime goal") {
                ForEach(SleepGoalResult.allCases, id: \.rawValue) { result in
                    NavigationLink { SleepReviewSourceList(windowDays: window, matches: { $0.goal == result }) } label: {
                        LabeledContent(result.label, value: String(snapshot.count(goal: result)))
                    }
                }
            }
        }.navigationTitle("Sleep review")
        .sheet(item: $route) { route in SleepEditorLoader(day: route.id) }
        .onAppear { workspace.advanceEvaluationClock() }
        .onChange(of: phase) { _, p in if p == .active { workspace.advanceEvaluationClock() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in workspace.advanceEvaluationClock() }
    }
}
private struct SleepReviewSourceList: View {
    let windowDays: Int
    let matches: (SleepReviewNight) -> Bool
    @Environment(SleepWorkspace.self) private var workspace
    @State private var route: SleepExternalRoute?
    private var nights: [SleepReviewNight] { workspace.review(windowDays: windowDays).nights.filter(matches) }
    var body: some View {
        List {
            if nights.isEmpty { Text("No matching sleep records.") }
            ForEach(nights) { night in Button(night.record.wakeDay) { route = .init(id: night.record.wakeDay) }.accessibilityIdentifier("sleep-source-night-\(night.record.wakeDay)") }
        }.navigationTitle("Original sleep records").sheet(item: $route) { route in SleepEditorLoader(day: route.id) }
        .onAppear { workspace.advanceEvaluationClock() }
    }
}

struct SleepSettingsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(SleepWorkspace.self) private var workspace
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(\.modelContext) private var context
    @AppStorage("sleep.showToday") private var showToday = true
    @AppStorage(SleepReminderPreferences.enabledKey) private var reminderEnabled = false
    @AppStorage(SleepReminderPreferences.minuteKey) private var reminderMinute = 540
    @State private var goalEnabled = false
    @State private var goalMinute = 1410
    @State private var error: String?
    private var effective: String { SleepGoalSemantics.proposedDay(rules: workspace.goals, now: Date(), zone: .current).identifier }
    var body: some View {
        Form {
            Section("Today entry") { Toggle("Show sleep on Today", isOn: $showToday).accessibilityIdentifier("sleep-show-today"); Text("Hiding this entry keeps history and independently enabled reminders.").font(.caption) }
            Section("Personal bedtime goal") {
                Toggle("Use a personal bedtime goal", isOn: $goalEnabled).accessibilityIdentifier("sleep-goal-enabled")
                if goalEnabled { timePicker("No later than", minutes: $goalMinute) }
                Text("Effective wake day: \(effective)")
                if let day = ImportantCivilDay(identifier: effective) { Text("Cutoff: \(goalMinute >= 720 ? day.adding(days: -1)!.identifier : day.identifier) \(SleepFormatting.minute(goalMinute))").font(.caption) }
                Text("First goal starts today. Later changes and disabling start next wake day; past nights keep their rules.").font(.caption)
                Button("Save bedtime goal") {
                    do { try SleepService(context: context).setGoal(cutoffMinute: goalEnabled ? goalMinute : nil); workspace.refresh(context); workspace.message = String(localized: "Bedtime goal saved.") }
                    catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("sleep-save-goal")
                ForEach(workspace.goals.sorted { $0.effectiveDay > $1.effectiveDay }) { rule in
                    Text(rule.effectiveDay + " · " + (rule.cutoffMinute.map(SleepFormatting.minute) ?? String(localized: "Goal disabled"))).font(.caption)
                }
            }
            Section("Morning reminder") {
                Toggle("Remind me to record sleep", isOn: $reminderEnabled).accessibilityIdentifier("sleep-reminder-enabled")
                timePicker("Morning reminder time", minutes: $reminderMinute)
                Text(reminders.sleepStatus().status.label).accessibilityIdentifier("sleep-reminder-status")
                if let next = reminders.sleepStatus().nextFire { Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))") }
                if let end = reminders.sleepStatus().coverageEnd { Text("Scheduled through: \(end.formatted(date: .abbreviated, time: .shortened))") }
                Text("At most one per wake day, planned for up to 7 days. Open the app to refresh coverage. Recorded days are not prompted.").font(.caption)
                Button("Refresh reminder status") { Task { await reminders.reconcile(context: context) } }
            }
            Section {
                Text("Existing early-bedtime habits stay independent. Sleep records do not check off habits or change their history.").font(.caption)
                NavigationLink("Manage existing habits") { HabitsView(mediaStore: mediaStore, thumbnailStore: thumbnailStore) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Sleep settings")
        .onAppear {
            let latest = workspace.goals.max { $0.effectiveDay < $1.effectiveDay }
            goalEnabled = latest?.cutoffMinute != nil; goalMinute = latest?.cutoffMinute ?? 1410
        }
        .onChange(of: reminderEnabled) { _, enabled in Task { await reminders.reconcile(context: context, requestPermission: enabled) } }
        .onChange(of: reminderMinute) { _, _ in Task { await reminders.reconcile(context: context) } }
    }
    private func timePicker(_ title: LocalizedStringKey, minutes: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(get: { SleepWallClock.pickerDate(minutes: minutes.wrappedValue, zone: .current) }, set: { date in
            minutes.wrappedValue = SleepWallClock.minutes(date, zone: .current)
        }), displayedComponents: .hourAndMinute)
    }
}

struct SleepFeedbackView: View {
    @Environment(SleepWorkspace.self) private var workspace
    @Environment(TodoReminderCoordinator.self) private var reminders
    @AppStorage(SleepReminderPreferences.enabledKey) private var enabled = false
    private func feedback(_ message: String) -> String {
        guard message == String(localized: "Sleep record saved."), enabled else { return message }
        let status = reminders.sleepStatus().status
        if status == .scheduled || status == .elapsed { return message }
        if status == .checking { return message + " " + status.label }
        return String(localized: "Record saved. The morning reminder is not fully scheduled.") + " " + status.label
    }
    var body: some View {
        if let message = workspace.message {
            HStack { Text(feedback(message)).font(.caption); Spacer(); Button("Got it") { workspace.message = nil } }.padding(8).background(.bar).accessibilityIdentifier("sleep-save-feedback")
        }
    }
}
