import Foundation
import SwiftData

@Model
final class EntryExternalSource {
    @Attribute(.unique) var entryID: UUID
    var encodedSource: Data

    init(entryID: UUID, source: CaptureSource) throws {
        self.entryID = entryID
        encodedSource = try JSONEncoder().encode(source)
    }

    var source: CaptureSource? { try? JSONDecoder().decode(CaptureSource.self, from: encodedSource) }
}

// Kept after an Entry is deleted so a committed-but-not-cleaned share cannot resurrect it.
@Model
final class CaptureImportReceipt {
    @Attribute(.unique) var id: UUID
    var importedAt: Date
    init(id: UUID, importedAt: Date) { self.id = id; self.importedAt = importedAt }
}

@MainActor
final class ExternalCaptureImporter {
    let container: ModelContainer
    let mediaStore: MediaStore
    let inbox: ShareInbox
    var checkpoint: ((String) throws -> Void)?

    init(container: ModelContainer, mediaStore: MediaStore, inbox: ShareInbox) {
        self.container = container
        self.mediaStore = mediaStore
        self.inbox = inbox
    }

    // Synchronous on MainActor to serialize scans; a private context cannot save/rollback editor drafts.
    func scan() throws -> Int {
        var failed = 0
        for directory in try inbox.pending() {
            CaptureLog.event("inbox.discovered")
            do { try consume(directory) }
            catch {
                failed += 1
                let reason = (error as? CaptureError)?.rawValue ?? String(describing: type(of: error))
                CaptureLog.event("import.retained reason=\(reason)")
            }
        }
        return failed
    }

    func consume(_ directory: URL) throws {
        guard let id = UUID(uuidString: directory.lastPathComponent) else { throw CaptureError.invalidPayload }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let receipt = try context.fetch(FetchDescriptor<CaptureImportReceipt>(predicate: #Predicate { $0.id == id })).first
        if receipt != nil {
            CaptureLog.event("import.alreadyCommitted", id: id)
            try inbox.remove(directory)
            return
        }
        // Cleanup may have been interrupted after deleting some files; a receipt is authoritative.
        let payload = try inbox.read(directory)
        guard try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).isEmpty else {
            throw CaptureError.invalidPayload
        }
        CaptureLog.event("import.started", id: id)
        var stored: [StoredMediaFile] = []
        do {
            let sources = payload.images.map {
                MediaSource(url: directory.appendingPathComponent($0.filename), originalFilename: $0.filename, contentType: $0.contentType)
            }
            try mediaStore.ensureCapacity(for: sources)
            for source in sources {
                stored.append(try mediaStore.storeOriginal(source))
                CaptureLog.event("attachment.copied count=\(stored.count)", id: id)
                try checkpoint?("attachment")
            }
            let images = zip(stored, payload.images).enumerated().map { index, pair in
                ImageMetadata(id: pair.0.id, relativePath: pair.0.relativePath,
                              originalFilename: pair.1.filename, contentType: pair.1.contentType,
                              byteCount: pair.0.byteCount, pixelWidth: pair.0.pixelWidth,
                              pixelHeight: pair.0.pixelHeight, checksum: pair.0.checksum,
                              sortOrder: index, createdAt: payload.createdAt)
            }
            let body = payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? payload.source?.url : payload.text
            try EntryRules.validateContent(body: body, imageCount: images.count)
            let entry = Entry(id: id, title: payload.source?.title, body: body,
                              createdAt: Date(), occurredAt: payload.createdAt, images: images)
            images.forEach { $0.entry = entry }
            context.insert(entry)
            if let source = payload.source { context.insert(try EntryExternalSource(entryID: id, source: source)) }
            context.insert(CaptureImportReceipt(id: id, importedAt: Date()))
            try checkpoint?("beforeSave")
            try context.save()
        } catch {
            context.rollback()
            for file in stored { try mediaStore.removeOriginal(at: file.relativePath) }
            throw error
        }
        // A failure here must never roll back committed media. Receipt makes the retry cleanup-only.
        CaptureLog.event("import.committed", id: id)
        try checkpoint?("afterSave")
        try inbox.remove(directory)
        CaptureLog.event("inbox.cleaned", id: id)
    }
}
