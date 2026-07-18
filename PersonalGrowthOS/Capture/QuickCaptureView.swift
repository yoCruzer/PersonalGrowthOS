import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
            errorMessage = "The photo could not be loaded. Your text is still here."
        }
    }

    func appendCameraImage(_ source: MediaSource) {
        guard imageSources.count < EntryRules.maximumImageCount else { return }
        imageSources.append(source)
        errorMessage = nil
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

enum CaptureImageLoadError: Error {
    case noData
    case unsupportedType
}

struct QuickCaptureView: View {
    let mediaStore: MediaStore
    let didSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var draft = CaptureDraftState()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var temporaryImageURLs: [URL] = []
    @State private var isShowingCamera = false

    var body: some View {
        let photoButtonTitle = draft.imageSources.isEmpty
            ? "Choose Photos"
            : "Replace \(draft.imageSources.count) Photos"

        NavigationStack {
            Form {
                Section("What do you want to remember?") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("capture-body")
                }

                Section("Photo") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: EntryRules.maximumImageCount,
                        matching: .images
                    ) {
                        Label(
                            photoButtonTitle,
                            systemImage: "photo"
                        )
                    }
                    .accessibilityIdentifier("capture-photo-picker")

                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .disabled(
                        !UIImagePickerController.isSourceTypeAvailable(.camera)
                            || draft.imageSources.count >= EntryRules.maximumImageCount
                    )

                    if !draft.imageSources.isEmpty {
                        Label("\(draft.imageSources.count) photo(s) ready", systemImage: "checkmark.circle.fill")
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
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                load(items)
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView(
                    completion: { result in
                        isShowingCamera = false
                        switch result {
                        case .success(let source):
                            temporaryImageURLs.append(source.url)
                            draft.appendCameraImage(source)
                        case .failure(let error):
                            draft.finishImageLoad(with: .failure(error))
                        }
                    },
                    cancellation: {
                        isShowingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .onDisappear { removeTemporaryImages() }
        }
    }

    private func load(_ items: [PhotosPickerItem]) {
        draft.beginImageLoad()
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
                        .appendingPathComponent("PGOS-Capture-\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: url, options: .atomic)
                    newURLs.append(url)
                    sources.append(MediaSource(
                        url: url,
                        originalFilename: "Selected Photo.\(fileExtension)",
                        contentType: type.preferredMIMEType ?? "image/\(fileExtension)"
                    ))
                }
                removeTemporaryImages()
                temporaryImageURLs = newURLs
                draft.finishImageLoad(with: .success(sources))
            } catch {
                for url in newURLs {
                    try? FileManager.default.removeItem(at: url)
                }
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
                images: draft.imageSources
            ))
            removeTemporaryImages()
            didSave()
        } catch {
            isSaving = false
            draft.reportSaveFailure(error)
        }
    }

    private func removeTemporaryImages() {
        for url in temporaryImageURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryImageURLs = []
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let completion: (Result<MediaSource, Error>) -> Void
    let cancellation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, cancellation: cancellation)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (Result<MediaSource, Error>) -> Void
        let cancellation: () -> Void

        init(
            completion: @escaping (Result<MediaSource, Error>) -> Void,
            cancellation: @escaping () -> Void
        ) {
            self.completion = completion
            self.cancellation = cancellation
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            cancellation()
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            do {
                guard let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 1) else {
                    throw CaptureImageLoadError.noData
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PGOS-Camera-\(UUID().uuidString).jpg")
                try data.write(to: url, options: .atomic)
                completion(.success(MediaSource(
                    url: url,
                    originalFilename: "Camera Photo.jpg",
                    contentType: "image/jpeg"
                )))
            } catch {
                completion(.failure(error))
            }
            picker.dismiss(animated: true)
        }
    }
}
