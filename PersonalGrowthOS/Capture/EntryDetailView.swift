import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EntryDetailView: View {
    let entry: Entry
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    var focusFollowUpID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var pins: [EntryPin]
    @Query private var followUps: [EntryFollowUp]
    @State private var isAddingThought = false
    @State private var editingThought: EntryFollowUp?
    @State private var deletingThought: EntryFollowUp?
    @State private var continuationMessage: String?
    @State private var isEditing = false
    @State private var isEditingTags = false
    @State private var isEditingRelationships = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @Query(sort: [
        SortDescriptor(\Tag.normalizedName, order: .forward),
        SortDescriptor(\Tag.id, order: .forward)
    ]) private var allTags: [Tag]
    @Query private var allLinks: [ObjectLink]
    @Query private var allEntries: [Entry]
    @Query private var allHabits: [Habit]
    @Query private var allGoals: [Goal]

    init(entry: Entry, mediaStore: MediaStore, thumbnailStore: ThumbnailStore, focusFollowUpID: UUID? = nil) {
        self.entry = entry
        self.mediaStore = mediaStore
        self.thumbnailStore = thumbnailStore
        self.focusFollowUpID = focusFollowUpID
        let entryID = entry.id
        _pins = Query(filter: #Predicate<EntryPin> { $0.entryID == entryID })
        _followUps = Query(filter: #Predicate<EntryFollowUp> { $0.entryID == entryID })
    }

    private var attachedTags: [Tag] {
        let tagIDs = Set(allLinks.filter {
            $0.kind == .entryUsesTag && $0.sourceID == entry.id
        }.map(\.targetID))
        return allTags.filter { tagIDs.contains($0.id) }
    }

    private var reviewedEntries: [Entry] {
        let ids = Set(allLinks.filter {
            $0.kind == .reviewsEntry && $0.sourceID == entry.id
        }.map(\.targetID))
        return allEntries.filter { ids.contains($0.id) }
    }

    private var reviewedHabits: [Habit] {
        let ids = Set(allLinks.filter {
            $0.kind == .reviewsHabit && $0.sourceID == entry.id
        }.map(\.targetID))
        return allHabits.filter { ids.contains($0.id) }
    }

    private var reviewedGoals: [Goal] {
        let ids = Set(allLinks.filter {
            $0.kind == .reviewsGoal && $0.sourceID == entry.id
        }.map(\.targetID))
        return allGoals.filter { ids.contains($0.id) }
    }

    private var relatedHabits: [Habit] {
        let ids = Set(allLinks.filter {
            $0.kind == .entryRelatesHabit && $0.sourceID == entry.id
        }.map(\.targetID))
        return allHabits.filter { ids.contains($0.id) }
    }

    private var relatedGoals: [Goal] {
        let ids = Set(allLinks.filter {
            $0.kind == .entryRelatesGoal && $0.sourceID == entry.id
        }.map(\.targetID))
        return allGoals.filter { ids.contains($0.id) }
    }

    private var thoughts: [EntryFollowUp] {
        followUps.filter { $0.entryID == entry.id }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    private var isPinned: Bool { pins.contains { $0.entryID == entry.id } }

    var body: some View {
        ScrollViewReader { proxy in
            content.task {
                if let focusFollowUpID {
                    await Task.yield()
                    proxy.scrollTo(focusFollowUpID, anchor: .center)
                }
            }
        }
    }

    private var content: some View {
        List {
            if let title = entry.title, !title.isEmpty {
                Section { Text(title).font(.title3.bold()) }
            }
            if let body = entry.body, !body.isEmpty {
                Section { Text(body) }
            }
            if !entry.images.isEmpty {
                Section("Photos") {
                    let images = entry.images.sorted(by: { $0.sortOrder < $1.sortOrder })
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        DownsampledOriginalView(
                            metadata: image,
                            thumbnailStore: thumbnailStore,
                            mediaStore: mediaStore,
                            accessibilityLabel: "Photo \(index + 1) of \(images.count)"
                        )
                    }
                }
            }
            Section("Follow-ups") {
                ForEach(thoughts) { thought in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thought.body).textSelection(.enabled)
                        HStack {
                            Text(thought.createdAt, format: .dateTime.year().month().day().hour().minute())
                            if thought.updatedAt != thought.createdAt { Text("Edited") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if entry.status != .archived {
                            HStack {
                                Button("Edit") { editingThought = thought }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("edit-follow-up-\(thought.id)")
                                Button("Delete", role: .destructive) { deletingThought = thought }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("delete-follow-up-\(thought.id)")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                    .id(thought.id)
                    .accessibilityIdentifier("follow-up-\(thought.id)")
                    .listRowBackground(focusFollowUpID == thought.id ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                }
                if entry.status != .archived {
                    Button("Add a Thought", systemImage: "text.badge.plus") { isAddingThought = true }
                        .accessibilityIdentifier("entry-add-thought")
                }
                if let continuationMessage { Text(continuationMessage).font(.caption).foregroundStyle(.secondary) }
            }
            .id("follow-ups")
            Section("Occurred") {
                Text(entry.occurredAt.formatted(date: .long, time: .shortened))
            }
            if entry.kind == .review {
                Section("Review Period") {
                    if let start = entry.periodStart {
                        LabeledContent("Start", value: start.formatted(date: .long, time: .shortened))
                    }
                    if let end = entry.periodEnd {
                        LabeledContent("End", value: end.formatted(date: .long, time: .shortened))
                    }
                    if entry.periodStart == nil && entry.periodEnd == nil {
                        Text("No period selected")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Reviewed Objects") {
                    ForEach(reviewedEntries) { reviewed in
                        NavigationLink {
                            EntryDetailView(
                                entry: reviewed,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(reviewed.title ?? reviewed.body ?? "Entry", systemImage: "doc.text")
                        }
                    }
                    ForEach(reviewedHabits) { habit in
                        NavigationLink {
                            HabitDetailView(
                                habit: habit,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(habit.name, systemImage: "repeat")
                        }
                    }
                    ForEach(reviewedGoals) { goal in
                        NavigationLink {
                            GoalDetailView(
                                goal: goal,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(goal.title, systemImage: goal.kind == .flag ? "flag" : "target")
                        }
                    }
                    if reviewedEntries.isEmpty && reviewedHabits.isEmpty && reviewedGoals.isEmpty {
                        Text("No related Entry, Habit, or Goal")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !relatedHabits.isEmpty || !relatedGoals.isEmpty {
                Section("Relationships") {
                    ForEach(relatedHabits) { habit in
                        NavigationLink {
                            HabitDetailView(
                                habit: habit,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(habit.name, systemImage: "repeat")
                        }
                    }
                    ForEach(relatedGoals) { goal in
                        NavigationLink {
                            GoalDetailView(
                                goal: goal,
                                mediaStore: mediaStore,
                                thumbnailStore: thumbnailStore
                            )
                        } label: {
                            Label(goal.title, systemImage: goal.kind == .flag ? "flag" : "target")
                        }
                    }
                }
            }
            Section("Organization") {
                LabeledContent("Status", value: entry.status.localizedName)
                if !attachedTags.isEmpty {
                    ForEach(attachedTags) { tag in
                        Label(tag.displayName, systemImage: "tag")
                    }
                }
                Button("Manage Tags") { isEditingTags = true }
                    .accessibilityIdentifier("entry-manage-tags")
                Button(
                    entry.kind == .review
                        ? String(localized: "Manage Reviewed Objects")
                        : String(localized: "Manage Relationships")
                ) {
                    isEditingRelationships = true
                }
                    .accessibilityIdentifier("entry-manage-relationships")
            }
        }
        .navigationTitle(
            entry.kind == .review
                ? String(localized: "Review")
                : String(localized: "Entry")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("entry-edit")
                Menu {
                    if entry.status != .archived {
                        Button(isPinned ? "Unpin Entry" : "Pin Entry", systemImage: isPinned ? "pin.slash" : "pin") {
                            do { try EntryContinuationService(context: modelContext).setPinned(!isPinned, entryID: entry.id) }
                            catch { errorMessage = String(localized: "The change was not saved.") }
                        }
                        .accessibilityIdentifier("entry-toggle-pin")
                    }
                    if entry.status == .archived {
                        Button("Restore", systemImage: "arrow.uturn.backward") { restore() }
                    } else {
                        if entry.status == .inbox {
                            Button("Mark Organized", systemImage: "checkmark.circle") { organize() }
                        } else {
                            Button("Move to Inbox", systemImage: "tray") { moveToInbox() }
                        }
                        Button("Archive", systemImage: "archivebox") { archive() }
                    }
                    Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("entry-actions")
            }
        }
        .sheet(isPresented: $isAddingThought) {
            EntryThoughtEditor(entryID: entry.id, followUp: nil) {
                continuationMessage = String(localized: "Saved")
            }
        }
        .sheet(item: $editingThought) { thought in
            EntryThoughtEditor(entryID: entry.id, followUp: thought) {
                continuationMessage = String(localized: "Saved")
            }
        }
        .confirmationDialog("Delete this follow-up?", isPresented: Binding(
            get: { deletingThought != nil }, set: { if !$0 { deletingThought = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let thought = deletingThought else { return }
                do {
                    try EntryContinuationService(context: modelContext).delete(thought)
                    deletingThought = nil
                } catch { errorMessage = String(localized: "The change was not saved.") }
            }
        }
        .sheet(isPresented: $isEditing) {
            EntryEditorView(
                entry: entry,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
        }
        .sheet(isPresented: $isEditingTags) {
            EntryTagEditor(entry: entry)
        }
        .sheet(isPresented: $isEditingRelationships) {
            EntryRelationshipsEditor(entry: entry)
        }
        .alert("Delete this entry permanently?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { permanentlyDelete() }
        } message: {
            Text("Its text, photos, and follow-ups will be removed. This cannot be undone.")
        }
        .alert("Could Not Update Entry", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
    }

    private func archive() {
        do {
            try deletionService.archive(entry)
            dismiss()
        } catch {
            errorMessage = String(localized: "The entry was not archived. No photos were removed.")
        }
    }

    private func restore() {
        do {
            try deletionService.restore(entry)
            dismiss()
        } catch {
            errorMessage = String(localized: "The entry was not restored. Its archived copy is unchanged.")
        }
    }

    private func organize() {
        do {
            try deletionService.organize(entry)
            dismiss()
        } catch {
            errorMessage = String(localized: "The entry remains in Inbox.")
        }
    }

    private func moveToInbox() {
        do {
            try deletionService.moveToInbox(entry)
            dismiss()
        } catch {
            errorMessage = String(localized: "The entry's organized status is unchanged.")
        }
    }

    private func permanentlyDelete() {
        do {
            try deletionService.permanentlyDelete(entry)
            dismiss()
        } catch {
            if error is EntryMediaOperationError {
                errorMessage = String(localized: "The entry was not deleted and media recovery is required. Restart the app before trying again.")
            } else {
                errorMessage = String(localized: "The entry was not deleted. Its data remains available.")
            }
        }
    }

    private var deletionService: EntryDeletionService {
        EntryDeletionService(
            persistence: ModelContextEntryPersistence(context: modelContext),
            mediaStore: mediaStore,
            thumbnailCleanup: thumbnailStore.removeThumbnail
        )
    }
}

extension EntryStatus {
    var localizedName: String {
        switch self {
        case .inbox: String(localized: "Inbox")
        case .organized: String(localized: "Organized")
        case .archived: String(localized: "Archived")
        }
    }
}

private enum EntryEditorImageItem: Identifiable {
    case retained(ImageMetadata)
    case added(UUID, MediaSource)

    var id: UUID {
        switch self {
        case .retained(let image): image.id
        case .added(let id, _): id
        }
    }
}

private struct EntryEditorView: View {
    let entry: Entry
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var bodyText: String
    @State private var occurredAt: Date
    @State private var imageItems: [EntryEditorImageItem]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var temporaryURLs: [URL] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: Entry, mediaStore: MediaStore, thumbnailStore: ThumbnailStore) {
        self.entry = entry
        self.mediaStore = mediaStore
        self.thumbnailStore = thumbnailStore
        _title = State(initialValue: entry.title ?? "")
        _bodyText = State(initialValue: entry.body ?? "")
        _occurredAt = State(initialValue: entry.occurredAt)
        _imageItems = State(initialValue: entry.images
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map(EntryEditorImageItem.retained))
    }

    var body: some View {
        let remainingSlots = max(0, EntryRules.maximumImageCount - imageItems.count)

        NavigationStack {
            Form {
                Section("Title (optional)") {
                    TextField("Title", text: $title)
                }
                Section("Entry") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("entry-edit-body")
                }
                Section("Occurred") {
                    DatePicker("Date and time", selection: $occurredAt)
                }
                if !imageItems.isEmpty {
                    Section("Photos") {
                        ForEach(Array(imageItems.enumerated()), id: \.element.id) { index, item in
                            switch item {
                            case .retained(let image):
                                ExistingImageEditorRow(
                                    image: image,
                                    thumbnailStore: thumbnailStore,
                                    position: index + 1,
                                    total: imageItems.count,
                                    canMoveUp: index > 0,
                                    canMoveDown: index < imageItems.count - 1,
                                    moveUp: { imageItems.swapAt(index, index - 1) },
                                    moveDown: { imageItems.swapAt(index, index + 1) },
                                    remove: { removeImageItem(at: index) }
                                )
                            case .added(_, let source):
                                LocalImagePreviewRow(
                                    source: source,
                                    position: index + 1,
                                    total: imageItems.count,
                                    canMoveUp: index > 0,
                                    canMoveDown: index < imageItems.count - 1,
                                    moveUp: { imageItems.swapAt(index, index - 1) },
                                    moveDown: { imageItems.swapAt(index, index + 1) },
                                    remove: { removeImageItem(at: index) }
                                )
                            }
                        }
                    }
                }
                Section("Add Photos") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: remainingSlots,
                        matching: .images,
                        preferredItemEncoding: .current
                    ) {
                        Label("Choose up to \(remainingSlots)", systemImage: "photo.on.rectangle")
                    }
                    .disabled(remainingSlots == 0)
                    if isLoading { ProgressView("Loading photos…") }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            isLoading
                                || isSaving
                                || (bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && imageItems.isEmpty)
                        )
                        .accessibilityIdentifier("entry-edit-save")
                }
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                load(items)
            }
            .onDisappear { removeTemporaryFiles() }
        }
    }

    private func load(_ items: [PhotosPickerItem]) {
        isLoading = true
        errorMessage = nil
        let existingAddedCount = imageItems.reduce(0) { count, item in
            if case .added = item { return count + 1 }
            return count
        }
        Task {
            var newURLs: [URL] = []
            do {
                var sources: [MediaSource] = []
                for (index, item) in items.enumerated() {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CaptureImageLoadError.noData
                    }
                    guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                          let fileExtension = type.preferredFilenameExtension else {
                        throw CaptureImageLoadError.unsupportedType
                    }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("PGOS-Edit-\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: url, options: .atomic)
                    newURLs.append(url)
                    sources.append(MediaSource(
                        url: url,
                        originalFilename: "Selected Photo \(existingAddedCount + index + 1).\(fileExtension)",
                        contentType: type.preferredMIMEType ?? "image/\(fileExtension)"
                    ))
                }
                temporaryURLs.append(contentsOf: newURLs)
                imageItems.append(contentsOf: sources.map { .added(UUID(), $0) })
                selectedItems = []
                isLoading = false
            } catch {
                for url in newURLs { try? FileManager.default.removeItem(at: url) }
                isLoading = false
                errorMessage = String(localized: "The new photos could not be loaded. Your edits are still here.")
            }
        }
    }

    private func save() {
        isSaving = true
        do {
            let service = EntryEditingService(
                persistence: ModelContextEntryPersistence(context: modelContext),
                mediaStore: mediaStore,
                thumbnailCleanup: thumbnailStore.removeThumbnail
            )
            try service.update(entry, with: EntryEditingDraft(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title,
                body: bodyText,
                occurredAt: occurredAt,
                orderedImages: imageItems.map { item in
                    switch item {
                    case .retained(let image): .retained(image.id)
                    case .added(_, let source): .added(source)
                    }
                }
            ))
            removeTemporaryFiles()
            dismiss()
        } catch {
            isSaving = false
            switch error {
            case MediaStoreError.insufficientCapacity:
                errorMessage = String(localized: "There is not enough storage to add these photos. Your edits were kept.")
            case MediaStoreError.unsupportedContentType:
                errorMessage = String(localized: "One photo uses an unsupported format. Your edits were kept.")
            case MediaStoreError.originalTooLarge:
                errorMessage = String(localized: "One photo is larger than 25 MB. Your edits were kept.")
            case MediaStoreError.imageTooLarge:
                errorMessage = String(localized: "One photo exceeds the 80-megapixel limit. Your edits were kept.")
            case EntryMediaOperationError.rollbackIncomplete:
                errorMessage = String(localized: "The entry was not updated and media recovery is required. Restart the app before trying again.")
            default:
                errorMessage = String(localized: "The entry could not be updated. Your original entry is unchanged.")
            }
        }
    }

    private func removeTemporaryFiles() {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs = []
    }

    private func removeImageItem(at index: Int) {
        guard imageItems.indices.contains(index) else { return }
        let item = imageItems.remove(at: index)
        if case .added(_, let source) = item {
            do {
                try FileManager.default.removeItem(at: source.url)
            } catch {
                // Temporary files are retried during view cleanup.
            }
        }
    }
}

private struct ExistingImageEditorRow: View {
    let image: ImageMetadata
    let thumbnailStore: ThumbnailStore
    let position: Int
    let total: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = thumbnailStore.image(for: image) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text("Photo \(position) of \(total)")
                Text(image.originalFilename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Move Up", systemImage: "arrow.up", action: moveUp)
                    .disabled(!canMoveUp)
                Button("Move Down", systemImage: "arrow.down", action: moveDown)
                    .disabled(!canMoveDown)
                Button("Remove", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Actions for photo \(position) of \(total)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo \(position) of \(total), \(image.originalFilename)")
    }
}

private struct EntryThoughtEditor: View {
    let entryID: UUID
    let followUp: EntryFollowUp?
    let didSave: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var bodyText: String
    @State private var submissionID = UUID()
    @State private var isSaving = false
    @State private var confirmsDiscard = false
    @State private var errorMessage: String?

    init(entryID: UUID, followUp: EntryFollowUp?, didSave: @escaping () -> Void) {
        self.entryID = entryID
        self.followUp = followUp
        self.didSave = didSave
        _bodyText = State(initialValue: followUp?.body ?? "")
    }

    private var isDirty: Bool { bodyText != (followUp?.body ?? "") }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 200)
                    .focused($isFocused)
                    .accessibilityLabel("Thought")
                    .accessibilityIdentifier("follow-up-editor-body")
            }
            .navigationTitle(followUp == nil ? "Add a Thought" : "Edit Follow-up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isFocused = false
                        if isDirty { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || !isDirty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("follow-up-editor-save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
        .alert("Discard unsaved changes?", isPresented: $confirmsDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
                .accessibilityIdentifier("follow-up-keep-editing")
        }
        .alert("Could Not Save Follow-up", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        isFocused = false
        do {
            let service = EntryContinuationService(context: modelContext)
            if let followUp { try service.edit(followUp, body: bodyText) }
            else { try service.add(entryID: entryID, body: bodyText, id: submissionID) }
            didSave()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = String(localized: "Your thought was not saved. Your text is still here.")
        }
    }
}
