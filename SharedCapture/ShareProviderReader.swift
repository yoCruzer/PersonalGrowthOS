import Foundation
import UniformTypeIdentifiers
import ImageIO

// A callback provider may never finish or may call back after cancellation. This bridge
// completes locally exactly once; cancelling Progress is best effort at the provider.
final class CaptureLoadGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var progress: Progress?
    private var timer: DispatchWorkItem?

    var isPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return result == nil
    }

    @discardableResult
    func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return false }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let progress = self.progress
        self.progress = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        if case .failure = result { progress?.cancel() }
        continuation?.resume(with: result)
        return true
    }

    private func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    private func setProgress(_ progress: Progress?) {
        lock.lock()
        if result == nil { self.progress = progress }
        let failed: Bool
        if case .failure = result { failed = true } else { failed = false }
        lock.unlock()
        if failed { progress?.cancel() }
    }

    func wait(timeout: TimeInterval, start: (CaptureLoadGate<Value>) -> Progress?) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard install(continuation) else { return }
                let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(CaptureError.providerTimedOut)) }
                lock.lock()
                let pending = result == nil
                if pending { self.timer = timer }
                lock.unlock()
                guard pending else { return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                setProgress(start(self))
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }
}

struct CaptureReadIssue: Equatable {
    let item: Int
    let reason: CaptureError
}

struct CaptureReadResult {
    var payload = ShareImportPayload()
    var files: [UUID: URL] = [:]
    var issues: [CaptureReadIssue] = []
    var thumbnail: Data?
}

struct ShareProviderReader {
    let workspace: URL
    var timeout: TimeInterval = 30

    func read(_ items: [NSExtensionItem]) async throws -> CaptureReadResult {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        var result = CaptureReadResult()
        var texts: [String] = []
        var titles: [String] = []
        var ordinal = 0
        func appendText(_ text: String?) {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !texts.contains(text) { texts.append(text) }
        }
        func appendSource(_ source: CaptureSource) {
            if result.payload.source == nil { result.payload.source = source }
            else if result.payload.source?.url != source.url {
                // One source card is supported. Preserve every other explicit URL as text,
                // and require acknowledgement of the ambiguity before saving.
                appendText(source.url)
                result.issues.append(CaptureReadIssue(item: ordinal, reason: .multipleSources))
            }
        }
        for item in items {
            var pageMetadataTitle: String?
            try Task.checkCancellation()
            if let title = item.attributedTitle?.string { titles.append(title) }
            for provider in item.attachments ?? [] {
                ordinal += 1
                CaptureLog.event("provider.types=\(provider.registeredTypeIdentifiers.joined(separator: ","))")
                let kinds = [UTType.propertyList, .image, .url, .text].filter {
                    provider.hasItemConformingToTypeIdentifier($0.identifier)
                }
                guard !kinds.isEmpty else { CaptureLog.event("provider.skipped unsupported"); continue }
                var accepted = false
                var missingImage = false
                var lastError = CaptureError.unsupportedProvider
                for kind in kinds {
                    try Task.checkCancellation()
                    do {
                        if kind == .image {
                            guard result.payload.images.count < 9 else { throw CaptureError.tooLarge }
                            let image = try await loadImage(provider)
                            result.payload.images.append(image.attachment)
                            result.files[image.attachment.id] = image.url
                            if result.thumbnail == nil { result.thumbnail = image.thumbnail }
                            // A file URL is an alternate image encoding, not a webpage source.
                            // Preserve an explicitly provided HTTP(S) URL when this provider has one.
                            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                               let url = try? await loadWebURL(provider) {
                                appendSource(CaptureSource(url: url.absoluteString, siteName: url.host,
                                    capturedAt: result.payload.createdAt, captureMode: .metadataOnly))
                            }
                        } else {
                            if kind == .url {
                                let url = try await loadWebURL(provider)
                                appendSource(CaptureSource(url: url.absoluteString, siteName: url.host,
                                    capturedAt: result.payload.createdAt, captureMode: .metadataOnly))
                                accepted = true
                                break
                            }
                            let value = try await loadItem(provider, type: kind.identifier)
                            if kind == .propertyList {
                                guard let dictionary = value as? [String: Any],
                                      let values = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
                                      let url = values["url"] as? String, CaptureSource.webURL(url) != nil else {
                                    throw CaptureError.unsupportedProvider
                                }
                                var source = CaptureSource(url: url, canonicalURL: values["canonicalURL"] as? String,
                                    title: values["title"] as? String, siteName: values["siteName"] as? String,
                                    capturedAt: result.payload.createdAt, captureMode: .metadataOnly)
                                source.normalizeMetadata()
                                pageMetadataTitle = source.title
                                appendSource(source)
                                appendText(values["selectedText"] as? String)
                            } else {
                                let text = Self.text(value)
                                guard let text else { throw CaptureError.unsupportedProvider }
                                appendText(text)
                            }
                        }
                        accepted = true
                        break // Representations of one provider are alternatives, not extra content.
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        lastError = (error as? CaptureError) ?? .unsupportedProvider
                        if kind == .image { missingImage = true }
                    }
                }
                if accepted && missingImage { result.issues.append(CaptureReadIssue(item: ordinal, reason: lastError == .tooLarge ? .tooLarge : .attachmentInvalid)) }
                if !accepted { result.issues.append(CaptureReadIssue(item: ordinal, reason: lastError)) }
            }
            // Captions are independent of attachment encodings, even when attachments exist.
            let caption = item.attributedContentText?.string
            if caption != pageMetadataTitle {
                appendText(caption)
            }
        }
        result.payload.text = texts.joined(separator: "\n\n")
        if result.payload.source == nil, let url = CaptureSource.webURL(result.payload.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            result.payload.source = CaptureSource(url: url.absoluteString, siteName: url.host,
                capturedAt: result.payload.createdAt, captureMode: .metadataOnly)
        }
        if result.payload.source?.title == nil { result.payload.source?.title = titles.first }
        if !result.payload.text.isEmpty { result.payload.source?.captureMode = .selectedContent }
        result.payload.source?.normalizeMetadata()
        try Task.checkCancellation()
        return result
    }

