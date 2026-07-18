import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CaptureDraftState: ObservableObject {
    @Published var body = ""
    @Published private(set) var imageSource: MediaSource?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingImage = false

    func beginImageLoad() {
        isLoadingImage = true
        errorMessage = nil
    }

    func finishImageLoad(with result: Result<MediaSource, Error>) {
        isLoadingImage = false
        switch result {
        case .success(let source):
            imageSource = source
            errorMessage = nil
        case .failure:
            errorMessage = "The photo could not be loaded. Your text is still here."
        }
    }

    func reportSaveFailure(_ error: Error) {
        if let mediaError = error as? MediaStoreError,
           case .insufficientCapacity = mediaError {
            errorMessage = "There is not enough storage to save this photo. Your draft was kept."
        } else {
            errorMessage = "The entry could not be saved. Your draft was kept."
        }
    }
}

private enum CaptureImageLoadError: Error {
    case noData
    case unsupportedType
}

struct QuickCaptureView: View {
    let mediaStore: MediaStore
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var draft = CaptureDraftState()
    @State private var selectedItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var temporaryImageURL: URL?

    var body: some View {
        let photoButtonTitle = draft.imageSource == nil ? "Choose Photo" : "Replace Photo"

        NavigationStack {
            Form {
                Section("What do you want to remember?") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("capture-body")
                }

                Section("Photo") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(
                            photoButtonTitle,
                            systemImage: "photo"
                        )
                    }
                    .accessibilityIdentifier("capture-photo-picker")

                    if draft.imageSource != nil {
                        Label("Photo ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || draft.isLoadingImage)
                        .accessibilityIdentifier("capture-save")
                }
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                load(item)
            }
            .onDisappear { removeTemporaryImage() }
        }
    }

    private func load(_ item: PhotosPickerItem) {
        draft.beginImageLoad()
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CaptureImageLoadError.noData
                }
                guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                      let fileExtension = type.preferredFilenameExtension else {
                    throw CaptureImageLoadError.unsupportedType
                }
                removeTemporaryImage()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PGOS-Capture-\(UUID().uuidString).\(fileExtension)")
                try data.write(to: url, options: .atomic)
                temporaryImageURL = url
                draft.finishImageLoad(with: .success(MediaSource(
                    url: url,
                    originalFilename: "Selected Photo.\(fileExtension)",
                    contentType: type.preferredMIMEType ?? "image/\(fileExtension)"
                )))
            } catch {
                draft.finishImageLoad(with: .failure(error))
            }
        }
    }

    private func save() {
        isSaving = true
        do {
            let service = EntryCreationService(
                persistence: ModelContextEntryPersistence(context: modelContext),
                mediaStore: mediaStore
            )
            _ = try service.create(EntryCreationDraft(
                body: draft.body,
                image: draft.imageSource
            ))
            removeTemporaryImage()
            didSave()
        } catch {
            isSaving = false
            draft.reportSaveFailure(error)
        }
    }

    private func removeTemporaryImage() {
        if let temporaryImageURL {
            try? FileManager.default.removeItem(at: temporaryImageURL)
            self.temporaryImageURL = nil
        }
    }
}
