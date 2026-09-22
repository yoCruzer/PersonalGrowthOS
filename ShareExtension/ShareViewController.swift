import UIKit
import UniformTypeIdentifiers
import ImageIO
import LinkPresentation

final class ShareViewController: UIViewController {
    private let editor = UITextView()
    private let sourceLabel = UILabel()
    private let statusLabel = UILabel()
    private let preview = UIImageView()
    private let saveButton = UIButton(type: .system)
    private var payload = ShareImportPayload()
    private var files: [UUID: URL] = [:]
    private var metadataProvider: LPMetadataProvider?
    private var finished = false
    private let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let cancel = UIButton(type: .system)
        cancel.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        saveButton.setTitle(NSLocalizedString("Save", comment: ""), for: .normal)
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveCapture), for: .touchUpInside)
        let toolbar = UIStackView(arrangedSubviews: [cancel, UIView(), saveButton])
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        editor.font = .preferredFont(forTextStyle: .body)
        editor.accessibilityIdentifier = "share-text"
        sourceLabel.numberOfLines = 3
        sourceLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        preview.contentMode = .scaleAspectFit
        preview.heightAnchor.constraint(equalToConstant: 100).isActive = true
        preview.isHidden = true
        let stack = UIStackView(arrangedSubviews: [toolbar, sourceLabel, preview, editor, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
        Task { await load() }
    }

    @MainActor private func load() async {
        do {
            _ = try ShareInbox.shared()
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
            var texts: [String] = []
            var selectedText: String?
            for item in items {
                for provider in item.attachments ?? [] {
                    CaptureLog.event("provider.types=\(provider.registeredTypeIdentifiers.joined(separator: ","))")
                    if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                        CaptureLog.event("provider.selected propertyList")
                        if let dictionary = try? await loadItem(provider, type: UTType.propertyList.identifier) as? [String: Any],
                           let values = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                            if let url = values["url"] as? String, CaptureSource.webURL(url) != nil {
                                payload.source = CaptureSource(url: url,
                                    canonicalURL: CaptureSource.webURL(values["canonicalURL"] as? String)?.absoluteString,
                                    title: (values["title"] as? String).map { String($0.prefix(8_000)) },
                                    siteName: (values["siteName"] as? String).map { String($0.prefix(1_000)) },
                                    capturedAt: payload.createdAt, captureMode: .metadataOnly)
                            }
                            selectedText = values["selectedText"] as? String
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        CaptureLog.event("provider.selected image")
                        try await loadImage(provider)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        CaptureLog.event("provider.selected url")
                        let value = try await loadItem(provider, type: UTType.url.identifier)
                        let raw = (value as? URL)?.absoluteString ?? (value as? String)
                        if let url = CaptureSource.webURL(raw), payload.source == nil {
                            payload.source = CaptureSource(url: url.absoluteString, siteName: url.host,
                                capturedAt: payload.createdAt, captureMode: .metadataOnly)
                        } else if let raw, CaptureSource.webURL(raw) == nil { texts.append(raw) }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                        CaptureLog.event("provider.selected text")
                        let value = try await loadItem(provider, type: UTType.text.identifier)
                        if let text = value as? String { texts.append(text) }
                        else if let text = value as? NSAttributedString { texts.append(text.string) }
                        else { throw CaptureError.unsupportedProvider }
                    } else {
                        throw CaptureError.unsupportedProvider
                    }
                }
                if (item.attachments ?? []).isEmpty, let text = item.attributedContentText?.string { texts.append(text) }
                if payload.source?.title == nil, let title = item.attributedTitle?.string {
                    payload.source?.title = String(title.prefix(8_000))
                }
            }
            guard !finished else { return }
            payload.text = texts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: "\n\n")
            if let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload.text = selectedText
                payload.source?.captureMode = .selectedContent
            }
            if payload.source == nil, let url = CaptureSource.webURL(payload.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                payload.source = CaptureSource(url: url.absoluteString, siteName: url.host,
                    capturedAt: payload.createdAt, captureMode: .metadataOnly)
            }
            try payload.validate()
            editor.text = payload.text
            updateSource()
            statusLabel.text = NSLocalizedString("Saved shares appear when you next open 随心log.", comment: "")
            saveButton.isEnabled = true
            fetchMetadata()
        } catch {
            guard !finished else { return }
            CaptureLog.event("provider.failed type=\(String(describing: type(of: error)))")
            statusLabel.text = NSLocalizedString("Unable to read this share. Try sharing text, a webpage, or up to 9 photos (25 MB each).", comment: "")
        }
    }

    private func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let item { continuation.resume(returning: item) }
                else { continuation.resume(throwing: CaptureError.unsupportedProvider) }
            }
        }
    }

    private func loadImage(_ provider: NSItemProvider) async throws {
        guard payload.images.count < 9 else { throw CaptureError.tooLarge }
        let id = UUID()
        let target = workspace.appendingPathComponent(id.uuidString.lowercased())
        // Copy inside the provider callback: its temporary URL expires when the callback returns.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CaptureError.attachmentInvalid }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes > 0, bytes <= 25 * 1_024 * 1_024 else { throw CaptureError.tooLarge }
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        guard !finished else { try? FileManager.default.removeItem(at: target); return }
        guard let source = CGImageSourceCreateWithURL(target as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              let mime = UTType(type)?.preferredMIMEType,
              ["image/jpeg", "image/png", "image/heic", "image/heif"].contains(mime),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              height > 0, width > 0, width <= 80_000_000 / height else { throw CaptureError.attachmentInvalid }
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        payload.images.append(CaptureAttachment(id: id, filename: target.lastPathComponent,
            contentType: mime, byteCount: Int64(size), checksum: try ShareInbox.checksum(target)))
        files[id] = target
        if preview.image == nil, let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ] as CFDictionary) {
            preview.image = UIImage(cgImage: thumbnail)
            preview.isHidden = false
        }
    }

    private func updateSource() {
        sourceLabel.text = [payload.source?.title, payload.source?.url].compactMap { $0 }.joined(separator: "\n")
    }

    private func fetchMetadata() {
        guard let source = payload.source, source.title?.isEmpty != false,
              let url = CaptureSource.webURL(source.url) else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 3
        provider.shouldFetchSubresources = false
        metadataProvider = provider
        CaptureLog.event("metadata.started", id: payload.id)
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                if let metadata {
                    self.payload.source?.title = metadata.title.map { String($0.prefix(8_000)) }
                    self.payload.source?.canonicalURL = CaptureSource.webURL(metadata.url?.absoluteString)?.absoluteString
                    self.updateSource()
                }
                CaptureLog.event(error == nil ? "metadata.completed" : "metadata.fallback", id: self.payload.id)
            }
        }
    }

    @objc private func saveCapture() {
        guard !finished else { return }
        saveButton.isEnabled = false
        payload.text = editor.text
        if !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           payload.text != payload.source?.url {
            payload.source?.captureMode = .selectedContent
        }
        do {
            try ShareInbox.shared().publish(payload, files: files)
            finished = true
            metadataProvider?.cancel()
            try? FileManager.default.removeItem(at: workspace)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            saveButton.isEnabled = true
            CaptureLog.event("inbox.saveFailed type=\(String(describing: type(of: error)))", id: payload.id)
            statusLabel.text = NSLocalizedString("Could not save. Your share is still here; please retry or cancel.", comment: "")
        }
    }

    @objc private func cancelCapture() {
        finished = true
        metadataProvider?.cancel()
        try? FileManager.default.removeItem(at: workspace)
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
