import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PhotoInputOperation: Identifiable {
    let id = UUID()
    fileprivate var completed = false
    fileprivate var task: Task<Void, Never>?
}

// Owns only uncommitted input files. Each completion must still own the current operation.
@MainActor
final class PhotoInputSession: ObservableObject {
    @Published private(set) var isLoading = false
    private var current: PhotoInputOperation?
    private var ownedURLs: Set<URL> = []

    func begin() -> PhotoInputOperation {
        current?.task?.cancel()
        let operation = PhotoInputOperation()
        current = operation
        isLoading = true
        return operation
    }

    func track(_ task: Task<Void, Never>, for operation: PhotoInputOperation) {
        guard current === operation, !operation.completed else { task.cancel(); return }
        operation.task = task
    }

    @discardableResult
    func finish(_ operation: PhotoInputOperation, sources: [MediaSource], replacing: Bool) -> Bool {
        guard !operation.completed else { return false }
        operation.completed = true
        operation.task = nil
        guard current === operation else {
            for source in sources where !ownedURLs.contains(source.url) { try? FileManager.default.removeItem(at: source.url) }
            return false
        }
        current = nil
        isLoading = false
        if replacing { removeOwnedFiles() }
        ownedURLs.formUnion(sources.map(\.url))
        return true
    }

    func cancel(_ operation: PhotoInputOperation) {
        guard current === operation else { return }
        operation.task?.cancel()
        current = nil
        isLoading = false
    }

    func end() {
        if let current { cancel(current) }
        removeOwnedFiles()
    }

    private func removeOwnedFiles() {
        for url in ownedURLs { try? FileManager.default.removeItem(at: url) }
        ownedURLs = []
    }
}

@MainActor
final class CaptureDraftState: ObservableObject {
    @Published var body = ""
    @Published private(set) var imageSources: [MediaSource] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingImage = false

    func beginImageLoad() {
        isLoadingImage = true
        errorMessage = nil
    }

    func finishImageLoad(with result: Result<[MediaSource], Error>) {
        isLoadingImage = false
        switch result {
        case .success(let sources):
            imageSources = sources
            errorMessage = nil
        case .failure:
            errorMessage = String(localized: "The photo could not be loaded. Your text is still here.")
        }
    }

    func appendCameraImage(_ source: MediaSource) {
        guard imageSources.count < EntryRules.maximumImageCount else { return }
        imageSources.append(source)
        errorMessage = nil
    }

    func removeImage(at index: Int) -> MediaSource? {
        guard imageSources.indices.contains(index) else { return nil }
        return imageSources.remove(at: index)
    }

    func moveImage(from index: Int, by offset: Int) {
        let destination = index + offset
        guard imageSources.indices.contains(index), imageSources.indices.contains(destination) else { return }
        imageSources.swapAt(index, destination)
    }

    func reportSaveFailure(_ error: Error) {
        switch error {
        case EntryValidationError.emptyContent:
            errorMessage = String(localized: "Add text or at least one photo before saving.")
        case MediaStoreError.insufficientCapacity:
            errorMessage = String(localized: "There is not enough storage to save these photos. Your draft was kept.")
        case MediaStoreError.unsupportedContentType:
            errorMessage = String(localized: "One photo uses an unsupported format. Your draft was kept.")
        case MediaStoreError.originalTooLarge:
            errorMessage = String(localized: "One photo is larger than 25 MB. Your draft was kept.")
        case MediaStoreError.imageTooLarge:
            errorMessage = String(localized: "One photo exceeds the 80-megapixel limit. Your draft was kept.")
        case EntryMediaOperationError.rollbackIncomplete:
            errorMessage = String(localized: "The entry was not saved and media recovery is required. Restart the app before trying again.")
        default:
            errorMessage = String(localized: "The entry could not be saved. Your draft was kept.")
        }
    }

    func reset() {
        body = ""
        imageSources = []
        errorMessage = nil
        isLoadingImage = false
    }
}

enum CaptureImageLoadError: Error {
    case noData
    case unsupportedType
}

