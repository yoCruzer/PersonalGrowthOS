import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

private struct NetWorthPrivacy: ViewModifier {
    var editing = false
    @Environment(\.scenePhase) private var phase
    @AppStorage("netWorthAmountsHidden") private var hidden = false
    func body(content: Content) -> some View {
        Group {
            if editing && hidden {
                VStack(spacing: 20) { Label("Amounts hidden", systemImage: "eye.slash"); Button("Show amounts") { hidden = false } }
            } else { content }
        }.opacity(phase == .active ? 1 : 0).accessibilityHidden(phase != .active)
            .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay { Label("Financial information hidden", systemImage: "eye.slash").foregroundStyle(.secondary) } } }
            .onChange(of: phase) { _, value in if value != .active { hidden = true } }
    }
}
private extension View { func netWorthPrivacy(editing: Bool = false) -> some View { modifier(NetWorthPrivacy(editing: editing)) } }

struct NetWorthHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("netWorthAmountsHidden") private var hidden = false
    @State private var ledger = NetWorthLedger(items: [], snapshots: [])
    @State private var error: String?
    @State private var editing: NetWorthSnapshotValue?
    @State private var backdate = false
    @State private var date = Date()
    @State private var debtTrend = false
    @State private var csv: NetWorthCSVDocument?
    @State private var exporting = false
    @State private var exportWarning = false

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.secondary); Button("Retry", action: refresh) } }
            if let latest = ledger.latest {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Net worth · CNY").font(.subheadline).foregroundStyle(.secondary)
                        Text(readableAmount(amount((try? latest.totals())?.net))).font(typeSize.isAccessibilitySize ? .title : .largeTitle).fontWeight(.semibold)
                            .accessibilityLabel(amount((try? latest.totals())?.net))
                            .monospacedDigit().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("net-worth-main")
                        Text(latest.day).font(.subheadline).foregroundStyle(.secondary)
                        if latest.scopeAdjusted { Label("Statistical scope adjusted", systemImage: "info.circle").font(.footnote) }
                        comparison(latest)
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 24) { subtotal(latest, .asset); Spacer(); subtotal(latest, .liability) }
                            VStack(alignment: .leading, spacing: 12) { subtotal(latest, .asset); subtotal(latest, .liability) }
                        }
                    }.padding(.vertical, 12)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("A clear view of what you have").font(.title2.bold())
                        Text("Add a few balances, confirm the scope, and keep your first snapshot. You can fill in the rest later.").foregroundStyle(.secondary)
                        Text("Renminbi · Manual balances · Stored on this device").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
            }
            Section {
                Button { start(day: ImportantCivilDay(Date()).identifier) } label: {
                    Label(ledger.draft == nil ? "Record a snapshot" : "Continue inventory", systemImage: "square.and.pencil")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).listRowBackground(Color.clear).accessibilityIdentifier("net-worth-record")
            }
            if !ledger.history.isEmpty {
                Section {
                    Picker("Trend", selection: $debtTrend) { Text("Net worth").tag(false); Text("Liabilities").tag(true) }.pickerStyle(.segmented)
                    if hidden { Text("Amounts hidden").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100) }
                    else { trend }
                    NavigationLink("All snapshots and values") { history }
                } header: { Text("Over time") } footer: { Text("Only recorded dates are shown. Missing values and changes in scope break the line.") }
                if let latest = ledger.latest {
                    Section {
                        if hidden { Text("Amounts hidden").foregroundStyle(.secondary) }
                        else { composition(latest) }
                    } header: { Text("Asset composition") } footer: { Text(latest.day + " · " + String(localized: "Latest confirmed snapshot")) }
                }
            }
            Section {
                NavigationLink { NetWorthItemsView() } label: { Label("Balance items", systemImage: "list.bullet") }
                NavigationLink { history } label: { Label("Snapshot history", systemImage: "clock") }
                Button("Record a past date") { backdate = true }
                Button("Export snapshots as CSV") { exportWarning = true }.disabled(ledger.history.isEmpty)
            } footer: { Text("Hidden amounts are a screen privacy feature. CSV and full backups are not encrypted.") }
        }
        .navigationTitle("Household net worth").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye") }.accessibilityLabel(hidden ? "Show amounts" : "Hide amounts").accessibilityIdentifier("net-worth-privacy") } }
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PGOSUITesting"), ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthFixture") {
                do { try NetWorthUITestFixture.seed(context) } catch { self.error = error.localizedDescription }
            }
