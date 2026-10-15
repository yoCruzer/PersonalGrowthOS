import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ImportantDaysView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Query private var days: [ImportantDay]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var showArchived = false
    @State private var adding = false
    @AppStorage("ImportantDayHasSavedDay") private var hasSavedDay = false
    @AppStorage("ImportantDayWidgetTipDismissed") private var tipDismissed = false
    @State private var error: String?
    @State private var referenceDate = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var today: ImportantCivilDay { .init(referenceDate) }
    private var visible: [ImportantDay] {
        let q = TextSearchNormalizer.normalize(query)
        return days.filter { $0.isArchived == showArchived && (q.isEmpty || TextSearchNormalizer.normalize($0.title + " " + $0.notes).contains(q)) }.sorted { a, b in
            let ad = (try? a.rule()).flatMap { try? ImportantDayDateEngine.evaluate($0, today: today) }.map { $0.next ?? $0.displayDay }
            let bd = (try? b.rule()).flatMap { try? ImportantDayDateEngine.evaluate($0, today: today) }.map { $0.next ?? $0.displayDay }
            if ad != bd { return (ad ?? today) < (bd ?? today) }; return a.id.uuidString < b.id.uuidString
        }
    }
    private var favorites: [ImportantDay] {
        visible.filter { (try? $0.preferences().favoriteOrder) != nil }.sorted {
            let a = (try? $0.preferences().favoriteOrder) ?? Int.max, b = (try? $1.preferences().favoriteOrder) ?? Int.max
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }
    private var others: [ImportantDay] { visible.filter { day in !favorites.contains { $0.id == day.id } } }
    var body: some View {
        List {
            if hasSavedDay && !tipDismissed {
                Section {
                    Text("You can display a chosen day on your Home Screen. Open its details to authorize and prepare a widget.").font(.subheadline)
                    Button("Dismiss widget tip") { tipDismissed = true }
                }
            }
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Important Days", systemImage: "calendar")
                } description: {
                    Text(query.isEmpty ? String(localized: "A trip to look forward to, a beginning to remember, or an anniversary. Your examples stay yours to create.") : String(localized: "No matching days"))
                } actions: { Button("Add Important Day") { adding = true } }
            }
            if !favorites.isEmpty {
                Section("Frequently viewed") {
                    ForEach(favorites) { row($0) }
                        .onMove { offsets, destination in
                            var order = favorites; order.move(fromOffsets: offsets, toOffset: destination)
                            do { try ImportantDayService(context: context, mediaStore: mediaStore).reorderFavorites(order.map(\.id))
                            } catch { self.error = String(localized: "The day could not be saved. Your changes are still here.") }
                        }
                }
            }
            Section(showArchived ? "Archived days" : "Next dates") {
                ForEach(others.filter { (try? $0.rule()).map { $0.preset == .anniversary || (try? ImportantDayDateEngine.evaluate($0, today: today).next) != nil } ?? false }) { row($0) }
            }
            Section("Past beginnings and plans") {
                ForEach(others.filter { (try? $0.rule()).map { $0.preset != .anniversary && (try? ImportantDayDateEngine.evaluate($0, today: today).next) == nil } ?? true }) { row($0) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in referenceDate = Date() }
        .onChange(of: scenePhase) { _, p in if p == .active { referenceDate = Date() } }
        .navigationTitle("Important Days")
        .searchable(text: $query, prompt: "Day name or note")
        .accessibilityIdentifier("important-days-list")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Important Day").accessibilityIdentifier("important-day-add") }
            ToolbarItem { Menu { Toggle("Show archived days", isOn: $showArchived) } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Day filters") }
            ToolbarItem { EditButton() }
        }
        .sheet(isPresented: $adding) { ImportantDayEditorView(mediaStore: mediaStore) }
        .alert("Important Day Update", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func row(_ day: ImportantDay) -> some View {
        NavigationLink { ImportantDayDetailView(dayID: day.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: { ImportantDayRow(day: day, today: today) }
    }
}

struct ImportantDayRow: View {
    let day: ImportantDay
    var today = ImportantCivilDay(Date())
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(day.title, systemImage: "calendar").lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let rule = try? day.rule() { Text(rule.distanceDescription(today: today)).font(.subheadline).foregroundStyle(.secondary) }
            if day.isArchived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("important-day-row-\(day.id)")
    }
}

struct ImportantDayDetailView: View {
    let dayID: UUID
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var days: [ImportantDay]
    @Query private var links: [ImportantDayEntryLink]
    @Query private var entries: [Entry]
    @Query private var todoLinks: [ImportantDayTodoLink]
    @Query private var tasks: [TodoTask]
    @Query private var covers: [ImportantDayCover]
    @State private var editing = false
    @State private var writing = false
    @State private var linking = false
    @State private var addingTodo = false
    @State private var deleting = false
    @State private var help = false
    @State private var error: String?
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Environment(ImportantDayWidgetPublisher.self) private var widgetPublisher
    @State private var occurrenceFilter = "all"
    @State private var explicitOccurrence = false
    @State private var occurrenceYear: Int?
    @State private var referenceDate = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var day: ImportantDay? { days.first { $0.id == dayID } }
    private var today: ImportantCivilDay { .init(referenceDate) }
    private var relatedLinks: [ImportantDayEntryLink] { links.filter { $0.dayID == dayID } }
    private var periods: [String] { Set(relatedLinks.compactMap(\.occurrenceIdentifier)).sorted().reversed() }
    private var relatedEntries: [Entry] {
        let ids = Set(relatedLinks.filter { occurrenceFilter == "all" || (occurrenceFilter == "general" ? $0.occurrenceIdentifier == nil : $0.occurrenceIdentifier == occurrenceFilter) }.map(\.entryID))
        return entries.filter { ids.contains($0.id) }.sorted { $0.occurredAt > $1.occurredAt }
    }
    private var nextOccurrence: ImportantCivilDay? { day.flatMap { try? $0.rule() }.flatMap { try? ImportantDayDateEngine.evaluate($0, today: today) }?.next }
    private var selectedYear: Int {
        guard let rule = day.flatMap({ try? $0.rule() }) else { return today.year }
        if let occurrenceYear, ImportantDayDateEngine.years.contains(occurrenceYear), occurrenceYear >= (rule.year ?? 1901) { return occurrenceYear }
        guard let next = nextOccurrence else { return max(today.year, rule.year ?? today.year) }
        // A lunar year's last month can fall in the next Gregorian year.
        return [next.year - 1, next.year].first { (try? ImportantDayDateEngine.occurrence(rule, in: $0)) == next } ?? today.year
    }
    private var selectedOccurrence: ImportantCivilDay? {
        guard explicitOccurrence, let rule = day.flatMap({ try? $0.rule() }) else { return nil }
        return try? ImportantDayDateEngine.explicitPeriod(rule, year: selectedYear)
    }
    private var invalidPeriod: Bool { explicitOccurrence && selectedOccurrence == nil }
    var body: some View {
        Group {
            if let day {
                List {
                    Section {
                        if let cover = covers.first(where: { $0.dayID == dayID }), let url = try? mediaStore.fileURL(for: cover.relativePath) {
                            ImportantDayCoverImage(url: url, cropX: (try? day.preferences().cropX) ?? 0.5, cropY: (try? day.preferences().cropY) ?? 0.5).frame(height: 180).clipped().accessibilityLabel("Independent cover")
                        }
                        Text(day.title).font(.title2).fixedSize(horizontal: false, vertical: true)
                        if let rule = try? day.rule() {
                            Text(rule.distanceDescription(today: today)).font(.title3.monospacedDigit()).accessibilityIdentifier("important-day-distance")
                            Text(rule.dateDescription).font(.subheadline).foregroundStyle(.secondary)
                            if let result = try? ImportantDayDateEngine.evaluate(rule, today: today), let next = result.next {
                                Text("Next date: \(next.identifier)")
                                if let original = result.original, original <= today { Text("\(original.distance(to: today) ?? 0) days elapsed").foregroundStyle(.secondary) }
                                if let number = result.anniversaryNumber { Text("Anniversary: \(number)").font(.caption) }
                            }
                            if !rule.exceptionDescription.isEmpty { Text(rule.exceptionDescription).font(.caption) }
                        }
                        if !day.notes.isEmpty { Text(day.notes) }
                        if day.isArchived { Label("Archived", systemImage: "archivebox") }
                    }
                    if !day.isArchived {
                        Section {
                            if let rule = try? day.rule(), rule.preset == .anniversary {
                                Toggle("Associate with a specific anniversary year", isOn: $explicitOccurrence).accessibilityIdentifier("important-day-explicit-period")
                                if explicitOccurrence {
                                    Picker(rule.calendar == .chinese ? "Lunar year" : "Anniversary year", selection: Binding(get: { selectedYear }, set: { occurrenceYear = $0 })) {
                                        ForEach((rule.year ?? ImportantDayDateEngine.years.lowerBound)...ImportantDayDateEngine.years.upperBound, id: \.self) { Text(String($0)).tag($0) }
                                    }.pickerStyle(.wheel).frame(height: 120).accessibilityIdentifier("important-day-period-year")
                                    if let selectedOccurrence { Text("Selected date: \(selectedOccurrence.identifier)").accessibilityIdentifier("important-day-selected-period") }
                                    else { Text("There is no anniversary occurrence in this year under the saved date rules. Choose another year.").foregroundStyle(.secondary) }
                                }
                                Text("Off associates with the day itself. A period is saved only when you choose it.").font(.caption).foregroundStyle(.secondary)
                            }
                            Button { writing = true } label: { Label("Write a related entry", systemImage: "square.and.pencil") }.accessibilityIdentifier("important-day-write").disabled(invalidPeriod)
                            Button("Link an existing entry") { linking = true }.accessibilityIdentifier("important-day-link").disabled(invalidPeriod)
                            Button("Add related Todo") { addingTodo = true }.accessibilityIdentifier("important-day-todo").disabled(invalidPeriod)
                        }
                    }
                    Section("Related entries") {
                        if !periods.isEmpty {
                            Picker("Anniversary period", selection: $occurrenceFilter) {
                                Text("All").tag("all"); Text("General entries").tag("general")
                                ForEach(periods, id: \.self) { Text($0).tag($0) }
                            }.accessibilityIdentifier("important-day-period-filter")
                        }
                        ForEach(relatedEntries) { entry in
                            NavigationLink { EntryDetailView(entry: entry, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: { TimelineRow(entry: entry, thumbnailStore: thumbnailStore) }
                                .swipeActions { Button("Unlink", role: .destructive) { perform { try service.unlinkEntry(dayID: dayID, entryID: entry.id) } } }
                        }
                        if relatedEntries.isEmpty { Text("No related entries yet").foregroundStyle(.secondary) }
                    }
                    let related = todoLinks.filter { $0.dayID == dayID }
                    if !related.isEmpty {
                        Section("Related Todos") {
                            if related.contains(where: { $0.dayRevisionAtLink != day.revision }) { Text("The day changed. Related Todos keep their original schedule; check them before making changes.").font(.caption).foregroundStyle(.secondary) }
                            ForEach(tasks.filter { task in related.contains { $0.taskID == task.id } }) { task in
                                NavigationLink { TodoDetailView(taskID: task.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: { TodoTaskRow(task: task) }
                            }
                        }
                    }
                    Section("Reminders on this device") {
                        let state = reminders.status(for: day)
                        Text(state.status.label).accessibilityIdentifier("important-day-reminder-status")
                        if let next = state.nextFire { Text(next, format: .dateTime.year().month().day().hour().minute().timeZone()) }
                        if let coverage = state.coverageEnd { Text("Scheduled coverage ends: \(coverage.formatted())").font(.caption) }
                        Text("Up to two occurrences are queued. Open the app to replenish; delivery and focus settings are controlled by iOS.").font(.caption).foregroundStyle(.secondary)
                        Button("Check reminder schedule") { Task { await reminders.reconcile(context: context, requestPermission: true) } }
                    }
                    Section("Day settings") {
                        if let p = try? day.preferences() {
                            Text(p.today.label)
                            Text(p.reminderOffsets.isEmpty ? String(localized: "No reminder") : String(localized: "Reminder preferences saved; device schedule is checked separately."))
                            Text(p.desktopVisible ? String(localized: "Authorized for desktop display") : String(localized: "Private in this app"))
                        }
                        if widgetPublisher.lastError { Text("The day is saved, but the desktop snapshot could not be updated. Retry when storage is available.").font(.caption).foregroundStyle(.secondary) }
                        Button("Edit Important Day") { editing = true }
                        Button("Add a Home Screen widget") { help = true }
                        Button(day.isArchived ? "Restore" : "Archive") { perform { var draft = try ImportantDayDraft(day); draft.archived.toggle(); _ = try service.save(draft, id: dayID) } }
                        Button("Delete Important Day", role: .destructive) { deleting = true }
                    }
                }
                .navigationTitle("Important Day").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) { ImportantDayEditorView(mediaStore: mediaStore, day: day) }
                .sheet(isPresented: $writing) {
                    QuickCaptureView(mediaStore: mediaStore, navigationTitle: String(localized: "Related entry"), saveDraft: { draft in
                        try service.createEntry(draft, dayID: dayID, occurrence: selectedOccurrence)
                    }, didSave: { _ in writing = false })
                }
                .sheet(isPresented: $linking) { ImportantDayEntryPicker(dayID: dayID, occurrence: selectedOccurrence, mediaStore: mediaStore, thumbnailStore: thumbnailStore) }
                .sheet(isPresented: $addingTodo) { TodoEditorView(importantDayID: dayID, importantDayOccurrence: selectedOccurrence) { _ in addingTodo = false } }
                .sheet(isPresented: $help) {
                    NavigationStack { List {
                        ImportantDayWidgetPreview(day: day, mediaStore: mediaStore)
                        Text("Touch and hold the Home Screen, choose Edit, then Add Widget. Find this app and choose Important Day or Day List. Select the days and their order in Edit Widget.")
                        Text("Only days you authorize for desktop display are available. iOS controls refresh and may retain a rendered view briefly after access is revoked.")
                        Button("Prepare this day for a widget") { perform { var draft = try ImportantDayDraft(day); draft.preferences.desktopVisible = true; _ = try service.save(draft, id: dayID) } }
                    }.navigationTitle("Home Screen widget").toolbar { Button("Done") { help = false } } }
                }
                .confirmationDialog("Delete this day and its independent cover? Entries and Todos are kept.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete Important Day", role: .destructive) { perform { try service.delete(id: dayID); dismiss() } }
                }
            } else {
                ContentUnavailableView("Day unavailable", systemImage: "calendar.badge.exclamationmark", description: Text("This day was removed or cannot be opened. Your other entries are unchanged."))
            }
        }
        .accessibilityIdentifier("important-day-detail")
        .onChange(of: day?.ruleData) { _, _ in explicitOccurrence = false; occurrenceYear = nil }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in referenceDate = Date() }
        .onChange(of: scenePhase) { _, p in if p == .active { referenceDate = Date() } }
        .alert("Important Day Update", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private var service: ImportantDayService { .init(context: context, mediaStore: mediaStore) }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = String(localized: "The day could not be saved. Your changes are still here.") }
    }
}

struct ImportantDayEntryPicker: View {
    let dayID: UUID
    let occurrence: ImportantCivilDay?
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [Entry]
    @State private var query = ""
    @State private var error = false
    var body: some View {
        NavigationStack {
            List(entries.filter { query.isEmpty || TextSearchNormalizer.normalize(($0.title ?? "") + " " + ($0.body ?? "")).contains(TextSearchNormalizer.normalize(query)) }.sorted { $0.occurredAt > $1.occurredAt }) { entry in
                Button { do { try ImportantDayService(context: context, mediaStore: mediaStore).linkEntry(dayID: dayID, entryID: entry.id, occurrence: occurrence); dismiss() } catch { self.error = true } } label: { TimelineRow(entry: entry, thumbnailStore: thumbnailStore) }
            }.navigationTitle("Link an existing entry").searchable(text: $query)
                .toolbar { Button("Cancel") { dismiss() } }
                .alert("Could not link entry", isPresented: $error) { Button("OK", role: .cancel) {} }
        }
    }
}

struct ImportantDayCoverImage: View {
    let url: URL
    var cropX = 0.5
    var cropY = 0.5
    var body: some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            ImportantDayPhotoView(image: UIImage(cgImage: image), cropX: cropX, cropY: cropY)
        } else { Image(systemName: "photo").foregroundStyle(.secondary).accessibilityLabel("Cover unavailable") }
    }
}

struct ImportantDayEditorView: View {
    let mediaStore: MediaStore
    var day: ImportantDay? = nil
    var sourceEntry: Entry? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingDays: [ImportantDay]
    @State private var draft = ImportantDayDraft()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var externalRouter = ImportantDayExternalRouter.shared
    @State private var loaded = false
    @State private var submissionID = UUID()
    @State private var confirmedOccurrence = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverSource: MediaSource?
    @State private var useEntryPhoto = false
    @State private var removeCover = false
    @State private var saving = false
    @State private var error: String?
    @Environment(TodoReminderCoordinator.self) private var reminders
    @State private var calendarChanged = false
    @State private var duplicateConfirmation = false
    @State private var confirmedActualBeginning = false
    @StateObject private var photoSession = PhotoInputSession()
    @State private var referenceDate = Date()
    private var today: ImportantCivilDay { .init(referenceDate) }
    private var valid: Bool { (try? draft.validate()) != nil && (sourceEntry == nil || confirmedOccurrence) && !calendarChanged && (!(day.flatMap { try? $0.rule().preset } == .anticipated && draft.rule.preset == .beginning) || confirmedActualBeginning) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Day name", text: $draft.title, axis: .vertical).accessibilityIdentifier("important-day-title")
                    Picker("Create as", selection: $draft.rule.preset) {
                        ForEach(ImportantDayPreset.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("important-day-preset")
                    Picker("Calendar", selection: $draft.rule.calendar) {
                        ForEach(ImportantDayCalendar.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("important-day-calendar")
                    if calendarChanged {
                        Text("Changing the calendar reinterprets these month and day numbers. Check the Gregorian preview before confirming.").font(.caption)
                        Button("Use the date in the selected calendar") { calendarChanged = false }
                    }
                    if draft.rule.preset == .anniversary {
                        Toggle("I know the starting year", isOn: Binding(get: { draft.rule.year != nil }, set: { draft.rule.year = $0 ? today.year : nil; if !$0 { draft.rule.perspective = .next } })).accessibilityIdentifier("important-day-known-year")
                    }
                    dateFields
                    if day.flatMap({ try? $0.rule().preset }) == .anticipated && draft.rule.preset == .beginning {
                        Toggle("I confirm this beginning actually occurred on the selected day", isOn: $confirmedActualBeginning)
                    }
                    if let sourceEntry {
                        Text("Suggested from the entry's occurrence time: \(ImportantCivilDay(sourceEntry.occurredAt).identifier). Confirm the actual day; the original local time zone may be unknown.").font(.caption)
                        Toggle("I confirm this actual occurrence date", isOn: $confirmedOccurrence).accessibilityIdentifier("important-day-confirm-occurrence")
                    }
                }
                specialRules
                Section("Date preview") {
                    Text(draft.rule.distanceDescription(today: today)).accessibilityIdentifier("important-day-preview")
                    if let result = try? ImportantDayDateEngine.evaluate(draft.rule, today: today) {
                        Text("Gregorian date: \(result.displayDay.identifier)")
                        if draft.rule.preset == .anniversary {
                            ForEach(previewDates, id: \.self) { Text($0.identifier).font(.caption).monospacedDigit() }
                        }
                    } else {
                        Text("Choose a valid date and confirm special-date rules. Supported years: 1901–2100; lunar dates use Asia/Shanghai.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("More settings") {
                    Picker("Today display", selection: $draft.preferences.today) {
                        ForEach(ImportantDayTodayPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Frequently viewed", isOn: Binding(get: { draft.preferences.favoriteOrder != nil }, set: { draft.preferences.favoriteOrder = $0 ? (existingDays.compactMap { try? $0.preferences().favoriteOrder }.max() ?? -1) + 1 : nil }))
                    Text("Frequently viewed only controls list order. Desktop display and notifications need separate choices.").font(.caption).foregroundStyle(.secondary)
                    TextField("Short note", text: $draft.notes, axis: .vertical)
                    if draft.rule.preset == .anniversary && draft.rule.year != nil {
                        Picker("Main perspective", selection: $draft.rule.perspective) {
                            Text("Next anniversary").tag(ImportantDayPerspective.next)
                            Text("Elapsed days").tag(ImportantDayPerspective.elapsed)
                        }
                    }
                    Section("Reminder preferences") {
                        ForEach([0, 1, 3, 7], id: \.self) { offset in
                            Toggle(offset == 0 ? String(localized: "On the day") : String(localized: "\(offset) days before"), isOn: Binding(get: { draft.preferences.reminderOffsets.contains(offset) }, set: { enabled in
                                if enabled && draft.preferences.reminderOffsets.count < 2 { draft.preferences.reminderOffsets.append(offset); draft.preferences.reminderOffsets.sort() }
                                else if !enabled { draft.preferences.reminderOffsets.removeAll { $0 == offset } }
                            })).disabled(draft.preferences.reminderOffsets.count >= 2 && !draft.preferences.reminderOffsets.contains(offset))
                        }
                        if !draft.preferences.reminderOffsets.isEmpty {
                            DatePicker("Reminder time", selection: Binding(get: { today.instant(minutes: draft.preferences.reminderMinutes, timeZone: .current) ?? Date() }, set: { date in
                                let c = Calendar.current; draft.preferences.reminderMinutes = c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
                            }), displayedComponents: .hourAndMinute)
                            Toggle("Use a general notification description", isOn: $draft.preferences.genericNotification)
                            Text("Time zone: \(TimeZone.current.identifier)").font(.caption)
                            if let next = try? ImportantDayReminderPlanner.requests(id: submissionID, title: draft.title, rule: draft.rule, preferences: draft.preferences, now: Date(), timeZone: .current).first {
                                Text("Next reminder: \(next.fireAt.formatted(date: .complete, time: .shortened))").font(.caption).accessibilityIdentifier("important-day-reminder-preview")
                            } else { Text("No future reminder within the supported date range").font(.caption) }
                        }
                    }
                    Section("Independent cover") {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose cover photo", systemImage: "photo") }.disabled(photoSession.isLoading)
                        if let image = sourceEntry?.images.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                            Toggle("Use entry photo as an independent cover", isOn: $useEntryPhoto)
                            if useEntryPhoto { Text("A separate copy is saved. Deleting the source entry will keep this cover.").font(.caption); Text(image.originalFilename).font(.caption) }
                        }
                        if let source = coverSource {
                            ImportantDayCoverImage(url: source.url, cropX: draft.preferences.cropX, cropY: draft.preferences.cropY).frame(height: 130).clipped()
                            Button("Cancel selected photo") { photoSession.end(); coverSource = nil; selectedPhoto = nil }
                        }
                        if day != nil { Toggle("Remove saved cover", isOn: $removeCover) }
                        Toggle("Photo widget style", isOn: $draft.preferences.photoStyle)
                        LabeledContent("Crop horizontal position") { Slider(value: $draft.preferences.cropX, in: 0...1).accessibilityLabel("Crop horizontal position") }
                        LabeledContent("Crop vertical position") { Slider(value: $draft.preferences.cropY, in: 0...1).accessibilityLabel("Crop vertical position") }
                    }
                    Toggle("Allow this day on the desktop", isOn: $draft.preferences.desktopVisible)
                    Text("This shares only its title, date rules and a small cover with widgets. Your entries and original photos stay in the app.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("important-day-save-error") } }
            }
            .safeAreaInset(edge: .top) {
                if externalRouter.pending != nil {
                    Text("An Important Day is waiting. Finish or cancel this editor, then open the request.").font(.caption).padding(8).background(.bar).accessibilityIdentifier("important-day-editor-route-queued")
                }
            }
            .navigationTitle(day == nil ? String(localized: "Add Important Day") : String(localized: "Edit Important Day"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if day == nil && existingDays.contains(where: { $0.title == draft.title.trimmingCharacters(in: .whitespacesAndNewlines) && (try? $0.rule()) == draft.rule }) { duplicateConfirmation = true }
                        else { save() }
                    }.disabled(!valid || saving || photoSession.isLoading).accessibilityIdentifier("important-day-save")
                }
            }
            .task {
                guard !loaded else { return }; loaded = true
                do {
                    if let day { draft = try ImportantDayDraft(day); submissionID = day.id }
                    else {
                        let civil = ImportantCivilDay(sourceEntry?.occurredAt ?? Date())
                        draft.rule.year = civil.year; draft.rule.month = civil.month; draft.rule.day = civil.day
                        if let sourceEntry {
                            draft.title = String((sourceEntry.title ?? sourceEntry.body?.components(separatedBy: .newlines).first ?? "").prefix(80))
                            draft.rule.preset = .beginning; draft.rule.perspective = .elapsed
                        }
                    }
                } catch { self.error = String(localized: "The day cannot be edited because its saved data is invalid.") }
            }
            .onChange(of: draft.rule.calendar) { old, new in if loaded && old != new { calendarChanged = true } }
            .onChange(of: draft.rule.preset) { _, new in
                if new != .anniversary && draft.rule.year == nil { draft.rule.year = today.year }
                draft.rule.perspective = new == .beginning ? .elapsed : .next
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in referenceDate = Date() }
            .onChange(of: selectedPhoto) { _, selected in loadPhoto(selected) }
            .onDisappear { photoSession.end() }
            .confirmationDialog("A day with this name and date already exists", isPresented: $duplicateConfirmation, titleVisibility: .visible) {
                Button("Create another day") { save() }
            }
        }
    }
    @ViewBuilder private var dateFields: some View {
        if draft.rule.calendar == .gregorian && draft.rule.year != nil {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                    Text(civilDateBinding.wrappedValue, format: .dateTime.year().month().day()).fixedSize(horizontal: false, vertical: true)
                    DatePicker("Date", selection: civilDateBinding, in: supportedDates, displayedComponents: .date)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).accessibilityIdentifier("important-day-date")
                }
            } else {
                DatePicker("Date", selection: civilDateBinding, in: supportedDates, displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).accessibilityIdentifier("important-day-date")
            }
        } else {
            if draft.rule.year != nil {
                Stepper("Starting year: \(draft.rule.year ?? today.year)", value: Binding(get: { draft.rule.year ?? today.year }, set: { draft.rule.year = $0 }), in: 1901...2100)
            }
            Picker("Month", selection: $draft.rule.month) { ForEach(1...12, id: \.self) { Text(String($0)).tag($0) } }
            Picker("Day", selection: $draft.rule.day) { ForEach(1...(draft.rule.calendar == .chinese ? 30 : 31), id: \.self) { Text(String($0)).tag($0) } }
        }
        if draft.rule.calendar == .chinese { Toggle("Lunar leap month", isOn: $draft.rule.isLeapMonth) }
    }
    private var supportedDates: ClosedRange<Date> {
        ImportantCivilDay(year: 1901, month: 1, day: 1).date!...ImportantCivilDay(year: 2100, month: 12, day: 31).date!
    }
    private var civilDateBinding: Binding<Date> {
        Binding(get: { ImportantCivilDay(year: draft.rule.year ?? today.year, month: draft.rule.month, day: draft.rule.day).date ?? Date() }, set: { date in
            let value = ImportantCivilDay(date, timeZone: .init(secondsFromGMT: 0)!); draft.rule.year = value.year; draft.rule.month = value.month; draft.rule.day = value.day
        })
    }
    @ViewBuilder private var specialRules: some View {
        if draft.rule.calendar == .gregorian && draft.rule.preset == .anniversary && draft.rule.month == 2 && draft.rule.day == 29 {
            Section("Confirm leap-day rule") {
                Picker("In a common year", selection: $draft.rule.leapDayRule) {
                    Text("Choose a rule").tag(nil as ImportantLeapDayRule?)
                    ForEach(ImportantLeapDayRule.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }
        if draft.rule.calendar == .chinese && draft.rule.isLeapMonth {
            Section("Confirm leap-month rule") {
                Picker("Without a matching leap month", selection: $draft.rule.leapMonthRule) {
                    Text("Choose a rule").tag(nil as ImportantLeapMonthRule?)
                    ForEach(ImportantLeapMonthRule.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }
        if draft.rule.calendar == .chinese && draft.rule.day == 30 {
            Section("Confirm short-month rule") {
                Picker("When day 30 does not exist", selection: $draft.rule.shortMonthRule) {
                    Text("Choose a rule").tag(nil as ImportantShortMonthRule?)
                    ForEach(ImportantShortMonthRule.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }
    }
    private var previewDates: [ImportantCivilDay] {
        guard (try? draft.rule.validate()) != nil else { return [] }
        return (max(1901, today.year - 1)...min(2100, today.year + 8)).compactMap { try? ImportantDayDateEngine.occurrence(draft.rule, in: $0) }.filter { $0 >= today }.prefix(3).map { $0 }
    }
    private func save() {
        guard !saving else { return }; saving = true
        do {
            var photo = removeCover ? nil : coverSource
            if !removeCover, photo == nil, useEntryPhoto, let image = sourceEntry?.images.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                photo = MediaSource(url: try mediaStore.fileURL(for: image.relativePath), originalFilename: image.originalFilename, contentType: image.contentType)
            }
            _ = try ImportantDayService(context: context, mediaStore: mediaStore).save(draft, id: submissionID, sourceEntryID: sourceEntry?.id, coverSource: photo, removeCover: removeCover)
            let ask = !draft.preferences.reminderOffsets.isEmpty
            if day == nil { UserDefaults.standard.set(true, forKey: "ImportantDayHasSavedDay") }
            reminders.savedImportantDayID = ask ? submissionID : nil
            photoSession.end()
            Task { await reminders.reconcile(context: context, requestPermission: ask) }
            dismiss()
        } catch {
            self.error = String(localized: "The day could not be saved. Your changes are still here."); saving = false
        }
    }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let operation = photoSession.begin()
        let task = Task { @MainActor in
            var url: URL?
            do {
                guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                      let ext = type.preferredFilenameExtension, let data = try await item.loadTransferable(type: Data.self) else { throw CaptureImageLoadError.noData }
                try Task.checkCancellation()
                let target = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-DayCover-\(UUID()).\(ext)"); url = target
                try data.write(to: target, options: .atomic)
                let source = MediaSource(url: target, originalFilename: "Cover.\(ext)", contentType: type.preferredMIMEType ?? "image/\(ext)")
                if photoSession.finish(operation, sources: [source], replacing: true) { coverSource = source; removeCover = false; useEntryPhoto = false }
            } catch {
                if let url { try? FileManager.default.removeItem(at: url) }
                if photoSession.finish(operation, sources: [], replacing: false) { self.error = String(localized: "The cover could not be loaded. Your day is still here.") }
            }
        }
        photoSession.track(task, for: operation)
    }
}

struct ImportantDaysTodaySection: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    let referenceDate: Date
    @Query private var days: [ImportantDay]
    private var visible: [ImportantDay] {
        let ids = ImportantDayTodaySelector.select(days.compactMap { day in
            guard let rule = try? day.rule(), let p = try? day.preferences() else { return nil }
            return .init(id: day.id, rule: rule, policy: p.today, archived: day.isArchived, stableOrder: 0)
        }, today: .init(referenceDate))
        return ids.compactMap { id in days.first { $0.id == id } }
    }
    var body: some View {
        if !visible.isEmpty {
            Section {
                ForEach(visible) { day in
                    NavigationLink { ImportantDayDetailView(dayID: day.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore) } label: { ImportantDayRow(day: day, today: .init(referenceDate)) }
                }
            } header: {
                HStack { Text("Important Days"); Spacer(); NavigationLink("All") { ImportantDaysView(mediaStore: mediaStore, thumbnailStore: thumbnailStore) } }
            }.accessibilityIdentifier("today-important-days")
        }
    }
}

struct ImportantDayReminderFeedbackView: View {
    @Environment(TodoReminderCoordinator.self) private var reminders
    @Query private var days: [ImportantDay]
    var body: some View {
        if let id = reminders.savedImportantDayID, let day = days.first(where: { $0.id == id }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Important day saved").font(.subheadline.bold())
                    Text(reminders.status(for: day).status.label).font(.caption)
                }
                Spacer()
                Button("Dismiss") { reminders.savedImportantDayID = nil }
            }.padding(10).background(.regularMaterial).accessibilityIdentifier("important-day-save-feedback")
        }
    }
}

/// Private on-screen preview reuses the extension's real view. It never grants or publishes desktop access.
struct ImportantDayWidgetPreview: View {
    let day: ImportantDay
    let mediaStore: MediaStore
    @Query private var covers: [ImportantDayCover]
    var body: some View {
        if let rule = try? day.rule(), let p = try? day.preferences() {
            let record = ImportantDayWidgetRecord(id: day.id, title: day.title, rule: rule, photoStyle: p.photoStyle, cropX: p.cropX, cropY: p.cropY, coverFilename: nil)
            let date = Date(), snapshot = ImportantDayWidgetSnapshot(version: 1, generation: UUID(), generatedAt: date, records: [record])
            let entry = DayWidgetEntry(date: date, ids: [day.id], snapshot: snapshot, sample: false)
            let cover = covers.first { $0.dayID == day.id }
            let image = cover.flatMap { try? mediaStore.fileURL(for: $0.relativePath) }.flatMap(ImportantDayWidgetPublisher.smallImage).flatMap(UIImage.init(data:))
            SingleDayWidgetView(entry: entry, previewMode: true, previewImage: image)
                .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("important-day-widget-preview")
        }
    }
}
