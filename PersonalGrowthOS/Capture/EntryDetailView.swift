import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EntryDetailView: View {
    let entry: Entry
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let title = entry.title, !title.isEmpty {
                Section { Text(title).font(.title3.bold()) }
            }
            if let body = entry.body, !body.isEmpty {
                Section { Text(body) }
            }
            if !entry.images.isEmpty {
                Section("Photos") {
                    ForEach(entry.images.sorted(by: { $0.sortOrder < $1.sortOrder })) { image in
                        DownsampledOriginalView(
                            metadata: image,
                            thumbnailStore: thumbnailStore
                        )
                    }
                }
            }
            Section("Occurred") {
                Text(entry.occurredAt.formatted(date: .long, time: .shortened))
            }
        }
        .navigationTitle(entry.kind == .review ? "Review" : "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("entry-edit")
                Menu {
                    Button("Archive", systemImage: "archivebox") { archive() }
                    Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("entry-actions")
            }
        }
        .sheet(isPresented: $isEditing) {
            EntryEditorView(
                entry: entry,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore
            )
        }
        .alert("Delete this entry permanently?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { permanentlyDelete() }
        } message: {
            Text("Its text and owned photos will be removed. This cannot be undone.")
        }
        .alert("Could Not Update Entry", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func archive() {
        do {
            try deletionService.archive(entry)
            dismiss()
        } catch {
            errorMessage = "The entry was not archived. No photos were removed."
        }
    }

    private func permanentlyDelete() {
        do {
            try deletionService.permanentlyDelete(entry)
            dismiss()
        } catch {
            errorMessage = "The entry was not deleted. Its data and photos were restored."
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

private struct EntryEditorView: View {
    let entry: Entry
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var bodyText: String
    @State private var occurredAt: Date
    @State private var retainedImageIDs: Set<UUID>
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var addedImages: [MediaSource] = []
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
        _retainedImageIDs = State(initialValue: Set(entry.images.map(\.id)))
    }

    var body: some View {
        let retainedCount = entry.images.filter { retainedImageIDs.contains($0.id) }.count
        let remainingSlots = max(0, EntryRules.maximumImageCount - retainedCount)

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
                if !entry.images.isEmpty {
                    Section("Existing Photos") {
                        ForEach(entry.images.sorted(by: { $0.sortOrder < $1.sortOrder })) { image in
                            HStack {
                                Label(image.originalFilename, systemImage: "photo")
                                Spacer()
                                Button(retainedImageIDs.contains(image.id) ? "Remove" : "Keep") {
                                    if retainedImageIDs.contains(image.id) {
                                        retainedImageIDs.remove(image.id)
                                    } else {
                                        retainedImageIDs.insert(image.id)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Add Photos") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: remainingSlots,
                        matching: .images
                    ) {
                        Label("Choose up to \(remainingSlots)", systemImage: "photo.on.rectangle")
                    }
                    .disabled(remainingSlots == 0)
                    if !addedImages.isEmpty {
                        Text("\(addedImages.count) new photo(s) ready")
                    }
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
                        .disabled(isLoading || isSaving)
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
        Task {
            var newURLs: [URL] = []
            do {
                var sources: [MediaSource] = []
                for item in items {
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
                        originalFilename: "Selected Photo.\(fileExtension)",
                        contentType: type.preferredMIMEType ?? "image/\(fileExtension)"
                    ))
                }
                removeTemporaryFiles()
                temporaryURLs = newURLs
                addedImages = sources
                isLoading = false
            } catch {
                for url in newURLs { try? FileManager.default.removeItem(at: url) }
                isLoading = false
                errorMessage = "The new photos could not be loaded. Your edits are still here."
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
                retainedImageIDs: retainedImageIDs,
                addedImages: addedImages
            ))
            removeTemporaryFiles()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "The entry could not be updated. Your original entry is unchanged."
        }
    }

    private func removeTemporaryFiles() {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs = []
    }
}