#endif
            refresh()
        }
        .sheet(item: $editing, onDismiss: refresh) { value in NavigationStack { NetWorthEditorView(initial: value) } }
        .sheet(isPresented: $backdate) {
            NavigationStack { Form { DatePicker("Snapshot date", selection: $date, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical) }
                .navigationTitle("Record a past date").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { backdate = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Continue") { backdate = false; start(day: ImportantCivilDay(date).identifier, resumeExistingDraft: false) } }
                } }.presentationDetents([.large]).netWorthPrivacy()
        }
        .confirmationDialog("Export unencrypted financial information?", isPresented: $exportWarning, titleVisibility: .visible) {
            Button("Export CSV") { do { csv = .init(text: try NetWorthCSV.make(ledger)); exporting = true } catch { self.error = error.localizedDescription } }
        } message: { Text("The file contains names, notes and amounts even when amounts are hidden. Choose a safe destination.") }
        .fileExporter(isPresented: $exporting, document: csv, contentType: .commaSeparatedText, defaultFilename: "NetWorth") { result in if case .failure(let error) = result { self.error = error.localizedDescription } }
        .netWorthPrivacy()
    }
    private func amount(_ cents: Int64?) -> String { hidden ? "••••" : cents.map(NetWorthMoney.display) ?? String(localized: "Net worth incomplete") }
    private func readableAmount(_ value: String) -> String {
        guard typeSize.isAccessibilitySize, value.count > 8,
              let decimal = value.range(of: Locale.current.decimalSeparator ?? ".", options: .backwards) else { return value }
        // Keep the fractional part together at large accessibility sizes, without shrinking type.
        return String(value[..<decimal.lowerBound]) + "\n" + String(value[decimal.lowerBound...])
    }
    private func subtotal(_ snapshot: NetWorthSnapshotValue, _ side: NetWorthSide) -> some View {
        let totals = try? snapshot.totals()
        let complete = side == .asset ? totals?.assetsComplete : totals?.liabilitiesComplete
        return VStack(alignment: .leading, spacing: 4) {
            Text(side.title + (complete == true ? "" : " · " + String(localized: "Known subtotal"))).font(.caption).foregroundStyle(.secondary)
            Text(readableAmount(amount(side == .asset ? totals?.assets : totals?.liabilities))).font(.body.weight(.medium)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(amount(side == .asset ? totals?.assets : totals?.liabilities))
        }
    }
    @ViewBuilder private func comparison(_ latest: NetWorthSnapshotValue) -> some View {
        if !hidden, ledger.history.count > 1 {
            let previous = ledger.history[ledger.history.count - 2]
            if let a = try? latest.totals().net, let b = try? previous.totals().net {
                VStack(alignment: .leading, spacing: 3) {
                    Text((a == b ? String(localized: "No change since last snapshot") : a > b ? String(localized: "Increase since last snapshot") : String(localized: "Decrease since last snapshot")) + (a == b ? "" : " " + NetWorthMoney.display(abs(a - b)))).monospacedDigit()
                    Text(previous.day + " → " + latest.day).foregroundStyle(.secondary)
                    if latest.scopeAdjusted || previous.scopeAdjusted { Text("Scope changed; this difference is not a return.").foregroundStyle(.secondary) }
                }.font(.footnote)
            } else { Text("Complete both snapshots to compare.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private var trend: some View {
        let points = NetWorthTrend.points(ledger.history, liabilities: debtTrend)
        return Chart(points) { point in
            if let value = point.cents {
                PointMark(x: .value("Date", point.date), y: .value("CNY", Double(value) / 100)).foregroundStyle(Color.accentColor)
                    .symbol(point.adjusted ? .diamond : .circle)
                    .annotation(position: .top) { if point.adjusted { Text("Scope adjusted").font(.caption2).foregroundStyle(.secondary) } }
                LineMark(x: .value("Date", point.date), y: .value("CNY", Double(value) / 100), series: .value("Segment", point.segment)).foregroundStyle(Color.accentColor)
            }
        }.frame(height: 180).chartYAxis { AxisMarks(position: .leading) }
            .accessibilityLabel(debtTrend ? "Liability trend" : "Net worth trend").accessibilityIdentifier("net-worth-trend")
            .chartOverlay { proxy in GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                    guard let frame = proxy.plotFrame,
                          let day: Date = proxy.value(atX: location.x - geometry[frame].origin.x),
                          let nearest = points.filter({ $0.cents != nil }).min(by: { abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day)) }),
                          let snapshot = ledger.history.first(where: { $0.id == nearest.id }) else { return }
                    selectedSnapshot = snapshot
                }
            } }.sheet(item: $selectedSnapshot, onDismiss: refresh) { snapshot in NavigationStack {
                NetWorthDetailView(snapshot: snapshot).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selectedSnapshot = nil } } }
            } }
    }
    @State private var selectedSnapshot: NetWorthSnapshotValue?
    @ViewBuilder private func composition(_ snapshot: NetWorthSnapshotValue) -> some View {
        let total = try? snapshot.totals()
        ForEach(NetWorthCategory.allCases.filter { $0.side == .asset }, id: \.self) { category in
            let rows = snapshot.items.filter { $0.included && $0.category == category }
            if !rows.isEmpty {
                let sum = (try? NetWorthMoney.sum(rows.compactMap(\.cents))) ?? 0
                NavigationLink { NetWorthDetailView(snapshot: snapshot, category: category) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.title).foregroundStyle(.primary)
                        Text(rows.allSatisfy({ $0.cents == nil }) ? String(localized: "Unknown") : NetWorthMoney.display(sum)).monospacedDigit().font(.subheadline)
                        if total?.assetsComplete == true, let assets = total?.assets, assets > 0 {
                            ProgressView(value: Double(sum) / Double(assets)).accessibilityLabel(category.title)
                            Text((Double(sum) / Double(assets)).formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundStyle(.secondary)
                        } else { Text("Known subtotal").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("net-worth-category-\(category.rawValue)")
            }
        }
    }
    private var history: some View {
        List {
            if ledger.history.isEmpty { Text("No confirmed snapshots yet").foregroundStyle(.secondary) }
            ForEach(ledger.history.reversed()) { snapshot in
                NavigationLink { NetWorthDetailView(snapshot: snapshot) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.day).font(.headline)
                        Text(amount((try? snapshot.totals())?.net)).monospacedDigit()
                        if snapshot.scopeAdjusted { Text("Statistical scope adjusted").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
        }.navigationTitle("Snapshot history").onAppear(perform: refresh).netWorthPrivacy()
    }
    private func refresh() { do { ledger = try NetWorthService(context: context).read(); error = nil } catch { self.error = error.localizedDescription } }
    private func start(day: String, resumeExistingDraft: Bool = true) {
        do { editing = try NetWorthService(context: context).begin(day: day, resumeExistingDraft: resumeExistingDraft); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct NetWorthTrend {
    struct Point: Identifiable { var id: UUID; var date: Date; var cents: Int64?; var segment: Int; var adjusted: Bool }
    static func points(_ snapshots: [NetWorthSnapshotValue], liabilities: Bool = false) -> [Point] {
        var segment = 0; var previousAdjusted = false
        return snapshots.filter(\.confirmed).sorted { $0.day < $1.day }.compactMap { snapshot in
            guard let date = ImportantCivilDay(identifier: snapshot.day)?.date else { return nil }
            let totals = try? snapshot.totals()
            let value = liabilities ? (totals?.liabilitiesComplete == true ? totals?.liabilities : nil) : totals?.net
            if value == nil || snapshot.scopeAdjusted || previousAdjusted { segment += 1 }
            previousAdjusted = snapshot.scopeAdjusted
            let point = Point(id: snapshot.id, date: date, cents: value, segment: segment, adjusted: snapshot.scopeAdjusted)
            if value == nil { segment += 1 }
            return point
        }
    }
}

private struct NetWorthCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct NetWorthEditorView: View {
    let initial: NetWorthSnapshotValue
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NetWorthSnapshotValue
    @State private var error: String?
    @State private var addItem = false
    @State private var discard = false
    @State private var injectedConfirmFailure = false
    @FocusState private var focused: UUID?
    init(initial: NetWorthSnapshotValue) { self.initial = initial; _draft = State(initialValue: initial) }
    var body: some View {
        Form {
            Section {
                Text(draft.day).font(.headline)
                Text("Update what changed, then carry forward the remaining balances. Original amount dates are kept.").font(.subheadline).foregroundStyle(.secondary)
                Button("Carry forward remaining balances") { draft.carryRemaining(); persist() }.accessibilityIdentifier("net-worth-carry")
            }
            if let error { Section { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("net-worth-error"); Button("Retry saving draft") { persist() } } }
            ForEach(NetWorthSide.allCases, id: \.self) { side in
                Section(side.title) {
                    ForEach(draft.items.indices.filter { draft.items[$0].side == side }, id: \.self) { index in row(index) }
                    Toggle(side == .asset ? "Asset scope confirmed" : "Liability scope confirmed", isOn: scopeBinding(side))
                }
            }
            Section { Button("Add balance item") { addItem = true }.accessibilityIdentifier("net-worth-add-item") }
            Section {
                Toggle("Statistical scope adjusted", isOn: $draft.scopeAdjusted).onChange(of: draft.scopeAdjusted) { _, _ in persist() }
                Text("Mark this when adding previously omitted assets or changing the family's scope, not for transfers between accounts.").font(.footnote).foregroundStyle(.secondary)
                TextField("Snapshot note", text: $draft.note, axis: .vertical).onChange(of: draft.note) { _, _ in persist() }
            }
            Section {
                Button("Save confirmed snapshot") { save() }.font(.headline).accessibilityIdentifier("net-worth-confirm")
                Button("Discard draft", role: .destructive) { discard = true }
            } footer: { Text("Unknown balances and unconfirmed scope keep net worth incomplete. A confirmed empty side means zero.") }
        }
        .navigationTitle("Inventory · CNY").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Continue later") { if persist() { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { focused = nil; save() } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } }
        }
        .sheet(isPresented: $addItem) { NavigationStack { NetWorthItemEditor(value: .init(name: "", side: .asset, category: .cash), recordsAmount: true, day: draft.day) { item, row in
            if !draft.items.contains(where: { $0.id == item.id }) { draft.items.append(row ?? NetWorthSnapshotItem(item)); persist() }
        } } }
        .confirmationDialog("Discard this draft?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { do { try NetWorthService(context: context).delete(id: draft.id, revision: draft.revision); dismiss() } catch { self.error = error.localizedDescription } }
        }.netWorthPrivacy(editing: true)
    }
    private func scopeBinding(_ side: NetWorthSide) -> Binding<Bool> {
        Binding(get: { side == .asset ? draft.assetsConfirmed : draft.liabilitiesConfirmed }, set: { value in
            if side == .asset { draft.assetsConfirmed = value } else { draft.liabilitiesConfirmed = value }; persist()
        })
    }
    private func row(_ index: Int) -> some View {
        let row = draft.items[index]
        return VStack(alignment: .leading, spacing: 8) {
            Text(row.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(row.category.title).font(.caption).foregroundStyle(.secondary)
            if let cents = row.cents, let day = row.amountDay {
                Text(String(localized: "Previous amount") + " " + NetWorthMoney.display(cents) + " · " + day).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Toggle("Include in this snapshot", isOn: Binding(get: { draft.items[index].included }, set: { draft.items[index].included = $0; persist() }))
            if row.included {
                TextField("New amount · blank means unknown", text: Binding(get: { draft.items[index].inputText ?? "" }, set: { draft.items[index].inputText = $0; persist() }))
                    .keyboardType(.decimalPad).focused($focused, equals: row.id).monospacedDigit().accessibilityIdentifier("net-worth-amount-\(index)")
                Text(row.pending ? String(localized: "Awaiting confirmation") : row.state.title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Use previous") { draft.items[index].inputText = nil; draft.items[index].pending = false; draft.items[index].state = row.cents == nil ? .unknown : .carriedForward; persist() }.disabled(row.cents == nil)
                    Spacer()
                    Button("Unknown") { draft.items[index].cents = nil; draft.items[index].amountDay = nil; draft.items[index].state = .unknown; draft.items[index].pending = false; draft.items[index].inputText = nil; persist() }
                }.buttonStyle(.borderless)
                Toggle("Estimated", isOn: Binding(get: { draft.items[index].state == .estimated }, set: { draft.items[index].state = $0 ? .estimated : (row.cents == nil ? .unknown : .entered); if draft.items[index].inputText == nil { draft.items[index].inputText = row.cents.map(NetWorthMoney.decimal) ?? "" }; persist() }))
            }
        }.padding(.vertical, 6)
    }
    @discardableResult private func persist() -> Bool {
        do { draft = try NetWorthService(context: context).saveDraft(draft); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func save() {
        guard persist() else { return }
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PGOSUITesting"), ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthConfirmFailure"), !injectedConfirmFailure {
                injectedConfirmFailure = true
                _ = try NetWorthService(context: context, commit: { _ in throw CocoaError(.fileWriteOutOfSpace) }).confirm(draft)
            } else { _ = try NetWorthService(context: context).confirm(draft) }
#else
            _ = try NetWorthService(context: context).confirm(draft)
#endif
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct NetWorthItemEditor: View {
    @State var value: NetWorthItemValue
    var recordsAmount = false
    var day = ImportantCivilDay(Date()).identifier
    var saved: (NetWorthItemValue, NetWorthSnapshotItem?) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var estimated = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $value.name).accessibilityIdentifier("net-worth-item-name")
                Picker("Side", selection: $value.side) { ForEach(NetWorthSide.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .onChange(of: value.side) { _, side in value.category = side == .asset ? .cash : .mortgage }
                Picker("Category", selection: $value.category) { ForEach(NetWorthCategory.allCases.filter { $0.side == value.side }, id: \.self) { Text($0.title).tag($0) } }
                Text(value.category.guidance).font(.footnote).foregroundStyle(.secondary)
            }
            if recordsAmount {
                Section("Balance · CNY") {
                    TextField("Amount · blank means unknown", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("net-worth-initial-amount")
                    Toggle("Estimated", isOn: $estimated)
                }
            }
            Section {
                TextField("Ownership label (optional)", text: $value.ownership)
                TextField("Short note (optional)", text: $value.note, axis: .vertical)
            } footer: { Text("Do not enter account numbers, addresses or identity documents.") }
            if let error { Text(error).foregroundStyle(.secondary) }
        }.navigationTitle("Balance item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do {
                        var row = NetWorthSnapshotItem(value)
                        if recordsAmount { try row.enter(amountText, day: day, estimated: estimated) }
                        let result = try NetWorthService(context: context).saveItem(value)
                        saved(result, recordsAmount ? row : nil); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.netWorthPrivacy(editing: true)
    }
}

struct NetWorthItemsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("netWorthAmountsHidden") private var hidden = false
    @State private var ledger = NetWorthLedger(items: [], snapshots: [])
    @State private var editing: NetWorthItemValue?
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error); Button("Retry", action: refresh) }
            ForEach(NetWorthSide.allCases, id: \.self) { side in
                Section(side.title) {
                    ForEach(ledger.items.filter { $0.side == side }.sorted { $0.name < $1.name }) { item in
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).foregroundStyle(.primary)
                                Text(item.category.title + (item.archived ? " · " + String(localized: "Archived") : "")).font(.caption).foregroundStyle(.primary)
                                if let row = ledger.history.reversed().compactMap({ $0.items.first { $0.id == item.id } }).first {
                                    Text(hidden ? "••••" : ((row.cents.map(NetWorthMoney.display) ?? String(localized: "Unknown")) + " · " + (row.amountDay ?? "—"))).monospacedDigit().font(.subheadline).foregroundStyle(.primary)
                                }
                            }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).swipeActions {
                            Button(item.archived ? "Restore" : "Archive") {
                                var changed = item; changed.archived.toggle()
                                do { _ = try NetWorthService(context: context).saveItem(changed); refresh() } catch { self.error = error.localizedDescription }
                            }.tint(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Balance items")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { editing = .init(name: "", side: .asset, category: .cash) } } }
            .onAppear(perform: refresh)
            .sheet(item: $editing, onDismiss: refresh) { value in NavigationStack { NetWorthItemEditor(value: value) { _, _ in } } }
            .netWorthPrivacy()
    }
    private func refresh() { do { ledger = try NetWorthService(context: context).read(); error = nil } catch { self.error = error.localizedDescription } }
}

struct NetWorthDetailView: View {
    @State var snapshot: NetWorthSnapshotValue
    var category: NetWorthCategory? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("netWorthAmountsHidden") private var hidden = false
    @State private var editing: NetWorthSnapshotValue?
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text(snapshot.day).font(.title2.bold())
                Text(hidden ? "••••" : ((try? snapshot.totals())?.net.map(NetWorthMoney.display) ?? String(localized: "Net worth incomplete"))).font(.title).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Text(snapshot.assetsConfirmed ? String(localized: "Asset scope confirmed") : String(localized: "Asset scope not confirmed")).font(.footnote).foregroundStyle(.secondary)
                Text(snapshot.liabilitiesConfirmed ? String(localized: "Liability scope confirmed") : String(localized: "Liability scope not confirmed")).font(.footnote).foregroundStyle(.secondary)
                if snapshot.scopeAdjusted { Text("Statistical scope adjusted") }
                if !snapshot.note.isEmpty { Text(snapshot.note) }
            } header: { Text("Net worth · CNY") }
            ForEach(NetWorthSide.allCases, id: \.self) { side in
                Section(side.title) {
                    ForEach(snapshot.items.filter { $0.side == side && (category == nil || $0.category == category) }) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name).font(.headline)
                            Text(row.category.title).font(.caption).foregroundStyle(.secondary)
                            Text(hidden ? "••••" : row.cents.map(NetWorthMoney.display) ?? String(localized: "Unknown")).monospacedDigit()
                            Text(row.state.title + " · " + (row.amountDay ?? "—")).font(.caption).foregroundStyle(.secondary)
                            if !row.included { Text("Not included").font(.caption) }
                            if !row.ownership.isEmpty { Text(row.ownership).font(.caption) }
                            if !row.note.isEmpty { Text(row.note).font(.footnote) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
            Section {
                Button("Correct snapshot") { do { editing = try NetWorthService(context: context).begin(day: snapshot.day, editingID: snapshot.id) } catch { self.error = error.localizedDescription } }
                Button("Delete snapshot", role: .destructive) { deleting = true }
            }
        }.navigationTitle("Snapshot details").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing, onDismiss: reload) { value in NavigationStack { NetWorthEditorView(initial: value) } }
            .confirmationDialog("Delete this historical snapshot?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete snapshot", role: .destructive) { do { try NetWorthService(context: context).delete(id: snapshot.id, revision: snapshot.revision); dismiss() } catch { self.error = error.localizedDescription } }
            }.netWorthPrivacy()
    }
    private func reload() { do { if let value = try NetWorthService(context: context).read().history.first(where: { $0.id == snapshot.id }) { snapshot = value } } catch { self.error = error.localizedDescription } }
}

#if DEBUG
// Explicit UI-testing launch only; all values are synthetic and use production services.
@MainActor enum NetWorthUITestFixture {
    static func seed(_ context: ModelContext) throws {
        let service = NetWorthService(context: context)
        guard try service.read().snapshots.isEmpty else { return }
        UserDefaults.standard.set(false, forKey: "netWorthAmountsHidden")
        let negative = ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthNegative")
        let oneItem = ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthOneItem")
        let categories: [NetWorthCategory] = negative ? [.credit] : oneItem ? [.cash] : [.cash, .investments, .property, .valuables, .mortgage, .credit]
        let names = ["测试银行存款", "测试投资账户市值", "测试住房估值", "测试车辆估值", "测试房贷余额", "测试信用卡未还"]
        for i in categories.indices { _ = try service.saveItem(.init(name: negative ? "测试家庭共同承担的长期信用卡未还余额（长名称）" : names[i], side: categories[i].side, category: categories[i])) }
        let dates = ["2025-11-30","2025-12-31","2026-01-31","2026-02-28","2026-03-31","2026-04-30","2026-05-31","2026-06-30","2026-07-31","2026-08-31","2026-09-30","2026-10-31"]
        let single = ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthSingle")
        for (index, day) in (single ? [dates.last!] : dates).enumerated() {
            var draft = try service.begin(day: day)
            for i in draft.items.indices {
                let base: Int64
                switch draft.items[i].category {
                case .cash: base = 10000000 + Int64(index) * 100000
                case .investments: base = 20000000 + Int64(index) * 200000
                case .property: base = 200000000
                case .valuables: base = 10000000
                case .mortgage: base = 100000000 - Int64(index) * 100000
                default: base = 1000000
                }
                try draft.items[i].enter(NetWorthMoney.decimal(base), day: day, estimated: draft.items[i].category == .property)
            }
            draft.assetsConfirmed = true; draft.liabilitiesConfirmed = true
            if ProcessInfo.processInfo.arguments.contains("-PGOSNetWorthPartial"), let i = draft.items.firstIndex(where: { $0.category == .mortgage }) { try draft.items[i].enter("", day: day) }
            draft.scopeAdjusted = index == 5
            _ = try service.confirm(service.saveDraft(draft))
        }
    }
}
#endif
