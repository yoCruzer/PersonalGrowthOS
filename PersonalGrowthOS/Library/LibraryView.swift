import SwiftData
import SwiftUI

enum LibraryEntryFilter: String {
    case inbox = "Inbox"
    case all = "All Entries"
    case archived = "Archived"

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .all: "doc.text"
        case .archived: "archivebox"
        }
    }
}

struct LibraryView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query private var entries: [Entry]
    @Query private var tags: [Tag]
    @State private var isCreatingReview = false

    var body: some View {
        List {
            Section {
                Button {
                    isCreatingReview = true
                } label: {
                    Label("New Review", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("library-new-review")
            } header: {
                Text("Reflect")
            } footer: {
                Text("Create a manual reflection for a day, week, or another period you choose.")
            }
            Section {
                destination(.inbox, count: entries.filter { $0.status == .inbox }.count)
                destination(.all, count: entries.count)
                NavigationLink {
                    TagsView(
                        mediaStore: mediaStore,
                        thumbnailStore: thumbnailStore
                    )
                } label: {
                    HStack {
                        Label("Tags", systemImage: "tag")
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Spacer()
                        Text("\(tags.count)")
                    }
                }
                .accessibilityIdentifier("library-tags")
                destination(.archived, count: entries.filter { $0.status == .archived }.count)
            } footer: {
                Text("Inbox is a place to leave captures until you choose to organize them. It never has to be empty.")
            }
        }
        .navigationTitle("Library")
        .accessibilityIdentifier("library-view")
        .sheet(isPresented: $isCreatingReview) {
            ReviewComposerView(mediaStore: mediaStore)
        }
    }

    private func destination(_ filter: LibraryEntryFilter, count: Int) -> some View {
        NavigationLink {
            LibraryEntriesView(
                filter: filter,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
        } label: {
            HStack {
                Label(filter.rawValue, systemImage: filter.systemImage)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer()
                Text("\(count)")
            }
        }
        .accessibilityIdentifier("library-\(filter.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

private struct ReviewComposerView: View {
    let mediaStore: MediaStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.id, order: .forward)
    ]) private var entries: [Entry]
    @Query(sort: [SortDescriptor(\Habit.normalizedName)]) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Goal.normalizedTitle)]) private var goals: [Goal]
    @State private var includesPeriod = false
    @State private var periodStart = Calendar.current.startOfDay(for: Date())
    @State private var periodEnd = Date()
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var selectedHabitIDs: Set<UUID> = []
    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var isWriting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    Toggle("Include Review Period", isOn: $includesPeriod)
                        .accessibilityIdentifier("review-include-period")
                    if includesPeriod {
                        DatePicker("Start", selection: $periodStart)
                            .accessibilityIdentifier("review-period-start")
                        DatePicker("End", selection: $periodEnd)
                            .accessibilityIdentifier("review-period-end")
                        if periodEnd < periodStart {
                            Text("The end must be on or after the start.")
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !entries.isEmpty {
                    Section("Entries") {
                        ForEach(entries) { entry in
                            selectionButton(
                                entry.title ?? entry.body ?? "Entry",
                                selected: selectedEntryIDs.contains(entry.id),
                                identifier: "review-entry-\(entry.id.uuidString)"
                            ) {
                                selectedEntryIDs.toggle(entry.id)
                            }
                        }
                    }
                }
                if !habits.isEmpty {
                    Section("Habits") {
                        ForEach(habits) { habit in
                            selectionButton(
                                habit.name,
                                selected: selectedHabitIDs.contains(habit.id),
                                identifier: "review-habit-\(habit.normalizedName)"
                            ) {
                                selectedHabitIDs.toggle(habit.id)
                            }
                        }
                    }
                }
                if !goals.isEmpty {
                    Section("Goals and Flags") {
                        ForEach(goals) { goal in
                            selectionButton(
                                goal.title,
                                selected: selectedGoalIDs.contains(goal.id),
                                identifier: "review-goal-\(goal.normalizedTitle)"
                            ) {
                                selectedGoalIDs.toggle(goal.id)
                            }
                        }
                    }
                }
                Section {
                    Button("Write Review") { isWriting = true }
                        .disabled(includesPeriod && periodEnd < periodStart)
                        .accessibilityIdentifier("review-write")
                } footer: {
                    Text("Review is a regular Entry in Timeline, Library, and Search. It is never generated automatically.")
                }
            }
            .navigationTitle("New Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isWriting) {
                QuickCaptureView(
                    mediaStore: mediaStore,
                    navigationTitle: "Write Review",
                    saveDraft: { entryDraft in
                        let period = includesPeriod
                            ? try ReviewPeriod(start: periodStart, end: periodEnd)
                            : nil
                        return try ReviewCreationService(
                            context: modelContext,
                            mediaStore: mediaStore
                        ).create(ReviewCreationDraft(
                            entryDraft: entryDraft,
                            period: period,
                            reviewedEntryIDs: selectedEntryIDs,
                            reviewedHabitIDs: selectedHabitIDs,
                            reviewedGoalIDs: selectedGoalIDs
                        ))
                    },
                    didSave: { _ in
                        isWriting = false
                        dismiss()
                    }
                )
            }
        }
    }

    private func selectionButton(
        _ title: String,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(2)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
        .accessibilitySelectionState(selected)
    }
}