struct QuickCaptureView: View {
    let mediaStore: MediaStore
    let navigationTitle: String
    let saveDraft: ((EntryCreationDraft) throws -> Entry)?
    let showsCancel: Bool
    let cleansUpOnDisappear: Bool
    let didSave: (Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var draft = CaptureDraftState()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isSaving = false
    @StateObject private var inputSession = PhotoInputSession()
    @State private var cameraOperation: PhotoInputOperation?

    init(mediaStore: MediaStore, didSave: @escaping () -> Void) {
        self.init(
            mediaStore: mediaStore,
            showsCancel: true,
            cleansUpOnDisappear: true,
            didSave: { _ in didSave() }
        )
    }

    init(
        mediaStore: MediaStore,
        showsCancel: Bool,
        cleansUpOnDisappear: Bool,
        didSave: @escaping (Entry) -> Void
    ) {
        self.mediaStore = mediaStore
        navigationTitle = String(localized: "Quick Capture")
        saveDraft = nil
        self.showsCancel = showsCancel
        self.cleansUpOnDisappear = cleansUpOnDisappear
        self.didSave = didSave
    }

    init(
        mediaStore: MediaStore,
        navigationTitle: String,
        saveDraft: @escaping (EntryCreationDraft) throws -> Entry,
        didSave: @escaping (Entry) -> Void
    ) {
        self.mediaStore = mediaStore
        self.navigationTitle = navigationTitle
        self.saveDraft = saveDraft
        showsCancel = true
        cleansUpOnDisappear = true
        self.didSave = didSave
    }

    var body: some View {
        let photoButtonTitle = draft.imageSources.isEmpty
            ? String(localized: "Choose Photos")
            : String(localized: "Replace \(draft.imageSources.count) Photos")

        NavigationStack {
            Form {
                Section("What do you want to remember?") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 140)
                        .accessibilityLabel("What do you want to remember?")
                        .accessibilityIdentifier("capture-body")
                }

                Section("Photo") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: EntryRules.maximumImageCount,
                        matching: .images,
                        preferredItemEncoding: .current
                    ) {
                        Label(
                            photoButtonTitle,
                            systemImage: "photo"
                        )
                    }
                    .accessibilityIdentifier("capture-photo-picker")

                    Button {
                        cameraOperation = inputSession.begin()
                        draft.beginImageLoad()
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .disabled(
                        !CameraCaptureView.isAvailable
                            || draft.imageSources.count >= EntryRules.maximumImageCount
                    )

                    if !draft.imageSources.isEmpty {
                        ForEach(Array(draft.imageSources.enumerated()), id: \.offset) { index, source in
                            LocalImagePreviewRow(
                                source: source,
                                position: index + 1,
                                total: draft.imageSources.count,
                                canMoveUp: index > 0,
                                canMoveDown: index < draft.imageSources.count - 1,
                                moveUp: { draft.moveImage(from: index, by: -1) },
                                moveDown: { draft.moveImage(from: index, by: 1) },
                                remove: { removeImage(at: index) }
                            )
                        }
                    }
                    if draft.isLoadingImage {
                        ProgressView("Loading photo…")
                    }
                }

                if let errorMessage = draft.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("capture-error")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { inputSession.end(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            isSaving
                                || draft.isLoadingImage
                                || (draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && draft.imageSources.isEmpty)
                        )
                        .accessibilityIdentifier("capture-save")
                }
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                load(items)
            }
            .sheet(item: $cameraOperation) { operation in
                CameraCaptureView(
                    completion: { result in
                        switch result {
                        case .success(let source):
                            guard inputSession.finish(operation, sources: [source], replacing: false) else { return }
                            draft.finishImageLoad(with: .success(draft.imageSources))
                            draft.appendCameraImage(source)
                        case .failure(let error):
                            guard inputSession.finish(operation, sources: [], replacing: false) else { return }
                            draft.finishImageLoad(with: .failure(error))
                        }
                        if cameraOperation === operation { cameraOperation = nil }
                    },
                    cancellation: {
                        guard cameraOperation === operation else { return }
                        inputSession.cancel(operation)
                        draft.finishImageLoad(with: .success(draft.imageSources))
                        cameraOperation = nil
                    }
                )
                .interactiveDismissDisabled()
                .ignoresSafeArea()
            }
            .onDisappear {
                if cleansUpOnDisappear {
                    inputSession.end()
                }
            }
        }
    }

    private func load(_ items: [PhotosPickerItem]) {
        let operation = inputSession.begin()
        draft.beginImageLoad()
        let task = Task {
            var newURLs: [URL] = []
            do {
                var sources: [MediaSource] = []
                for (index, item) in items.enumerated() {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CaptureImageLoadError.noData
                    }
                    try Task.checkCancellation()
                    guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                          let fileExtension = type.preferredFilenameExtension else {
                        throw CaptureImageLoadError.unsupportedType
                    }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("PGOS-Capture-\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: url, options: .atomic)
                    newURLs.append(url)
                    sources.append(MediaSource(
                        url: url,
                        originalFilename: "Selected Photo \(index + 1).\(fileExtension)",
                        contentType: type.preferredMIMEType ?? "image/\(fileExtension)"
                    ))
                }
                guard inputSession.finish(operation, sources: sources, replacing: true) else { return }
                draft.finishImageLoad(with: .success(sources))
            } catch {
                for url in newURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                if inputSession.finish(operation, sources: [], replacing: false) {
                    draft.finishImageLoad(with: .failure(error))
                }
            }
        }
        inputSession.track(task, for: operation)
    }

    private func save() {
        isSaving = true
        do {
            let entryDraft = EntryCreationDraft(
                body: draft.body,
                images: draft.imageSources
            )
            let entry: Entry
            if let saveDraft {
                entry = try saveDraft(entryDraft)
            } else {
                let service = EntryCreationService(
                    persistence: ModelContextEntryPersistence(context: modelContext),
                    mediaStore: mediaStore
                )
                entry = try service.create(entryDraft)
            }
            inputSession.end()
            draft.reset()
            selectedItems = []
            isSaving = false
            didSave(entry)
        } catch {
            isSaving = false
            draft.reportSaveFailure(error)
        }
    }

    private func removeImage(at index: Int) {
        guard let source = draft.removeImage(at: index) else { return }
        do {
            try FileManager.default.removeItem(at: source.url)
        } catch {
            // Temporary files are retried during view cleanup.
        }
    }
}

struct LocalImagePreviewRow: View {
    let source: MediaSource
    let position: Int
    let total: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let image = ThumbnailStore.downsampledImage(
                at: source.url,
                maximumPixelSize: 160
            ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text("Photo \(position) of \(total)")
                Text(source.originalFilename)
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
        .accessibilityLabel("Photo \(position) of \(total), \(source.originalFilename)")
    }
}
