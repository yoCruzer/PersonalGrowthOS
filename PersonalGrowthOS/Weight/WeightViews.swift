import Charts
import SwiftData
import SwiftUI
import UIKit

enum WeightFormatting {
    static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1...2))) + " kg"
    }
}

struct WeightHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var snapshot: WeightReviewSnapshot?
    @State private var through = Date()
    @State private var historical = false
    @State private var range = WeightReviewRange.month
    @State private var references: Set<WeightReviewRange> = [.week, .month]
    @State private var selectedDay: Date?
    @State private var selectionZoneID: String?
    @State private var refresh = 0
    @State private var visible = false
    @State private var failed = false
    @State private var adding = false
    @State private var editing: WeightRecord?
    @State private var deleting: WeightRecord?
    @State private var error: String?

    var body: some View {
        List {
            if failed {
                ContentUnavailableView("Could not load weight records", systemImage: "exclamationmark.triangle")
                Button("Retry") { refresh += 1 }
            } else if let snapshot {
                if let latest = snapshot.latest.first {
                    Section(historical ? "Latest through selected date" : "Latest Weight") {
                        Text(WeightFormatting.kilograms(latest.kilograms)).font(.title2.bold()).accessibilityIdentifier("weight-latest-value")
                        Text(latest.recordedAt, format: .dateTime.year().month().day().hour().minute()).font(.subheadline)
                        if let previous = snapshot.latest.dropFirst().first {
                            let delta = latest.kilograms - previous.kilograms
                            Text("Since previous: \(delta > 0 ? "+" : "")\(WeightFormatting.kilograms(delta))")
                            Text(previous.recordedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        } else { Text("No previous measurement to compare") }
                    }
                } else {
                    Section {
                        ContentUnavailableView(historical ? "No records through selected date" : "No Weight Records", systemImage: "scalemass")
                            .accessibilityIdentifier("weight-empty-state")
                        GrowthEmptyStateAddButton(title: "Add Weight", systemImage: "plus") { adding = true }.accessibilityIdentifier("add-weight")
                    }
                }
                Section("Trend") {
                    Picker("Time range", selection: $range) { ForEach(WeightReviewRange.allCases) { Text($0.label).tag($0) } }
                        .accessibilityIdentifier("weight-review-range")
                    DatePicker("Statistics through", selection: Binding(get: { through }, set: { historical = true; through = $0 }), in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("weight-review-through")
                    let summary = snapshot.summaries[range]!
                    Text(summary.start.formatted(date: .abbreviated, time: .omitted) + " – " + snapshot.asOfDay.formatted(date: .abbreviated, time: .omitted)).font(.caption).accessibilityIdentifier("weight-review-dates")
                    Text("Daily points are daily means. A missing day means no record.").font(.caption).foregroundStyle(.secondary)
                    chart(snapshot)
                    DatePicker("Select a record day", selection: Binding(get: { selectedDay ?? snapshot.asOfDay }, set: { selectedDay = snapshot.calendar.startOfDay(for: $0) }), displayedComponents: .date)
                        .accessibilityIdentifier("weight-select-day")
                    if selectedDay != nil {
                        Button("Clear selection") { selectedDay = nil }.accessibilityIdentifier("weight-clear-selection")
                    }
                }
                Section("Range averages") {
                    Text("Each recorded day has equal weight. All averages use the same ending date.").font(.caption).foregroundStyle(.secondary)
                    ForEach(WeightReviewRange.allCases.filter { $0 != .all }) { reference in
                        let value = snapshot.summaries[reference]!
                        Toggle(isOn: Binding(get: { references.contains(reference) }, set: { enabled in
                            if enabled { references.insert(reference) } else { references.remove(reference) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Path { path in path.move(to: .init(x: 0, y: 6)); path.addLine(to: .init(x: 32, y: 6)) }
                                        .stroke(color(reference), style: StrokeStyle(lineWidth: 2, dash: dash(reference)))
                                        .frame(width: 32, height: 12).accessibilityHidden(true)
                                    Text(reference.label).foregroundStyle(.primary)
                                }
                                Text(value.mean.map(WeightFormatting.kilograms) ?? String(localized: "No data"))
                                Text("\(value.days) recorded days · \(value.observations) measurements").font(.caption)
                            }
                        }.accessibilityIdentifier("weight-average-\(reference.rawValue)")
                    }
                }
                Section("Recording coverage") {
                    if let first = snapshot.earliest {
                        LabeledContent("First recorded day", value: first.formatted(date: .abbreviated, time: .omitted))
                        Text("Across \(snapshot.spanDays) days, recorded on \(snapshot.recordedDays) days")
                        Text("Last 30 days: \(snapshot.summaries[.month]!.days) recorded days")
                        DisclosureGroup("Recording continuity") {
                            if let end = snapshot.streakEnd {
                                Text("Through \(end.formatted(date: .abbreviated, time: .omitted)): \(snapshot.endingStreak) consecutive recorded days")
                            } else { Text("No consecutive records ending today or yesterday") }
                            Text("Longest: \(snapshot.longestStreak) consecutive recorded days")
                        }
                    } else { Text("No recorded days through this date") }
                    DisclosureGroup("Date and average details") {
                        Text("Weight uses Gregorian days in the current device time zone. Older records do not contain their original time zone.")
                        Text(snapshot.calendar.timeZone.identifier).font(.caption)
                        Text("Missing days are not measurements. This shows app records, not whether you weighed yourself.").font(.caption)
                    }
                }
                WeightBMISection(measurement:snapshot.latest.first,historical:historical)
                Section(selectedDay == nil ? "Recent measurements" : "Selected day") {
                    if let selectedDay, let day = snapshot.daily.first(where: { $0.day == selectedDay }) {
                        LabeledContent("Daily mean (kg)", value: WeightFormatting.kilograms(day.mean)).accessibilityIdentifier("weight-selected-mean")
                        Text("\(day.observations) measurements").font(.caption)
                    }
                    WeightMeasurementPage(start: selectedDay, end: selectedDay.flatMap { snapshot.calendar.date(byAdding: .day, value: 1, to: $0) }.map { snapshot.calendar.startOfDay(for: $0) },
                        now: snapshot.now, refresh: refresh, limit: 5, edit: edit, delete: requestDelete)
                    NavigationLink("All Weight Records") { WeightAllRecordsView(edit: edit) }
                        .accessibilityIdentifier("weight-all-records")
                }
            } else { ProgressView().accessibilityLabel("Loading weight records") }
        }
        .navigationTitle("Weight").accessibilityIdentifier("weight-history-view")
        .toolbar {
            if snapshot?.latest.isEmpty == false {
                Button { adding = true } label: { Label("Add Weight", systemImage: "plus") }.accessibilityIdentifier("add-weight")
            }
        }
        .onAppear { visible = true; refresh += 1 }
        .onDisappear { visible = false }
        .task(id: refresh) { await load() }
        .onChange(of: through) { _, _ in selectedDay = nil; refresh += 1 }
        .onChange(of: phase) { _, value in if value == .active && visible { refreshForClock() } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in if visible { refresh += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in if visible { refreshForClock() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in if visible { refreshForClock() } }
        .sheet(isPresented: $adding) { WeightEditorView(record: nil) { adding = false; refresh += 1 } }
        .sheet(item: $editing) { record in WeightEditorView(record: record) { editing = nil; refresh += 1 } }
        .confirmationDialog("Delete this weight record?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Weight Record", role: .destructive) {
                if let record = deleting {
                    do { try WeightRecordService(context: context).delete(record); deleting = nil; refresh += 1 }
                    catch { self.error = String(localized: "The weight record was not deleted.") }
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .alert("Weight Update", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func refreshForClock() {
        let now = Date()
        if !historical, !Calendar(identifier: .gregorian).isDate(through, inSameDayAs: now) { through = now }
        else { refresh += 1 }
    }
    private func color(_ range: WeightReviewRange) -> Color {
        switch range { case .week: .blue; case .month: .orange; case .quarter: .purple; case .year: .green; case .all: .primary }
    }
    private func dash(_ range: WeightReviewRange) -> [CGFloat] {
        switch range { case .week: [3, 3]; case .month: [8, 3]; case .quarter: [8, 3, 2, 3]; case .year: [2, 4]; case .all: [] }
    }
    @ViewBuilder private func chart(_ snapshot: WeightReviewSnapshot) -> some View {
        let points = snapshot.points(range)
        let axis = snapshot.axis(range: range, references: references)
        if points.isEmpty { Text("No records in this selection") }
        else {
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.day), y: .value("Daily mean (kg)", point.mean), series: .value("Recorded segment", point.segment))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Date", point.day), y: .value("Daily mean (kg)", point.mean))
                        .foregroundStyle(Color.accentColor)
                }
                ForEach(WeightReviewRange.allCases.filter { references.contains($0) }) { reference in
                    if let value = snapshot.summaries[reference]?.mean {
                        RuleMark(y: .value(reference.label, value)).foregroundStyle(color(reference)).lineStyle(StrokeStyle(lineWidth: 1, dash: dash(reference)))
                    }
                }
                if let selectedDay, let point = points.first(where: { $0.day == selectedDay }) {
                    RuleMark(x: .value("Selected day", point.day)).foregroundStyle(.secondary)
                }
            }.chartXScale(domain: snapshot.summaries[range]!.start...snapshot.endExclusive)
                .chartYScale(domain: axis.domain).chartYAxis { AxisMarks(values: axis.ticks) }
                .chartXSelection(value: Binding(get: { selectedDay }, set: { value in selectedDay = value.map { snapshot.calendar.startOfDay(for: $0) } }))
                .frame(height: 200).accessibilityLabel("Weight trend").accessibilityIdentifier("weight-trend-chart")
        }
    }
    @MainActor private func load() async {
        failed = false; snapshot = nil
        let container = context.container, end = through, now = Date(), zone = TimeZone.current
        let work = Task.detached { try await WeightReviewReader(modelContainer: container).snapshot(now: now, through: end, zone: zone) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            selectedDay=WeightReviewSelection.retainedDay(selectedDay,previousZoneID:selectionZoneID,calendar:result.calendar)
            selectionZoneID=result.calendar.timeZone.identifier
            snapshot = result
        } catch is CancellationError {} catch { if !Task.isCancelled { snapshot = nil; failed = true } }
    }
    private func edit(_ id: UUID) { do { editing = try context.fetch(FetchDescriptor<WeightRecord>(predicate: #Predicate { $0.id == id })).first } catch { self.error = String(localized: "Could not load weight records") } }
    private func requestDelete(_ id: UUID) { do { deleting = try context.fetch(FetchDescriptor<WeightRecord>(predicate: #Predicate { $0.id == id })).first } catch { self.error = String(localized: "Could not load weight records") } }
}

struct WeightMeasurementPage: View {
    let start: Date?
    let end: Date?
    let now: Date
    let refresh: Int
    var limit = 50
    var paginated = false
    let edit: (UUID) -> Void
    let delete: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @State private var records: [WeightMeasurement] = []
    @State private var failed = false
    @State private var more = false
    @State private var loading = false
    @State private var loadedKey: String?
    private var key: String { "\(start?.timeIntervalSince1970 ?? -1):\(end?.timeIntervalSince1970 ?? -1):\(now.timeIntervalSince1970):\(refresh)" }
    var body: some View {
        Group {
            // A task on Group is forwarded to conditional rows and cancels itself when loading changes.
            // Keep one stable row as the task host; reappearing with the same query reuses its page.
            Text("Newest first").font(.caption).foregroundStyle(.secondary)
                .task(id: key) { if loadedKey != key { await load(reset: true) } }
            if failed { Text("Could not load weight records"); Button("Retry") { Task { await load(reset: true) } } }
            else if loadedKey == key && records.isEmpty && !loading { Text("No records in this selection") }
            ForEach(loadedKey == key ? records : []) { record in
                Button { edit(record.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.recordedAt, format: .dateTime.year().month().day().hour().minute())
                        Text(WeightFormatting.kilograms(record.kilograms)).foregroundStyle(.secondary)
                        if record.recordedAt > Date() { Text("Future measurement; excluded from recorded statistics").font(.caption) }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("weight-record-row")
                    .swipeActions { Button("Delete", role: .destructive) { delete(record.id) } }
            }
            if paginated && more && loadedKey == key { Button("Load more") { Task { await load(reset: false) } }.disabled(loading) }
            if loading { ProgressView() }
        }
    }
    @MainActor private func load(reset: Bool) async {
        if reset { records = [] }
        failed = false; loading = true
        let container = context.container, offset = reset ? 0 : records.count, token = key
        let work = Task.detached { try await WeightReviewReader(modelContainer: container).records(start: start, end: end, now: now, offset: offset, limit: limit) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation(); guard token == key else { return }
            if reset { records = result } else { records += result }
            more = result.count == limit; loadedKey = token; loading = false
        } catch is CancellationError {} catch { if !Task.isCancelled && token == key { failed = true; loading = false } }
    }
}

struct WeightAllRecordsView: View {
    let edit: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var snapshot: WeightReviewSnapshot?
    @State private var selected = Date()
    @State private var selectionZoneID: String?
    @State private var refresh = 0
    @State private var failed = false
    @State private var pendingDeletion: UUID?
    @State private var actionError: String?
    var body: some View {
        List {
            Section {
                DatePicker("Select a record day", selection: $selected, displayedComponents: .date).accessibilityIdentifier("weight-history-date")
                HStack {
                    Button("Previous day") { moveDay(-1) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("weight-history-previous-day")
                    Spacer()
                    Button("Next day") { moveDay(1) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("weight-history-next-day")
                }.buttonStyle(.borderless)
                if let snapshot {
                    let components = snapshot.calendar.dateComponents([.year, .month], from: selected)
                    Text("Recorded days in this month").font(.headline)
                    ForEach(snapshot.daily.filter { snapshot.calendar.dateComponents([.year, .month], from: $0.day) == components }) { day in
                        Button { selected = day.day } label: {
                            LabeledContent(day.day.formatted(date: .abbreviated, time: .omitted), value: String(localized: "\(day.observations) measurements"))
                        }.accessibilityIdentifier("weight-history-day-\(HabitLocalDay(date: day.day, timeZone: snapshot.calendar.timeZone).description)")
                    }
                }
                if failed { Text("Could not load weight records"); Button("Retry") { refresh += 1 } }
                if let actionError { Text(actionError).foregroundStyle(.red) }
            }
            if let snapshot {
                let day = snapshot.calendar.startOfDay(for: selected)
                Section("Selected day") {
                    WeightMeasurementPage(start: day, end: snapshot.calendar.date(byAdding: .day, value: 1, to: day).map { snapshot.calendar.startOfDay(for: $0) }, now: Date.distantFuture, refresh: refresh,
                        paginated: true, edit: edit, delete: { pendingDeletion = $0 })
                }
            }
        }.navigationTitle("All Weight Records")
            .confirmationDialog("Delete this weight record?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("Delete Weight Record", role: .destructive) {
                    guard let id = pendingDeletion else { return }
                    do {
                        let read = ModelContext(context.container)
                        guard let record = try read.fetch(FetchDescriptor<WeightRecord>(predicate: #Predicate { $0.id == id })).first else { throw WeightValidationError.missingRecord }
                        try WeightRecordService(context: read).delete(record)
                        pendingDeletion = nil; actionError = nil; refresh += 1
                    } catch { actionError = String(localized: "The weight record was not deleted.") }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
            .onAppear { refresh += 1 }
            .onChange(of:phase) {_,value in if value == .active {refresh += 1}}
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in refresh += 1 }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh += 1 }
            .task(id: refresh) {
                let container = context.container
                let work = Task.detached { try await WeightReviewReader(modelContainer: container).snapshot(now: Date()) }
                do {
                    let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                    try Task.checkCancellation()
                    selected=WeightReviewSelection.retainedDay(selected,previousZoneID:selectionZoneID,calendar:result.calendar) ?? result.asOfDay
                    selectionZoneID=result.calendar.timeZone.identifier
                    snapshot = result; failed = false
                } catch is CancellationError {} catch { if !Task.isCancelled { snapshot = nil; failed = true } }
            }
    }
    private func moveDay(_ offset: Int) {
        let calendar = snapshot?.calendar ?? Calendar(identifier: .gregorian)
        if let day = calendar.date(byAdding: .day, value: offset, to: selected) { selected = day }
    }

}

struct WeightEditorView: View {
    let record: WeightRecord?
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isWeightFocused: Bool
    @State private var didRequestFocus = false
    @State private var previous: WeightMeasurement?
    @State private var weightText: String
    @State private var recordedAt: Date
    @State private var errorMessage: String?

    init(record: WeightRecord?, didSave: @escaping () -> Void) {
        self.record = record
        self.didSave = didSave
        _weightText = State(initialValue: record.map {
            $0.weightKilograms.formatted(.number.precision(.fractionLength(0...2)))
        } ?? "")
        _recordedAt = State(initialValue: record?.recordedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Weight (kg)", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($isWeightFocused)
                        .accessibilityIdentifier("weight-editor-value")
                    if record == nil, let previous {
                        LabeledContent("Previous Weight") {
                            VStack(alignment: .trailing) {
                                Text(verbatim: WeightFormatting.kilograms(previous.kilograms))
                                Text(previous.recordedAt, format: .dateTime.year().month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    DatePicker("Date", selection: $recordedAt, displayedComponents: .date)
                        .accessibilityIdentifier("weight-editor-date")
                } footer: {
                    Text("Enter a weight greater than 0 and no more than 1,000 kg.")
                }
            }
            .navigationTitle(record == nil ? "Record Weight" : "Edit Weight")
            .task {
                guard record == nil, !didRequestFocus else { return }
                didRequestFocus = true
                let container = modelContext.container
                previous = try? await WeightReviewReader(modelContainer: container).records(now: Date(), limit: 1).first
                await Task.yield()
                isWeightFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isWeightFocused {
                        Button { isWeightFocused = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Done").accessibilityIdentifier("weight-editor-dismiss-keyboard")
                    }
                    Button("Save") { save() }
                        .accessibilityIdentifier("weight-editor-save")
                }
            }
            .alert("Could Not Save Weight", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            let kilograms = try WeightRules.kilograms(from: weightText)
            let service = WeightRecordService(context: modelContext)
            if let record {
                try service.update(
                    record,
                    weightKilograms: kilograms,
                    recordedAt: recordedAt
                )
            } else {
                _ = try service.create(
                    weightKilograms: kilograms,
                    recordedAt: recordedAt
                )
            }
            didSave()
            dismiss()
        } catch WeightValidationError.invalidWeight {
            errorMessage = String(localized: "Enter a valid weight in kilograms.")
        } catch {
            errorMessage = String(localized: "The weight record was not saved.")
        }
    }
}

extension BMIReference {
    var label: String {self == .china ? String(localized:"China adult reference") : String(localized:"WHO adult reference")}
}
extension BMICategory {
    var label: String {
        switch self {
        case .low: return String(localized:"Underweight reference range")
        case .usual: return String(localized:"Usual adult reference range")
        case .elevated: return String(localized:"Overweight reference range")
        case .high: return String(localized:"Obesity reference range")
        }
    }
}
private struct WeightBMISection: View {
    let measurement: WeightMeasurement?
    let historical: Bool
    @Environment(\.modelContext) private var context
    @State private var preference=BodyReferencePreference(reference:.china)
    @State private var error: String?
    var body: some View {
        Section("BMI (optional)") {
            if let error {Text(error).foregroundStyle(.red);Button("Retry") {load()}}
            else {
                if let height=preference.heightCentimeters {
                    Text("Current height: \(height.formatted(.number.precision(.fractionLength(0...2)))) cm").accessibilityIdentifier("bmi-height")
                    if let measurement,let bmi=BMICalculation.value(kilograms:measurement.kilograms,centimeters:height),let category=BMICalculation.category(bmi,reference:preference.reference) {
                        LabeledContent("BMI",value:bmi.formatted(.number.precision(.fractionLength(1)))).accessibilityIdentifier("bmi-value")
                        Text(category.label).accessibilityIdentifier("bmi-category")
                        if let boundary=BMICalculation.boundaryHint(bmi,reference:preference.reference) {
                            Text("The unrounded BMI is below \(boundary.formatted(.number.precision(.fractionLength(1)))). The displayed value is rounded.").font(.caption)
                        }
                        Text(measurement.recordedAt,format:.dateTime.year().month().day()).font(.caption)
                        if historical {Text("Calculated from this historical weight using your current height.").font(.caption)}
                    } else {Text("Add a weight measurement to calculate BMI.")}
                } else {Text("Add optional height to see BMI. Weight recording works without it.")}
                Text(preference.reference.label).font(.subheadline)
                NavigationLink {BodyReferenceEditor(preference:preference)} label: {
                    Text(preference.heightCentimeters == nil ? "Set height (optional)" : "Edit or clear height")
                }.accessibilityIdentifier("bmi-edit")
            }
            DisclosureGroup("BMI reference and limits") {
                Text("General adult screening reference, not a diagnosis. These ranges do not apply directly to children or pregnancy. Muscle mass and older age also affect interpretation.").font(.caption)
                ForEach(BMIReference.allCases,id:\.self) { reference in
                    VStack(alignment:.leading,spacing:4) {
                        Text(reference.label).font(.headline)
                        let limits=reference.thresholds
                        Text("Underweight: <18.5")
                        Text("Usual adult range: ≥18.5 and <\(limits[1].formatted(.number.precision(.fractionLength(0))))")
                        Text("Overweight reference: ≥\(limits[1].formatted(.number.precision(.fractionLength(0)))) and <\(limits[2].formatted(.number.precision(.fractionLength(0))))")
                        Text("Obesity reference: ≥\(limits[2].formatted(.number.precision(.fractionLength(0))))")
                    }.font(.caption)
                }
                Text("Observe changes over time, keep regular meals and activity, and consult a qualified professional if you have concerns.").font(.caption)
                Link("China: Weight Management Guideline (2024)",destination:URL(string:"https://www.nhc.gov.cn/ylyjs/zcwj/202412/75cb79c171c94def9e768193e65484f7.shtml")!)
                Link("China: Core Knowledge (2024)",destination:URL(string:"https://www.nhc.gov.cn/cms-search/downFiles/5e20de34c0fe45bb9fcac0636b21ad98.pdf")!)
                Link("WHO adult BMI definitions",destination:URL(string:"https://www.who.int/data/nutrition/nlis/info/malnutrition-in-women")!)
                Link("CDC: About BMI",destination:URL(string:"https://www.cdc.gov/bmi/about/")!)
            }
        }.onAppear {load()}
        .onReceive(NotificationCenter.default.publisher(for:ModelContext.didSave).receive(on:RunLoop.main)) {_ in load()}
    }
    private func load() {
        do {preference=try BodyReferenceService.read(context.container);error=nil}
        catch {self.error=error.localizedDescription}
    }
}
private struct BodyReferenceEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var height: String
    @State private var reference: BMIReference
    @State private var error: String?
    @FocusState private var focused: Bool
    init(preference: BodyReferencePreference) {
        _height=State(initialValue:preference.heightCentimeters.map {String($0)} ?? "")
        _reference=State(initialValue:preference.reference)
    }
    var body: some View {
        Form {
            Section("Optional height") {
                TextField("Height (cm)",text:$height).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("bmi-height-input")
                Text("Input range: 50–300 cm. Leave blank to remove height.").font(.caption)
                Picker("Adult reference",selection:$reference) {ForEach(BMIReference.allCases,id:\.self) {Text($0.label).tag($0)}}.accessibilityIdentifier("bmi-reference")
                Text("Height is optional and saved on this device with your backup settings.").font(.caption)
            }
            if let error {Text(error).foregroundStyle(.red).accessibilityIdentifier("bmi-error")}
            Button("Save") {save(clear:false)}.accessibilityIdentifier("bmi-save")
            Button("Clear height",role:.destructive) {save(clear:true)}.accessibilityIdentifier("bmi-clear")
        }.navigationTitle("BMI settings")
        .toolbar {
            ToolbarItem(placement:.cancellationAction) {Button("Cancel") {dismiss()}}
            ToolbarItem(placement:.confirmationAction) {if focused {
                Button {focused=false} label: {Image(systemName:"keyboard.chevron.compact.down").frame(minWidth:44,minHeight:44)}.accessibilityLabel("Done")
            }}
        }
    }
    private func save(clear: Bool) {
        do {
            let value=try clear ? nil : BodyReferenceService.height(from:height)
            try BodyReferenceService.save(.init(heightCentimeters:value,reference:reference),container:context.container)
            dismiss()
        } catch {self.error=error.localizedDescription}
    }
}