private extension Set where Element == UUID {
    mutating func toggle(_ id: UUID) {
        if contains(id) {
            remove(id)
        } else {
            insert(id)
        }
    }
}

struct LibraryEntriesView: View {
    let filter: LibraryEntryFilter
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.createdAt, order: .reverse),
        SortDescriptor(\Entry.id, order: .forward)
    ]) private var entries: [Entry]

    private var displayedEntries: [Entry] {
        switch filter {
        case .inbox: entries.filter { $0.status == .inbox }
        case .all: entries
        case .archived: entries.filter { $0.status == .archived }
        }
    }

    var body: some View {
        Group {
            if displayedEntries.isEmpty {
                ContentUnavailableView(
                    "No \(filter.rawValue)",
                    systemImage: filter.systemImage,
                    description: Text(emptyDescription)
                )
            } else {
                List(displayedEntries) { entry in
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        TimelineRow(entry: entry, thumbnailStore: thumbnailStore)
                    }
                }
            }
        }
        .navigationTitle(filter.rawValue)
    }

    private var emptyDescription: String {
        switch filter {
        case .inbox: "New captures can stay here for as long as you like."
        case .all: "Your entries will appear here."
        case .archived: "Archived entries will appear here."
        }
    }
}

struct TagsView: View {
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Tag.normalizedName, order: .forward),
        SortDescriptor(\Tag.id, order: .forward)
    ]) private var tags: [Tag]
    @State private var newTagName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("New Tag") {
                HStack {
                    TextField("Tag name", text: $newTagName)
                        .accessibilityIdentifier("new-tag-name")
                    Button("Add") { createTag() }
                        .disabled(TextSearchNormalizer.normalize(newTagName).isEmpty)
                        .accessibilityIdentifier("add-tag")
                }
            }
            Section("Tags") {
                if tags.isEmpty {
                    Text("Tags are optional. Add one only when it helps you find something again.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags) { tag in
                        NavigationLink {
                            TagEntriesView(
                                tag: tag,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(tag.displayName, systemImage: "tag")
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { delete(tag) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .alert("Could Not Update Tags", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func createTag() {
        do {
            _ = try TagLinkService(context: modelContext).createTag(displayName: newTagName)
            newTagName = ""
        } catch TagValidationError.duplicateName {
            errorMessage = "A tag with that name already exists."
        } catch {
            errorMessage = "The tag was not created."
        }
    }

    private func delete(_ tag: Tag) {
        do {
            try TagLinkService(context: modelContext).deleteTag(tag)
        } catch {
            errorMessage = "The tag was not deleted. Its entry links are unchanged."
        }
    }
}

struct TagEntriesView: View {
    let tag: Tag
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Query(sort: [
        SortDescriptor(\Entry.occurredAt, order: .reverse),
        SortDescriptor(\Entry.createdAt, order: .reverse),
        SortDescriptor(\Entry.id, order: .forward)
    ]) private var entries: [Entry]
    @Query private var links: [ObjectLink]

    private var taggedEntries: [Entry] {
        let entryIDs = Set(links.filter {
            $0.kind == .entryUsesTag && $0.targetID == tag.id
        }.map(\.sourceID))
        return entries.filter { entryIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if taggedEntries.isEmpty {
                ContentUnavailableView(
                    "No Entries Tagged \(tag.displayName)",
                    systemImage: "tag",
                    description: Text("Tags are optional and can be added from an Entry.")
                )
            } else {
                List(taggedEntries) { entry in
                    NavigationLink {
                        EntryDetailView(
                            entry: entry,
                            mediaStore: mediaStore,
                            thumbnailStore: thumbnailStore
                        )
                    } label: {
                        TimelineRow(entry: entry, thumbnailStore: thumbnailStore)
                    }
                }
            }
        }
        .navigationTitle(tag.displayName)
    }
}

struct EntryTagEditor: View {
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Tag.normalizedName, order: .forward),
        SortDescriptor(\Tag.id, order: .forward)
    ]) private var tags: [Tag]
    @Query private var links: [ObjectLink]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    ContentUnavailableView(
                        "No Tags Yet",
                        systemImage: "tag",
                        description: Text("Create lightweight tags from Library when they help you find something again.")
                    )
                } else {
                    ForEach(tags) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Text(tag.displayName)
                                Spacer()
                                if isAttached(tag) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilitySelectionState(isAttached(tag))
                    }
                }
            }
            .navigationTitle("Entry Tags")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .alert("Could Not Update Tags", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func isAttached(_ tag: Tag) -> Bool {
        links.contains {
            $0.kind == .entryUsesTag
                && $0.sourceID == entry.id
                && $0.targetID == tag.id
        }
    }

    private func toggle(_ tag: Tag) {
        do {
            let service = TagLinkService(context: modelContext)
            if isAttached(tag) {
                try service.detach(tag: tag, from: entry)
            } else {
                try service.attach(tag: tag, to: entry)
            }
        } catch {
            errorMessage = "The Entry's tags were not changed."
        }
    }
}

extension View {
    @ViewBuilder
    func accessibilitySelectionState(_ selected: Bool) -> some View {
        if selected {
            accessibilityValue("Selected")
                .accessibilityAddTraits(.isSelected)
        } else {
            accessibilityValue("Not selected")
        }
    }
}