    private static func text(_ value: NSSecureCoding) -> String? {
        if let text = value as? String { return text }
        if let text = value as? NSAttributedString { return text.string }
        if let data = value as? Data {
            let prefix = Array(data.prefix(2))
            let encoding: String.Encoding = prefix == [0xff, 0xfe] || prefix == [0xfe, 0xff] ? .utf16 : .utf8
            return String(data: data, encoding: encoding)
        }
        return nil
    }

    private func loadWebURL(_ provider: NSItemProvider) async throws -> URL {
        if provider.canLoadObject(ofClass: NSURL.self) {
            let gate = CaptureLoadGate<URL>()
            do {
                return try await gate.wait(timeout: timeout) { gate in
                    provider.loadObject(ofClass: NSURL.self) { value, error in
                        if let error { gate.finish(.failure(error)) }
                        else if let url = value as? URL, CaptureSource.webURL(url.absoluteString) != nil {
                            gate.finish(.success(url))
                        } else { gate.finish(.failure(CaptureError.invalidURL)) }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Some legacy providers only implement the coercing interface. */ }
        }
        let value = try await loadItem(provider, type: UTType.url.identifier)
        let raw = (value as? URL)?.absoluteString ?? Self.text(value)
        guard let url = CaptureSource.webURL(raw) else { throw CaptureError.invalidURL }
        return url
    }

    func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        let gate = CaptureLoadGate<NSSecureCoding>()
        return try await gate.wait(timeout: timeout) { gate in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { gate.finish(.failure(error)) }
                else if let value { gate.finish(.success(value)) }
                else { gate.finish(.failure(CaptureError.unsupportedProvider)) }
            }
            return nil // This legacy API has no Progress return value.
        }
    }

    struct LoadedImage {
        let url: URL
        let attachment: CaptureAttachment
        let thumbnail: Data?
    }

    func loadImage(_ provider: NSItemProvider) async throws -> LoadedImage {
        let types = provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
        var lastError: Error = CaptureError.attachmentInvalid
        for type in types.isEmpty ? [UTType.image.identifier] : types {
            do { return try await loadImage(provider, type: type) }
            catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }

    private func loadImage(_ provider: NSItemProvider, type: String) async throws -> LoadedImage {
        let gate = CaptureLoadGate<URL>()
        let target = try await gate.wait(timeout: timeout) { gate in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard gate.isPending else { return }
                // The callback owns the provider URL's lifetime. Copy before returning it.
                let target = workspace.appendingPathComponent(UUID().uuidString.lowercased())
                do {
                    if let error { throw error }
                    guard let url else { throw CaptureError.attachmentInvalid }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes > 0, bytes <= 25 * 1_024 * 1_024 else { throw CaptureError.tooLarge }
                    try FileManager.default.copyItem(at: url, to: target)
                    if !gate.finish(.success(target)) { try? FileManager.default.removeItem(at: target) }
                } catch {
                    try? FileManager.default.removeItem(at: target)
                    gate.finish(.failure(error))
                }
            }
        }
        let task = Task.detached { try Self.inspectImage(at: target) }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            return result
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    private static func inspectImage(at target: URL) throws -> LoadedImage {
        try Task.checkCancellation()
        guard let id = UUID(uuidString: target.lastPathComponent),
              let source = CGImageSourceCreateWithURL(target as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?, let mime = UTType(type)?.preferredMIMEType,
              ["image/jpeg", "image/png", "image/heic", "image/heif"].contains(mime),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              height > 0, width > 0, width <= 80_000_000 / height else { throw CaptureError.attachmentInvalid }
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let attachment = CaptureAttachment(id: id, filename: target.lastPathComponent, contentType: mime,
            byteCount: Int64(size), checksum: try ShareInbox.checksum(target))
        var thumbnail: Data?
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ] as CFDictionary) {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination) { thumbnail = data as Data }
            }
        }
        try Task.checkCancellation()
        return LoadedImage(url: target, attachment: attachment, thumbnail: thumbnail)
    }
}
