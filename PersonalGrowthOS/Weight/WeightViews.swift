import Charts
import SwiftData
import SwiftUI

enum WeightFormatting {
    static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1...2))) + " kg"
    }
}

struct WeightHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: WeightRecordOrdering.newestFirstSortDescriptors)
    private var queriedRecords: [WeightRecord]
    @State private var isAddingRecord = false
    @State private var editingRecord: WeightRecord?
    @State private var pendingDeletion: WeightRecord?
    @State private var errorMessage: String?

    private var records: [WeightRecord] {
        WeightRecordOrdering.newestFirst(queriedRecords)
    }

    private var trend: WeightTrend? {
        WeightTrend.make(from: records)
    }

    var body: some View {
        List {
            if records.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView {
                            Label("No Weight Records", systemImage: "scalemass")
                        } description: {
                            Text("Add your first weight record to see your latest value and a simple trend.")
                        }
                        .accessibilityIdentifier("weight-empty-state")
                        GrowthEmptyStateAddButton(
                            title: "Add Weight",
                            systemImage: "plus",
                            action: { isAddingRecord = true }
                        )
                        .accessibilityIdentifier("add-weight")
                    }
                } footer: {
                    Text("Weight uses kilograms (kg). This is a personal record, not health advice.")
                }
            } else {
                Section("Latest Weight") {
                    if let latest = records.first {
                        LabeledContent {
                            Text(verbatim: WeightFormatting.kilograms(latest.weightKilograms))
                                .font(.title3.weight(.semibold))
                                .accessibilityIdentifier("weight-latest-value")
                        } label: {
                            Text(latest.recordedAt, format: .dateTime.year().month().day())
                        }
                        if let change = trend?.changeKilograms {
                            Label {
                                Text(verbatim: WeightFormatting.kilograms(abs(change)))
                            } icon: {
                                Image(systemName: change == 0
                                    ? "equal.circle"
                                    : change > 0 ? "arrow.up.right.circle" : "arrow.down.right.circle")
                            }
                            .foregroundStyle(change == 0 ? .secondary : .primary)
                            .accessibilityLabel(
                                "\(String(localized: "Since previous")) \(WeightFormatting.kilograms(change))"
                            )
                        }
                    }
                }

                Section("Trend") {
                    if records.count >= 2 {
                        Chart(WeightRecordOrdering.oldestFirst(records)) { record in
                            LineMark(
                                x: .value("Date", record.recordedAt),
                                y: .value("Weight (kg)", record.weightKilograms)
                            )
                            .interpolationMethod(.linear)
                            PointMark(
                                x: .value("Date", record.recordedAt),
                                y: .value("Weight (kg)", record.weightKilograms)
                            )
                        }
                        .frame(height: 180)
                        .accessibilityLabel("Weight trend")
                        .accessibilityIdentifier("weight-trend-chart")
                    } else {
                        Text("Add at least two records to see a trend.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("History") {
                    ForEach(records) { record in
                        Button {
                            editingRecord = record
                        } label: {
                            HStack {
                                Text(record.recordedAt, format: .dateTime.year().month().day())
                                Spacer()
                                Text(verbatim: WeightFormatting.kilograms(record.weightKilograms))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(record.recordedAt.formatted(date: .abbreviated, time: .omitted)), \(WeightFormatting.kilograms(record.weightKilograms))"
                        )
                        .accessibilityIdentifier("weight-record-row")
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                pendingDeletion = record
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Weight")
        .accessibilityIdentifier("weight-history-view")
        .toolbar {
            if !records.isEmpty {
                Button {
                    isAddingRecord = true
                } label: {
                    Label("Add Weight", systemImage: "plus")
                }
                .accessibilityIdentifier("add-weight")
            }
        }
        .sheet(isPresented: $isAddingRecord) {
            WeightEditorView(record: nil) {
                isAddingRecord = false
            }
        }
        .sheet(item: $editingRecord) { record in
            WeightEditorView(record: record) {
                editingRecord = nil
            }
        }
        .confirmationDialog(
            "Delete this weight record?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Weight Record", role: .destructive) {
                deletePendingRecord()
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        }
        .alert("Could Not Delete Weight", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deletePendingRecord() {
        guard let record = pendingDeletion else { return }
        do {
            try WeightRecordService(context: modelContext).delete(record)
            pendingDeletion = nil
        } catch {
            pendingDeletion = nil
            errorMessage = String(localized: "The weight record was not deleted.")
        }
    }
}

struct WeightEditorView: View {
    let record: WeightRecord?
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isWeightFocused: Bool
    @State private var didRequestFocus = false
    @Query(sort: WeightRecordOrdering.newestFirstSortDescriptors) private var previousRecords: [WeightRecord]
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
                    if record == nil, let previous = WeightRecordOrdering.newestFirst(previousRecords).first(where: { $0.recordedAt <= Date() }) {
                        LabeledContent("Previous Weight") {
                            VStack(alignment: .trailing) {
                                Text(verbatim: WeightFormatting.kilograms(previous.weightKilograms))
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
                await Task.yield()
                isWeightFocused = true
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isWeightFocused = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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
