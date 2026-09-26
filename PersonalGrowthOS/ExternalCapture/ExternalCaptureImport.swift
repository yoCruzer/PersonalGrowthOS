import Foundation
import SwiftData

extension Notification.Name {
    static let externalCaptureCommitted = Notification.Name("ExternalCaptureCommitted")
}

// All operations execute synchronously on a worker while holding this store's lease.
// No await occurs inside the lease, so actor reentrancy cannot publish a second operation.
enum StorePublication {
    private static let registryLock = NSLock()
    private static var locks: [URL: NSLock] = [:]

    static func perform<T>(at root: URL, _ operation: () throws -> T) throws -> T {
        let key = root.standardizedFileURL.resolvingSymlinksInPath()
        registryLock.lock()
        let lock = locks[key] ?? NSLock()
        locks[key] = lock
        registryLock.unlock()
        lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        return try operation()
    }
}

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

enum CaptureInboxReason: String, Codable {
    case pending, unsupportedVersion, invalidContent, storage, cleanup, other

    var title: String {
        switch self {
        case .pending: return String(localized: "Waiting to import")
        case .unsupportedVersion: return String(localized: "Requires a newer app version")
        case .invalidContent: return String(localized: "Shared content or photo is invalid")
        case .storage: return String(localized: "Not enough storage")
        case .cleanup: return String(localized: "Imported; pending file cleanup")
        case .other: return String(localized: "Import needs attention")
        }
    }
}

struct CaptureInboxItem: Identifiable {
    let id: String
    let createdAt: Date?
    let reason: CaptureInboxReason
    let isCommitted: Bool
    let isDeferred: Bool
}

struct CaptureScanReport {
    var failed = 0
    var newFailureIDs: [String] = []
    var pendingCount = 0
}

private struct CaptureFailureRecord: Codable {
    var reason: CaptureInboxReason
    var deferredVersion: String?
}

@MainActor
final class ExternalCaptureImporter {
    let container: ModelContainer
    let mediaStore: MediaStore
    let inbox: ShareInbox
    var checkpoint: ((String) throws -> Void)?
    var processingVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")/\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")/capture1"

    init(container: ModelContainer, mediaStore: MediaStore, inbox: ShareInbox) {
        self.container = container
        self.mediaStore = mediaStore
        self.inbox = inbox
    }

    func scan() async throws -> Int { try await scanReport().failed }
    func scanReport() async throws -> CaptureScanReport { try await run { try $0.scan() } }
    func consume(_ directory: URL) async throws { try await run { try $0.consume(directory) } }
    func pendingItems() async throws -> [CaptureInboxItem] { try await run { try $0.pendingItems() } }
    func keepForLater(_ ids: [String]) async throws { try await run { try $0.keepForLater(ids) } }
    func retry(_ id: String) async throws { try await run { try $0.retry(id) } }
    func discardPending(_ id: String) async throws { try await run { try $0.discardPending(id) } }

    private func run<T>(_ operation: @escaping (CaptureImportWorker) throws -> T) async throws -> T {
        let worker = CaptureImportWorker(container: container, mediaStore: mediaStore,
            inbox: inbox, checkpoint: checkpoint, processingVersion: processingVersion)
        let task = Task.detached {
            try worker.checkpoint?("scheduled")
            return try StorePublication.perform(at: worker.mediaStore.rootURL) { try operation(worker) }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

private struct CaptureImportWorker {
    let container: ModelContainer
    let mediaStore: MediaStore
    let inbox: ShareInbox
    let checkpoint: ((String) throws -> Void)?
    let processingVersion: String

    func scan() throws -> CaptureScanReport {
        _ = try CaptureStagingSession.reclaimAbandoned(root: inbox.root)
        var report = CaptureScanReport()
        var state = try readState()
        for directory in try inbox.pending() {
            try Task.checkCancellation()
            let id = directory.lastPathComponent
            if state[id]?.deferredVersion == processingVersion { continue }
            CaptureLog.event("inbox.discovered")
            do {
                try consume(directory)
                state.removeValue(forKey: id)
            } catch is CancellationError { throw CancellationError() }
            catch {
                report.failed += 1
                let reason = try failureReason(error, id: id)
                if state[id]?.reason != reason { report.newFailureIDs.append(id) }
                state[id] = CaptureFailureRecord(reason: reason)
                CaptureLog.event("import.retained reason=\(reason.rawValue)")
            }
        }
        let pending = try inbox.pending()
        report.pendingCount = pending.count
        let liveIDs = Set(pending.map(\.lastPathComponent))
        try writeState(state.filter { liveIDs.contains($0.key) })
        return report
    }

    private var stateURL: URL { mediaStore.rootURL.appendingPathComponent("CaptureInboxState.json") }

    private func readState() throws -> [String: CaptureFailureRecord] {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return [:] }
        return try JSONDecoder().decode([String: CaptureFailureRecord].self, from: Data(contentsOf: stateURL))
    }

    private func writeState(_ state: [String: CaptureFailureRecord]) throws {
        try FileManager.default.createDirectory(at: mediaStore.rootURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func hasReceipt(_ name: String) throws -> Bool {
        guard let id = UUID(uuidString: name) else { return false }
        return try ModelContext(container).fetchCount(FetchDescriptor<CaptureImportReceipt>(predicate: #Predicate { $0.id == id })) > 0
    }

    private func failureReason(_ error: Error, id: String) throws -> CaptureInboxReason {
        if try hasReceipt(id) { return .cleanup }
        if error as? CaptureError == .unsupportedSchema { return .unsupportedVersion }
        if error is CaptureError || error is DecodingError { return .invalidContent }
        if case MediaStoreError.insufficientCapacity = error { return .storage }
        let underlying = error as NSError
        if (underlying.domain == NSCocoaErrorDomain && underlying.code == NSFileWriteOutOfSpaceError)
            || (underlying.domain == NSPOSIXErrorDomain && underlying.code == 28) { return .storage }
        return .other
    }

    func pendingItems() throws -> [CaptureInboxItem] {
        let state = try readState()
        return try inbox.pending().map { directory in
            let id = directory.lastPathComponent
            let committed = try hasReceipt(id)
            return CaptureInboxItem(id: id,
                createdAt: try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate,
                reason: committed ? .cleanup : (state[id]?.reason ?? .pending),
                isCommitted: committed, isDeferred: state[id]?.deferredVersion == processingVersion)
        }
    }

    func keepForLater(_ ids: [String]) throws {
        var state = try readState()
        let live = Set(try inbox.pending().map(\.lastPathComponent))
        for id in ids where live.contains(id) {
            var record = state[id] ?? CaptureFailureRecord(reason: .pending)
            record.deferredVersion = processingVersion
            state[id] = record
        }
        try writeState(state)
    }

    private func directory(_ id: String) throws -> URL? {
        try inbox.pending().first { $0.lastPathComponent == id }
    }

    func retry(_ id: String) throws {
        guard let directory = try directory(id) else { return }
        var state = try readState()
        do {
            try consume(directory)
            state.removeValue(forKey: id)
            try writeState(state)
        } catch {
            state[id] = CaptureFailureRecord(reason: try failureReason(error, id: id))
            try writeState(state)
            throw error
        }
    }

    func discardPending(_ id: String) throws {
        guard let directory = try directory(id) else { return }
        // Only the selected Pending copy is removed, never an Entry or its receipt.
        try inbox.remove(directory)
        var state = try readState()
        state.removeValue(forKey: id)
        try writeState(state)
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
                try Task.checkCancellation()
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
            try Task.checkCancellation()
            try context.save()
        } catch {
            context.rollback()
            for file in stored {
                do { try mediaStore.removeOriginal(at: file.relativePath) }
                catch { CaptureLog.event("attachment.cleanupFailed", id: id) }
            }
            throw error
        }
        // A failure here must never roll back committed media. Receipt makes the retry cleanup-only.
        CaptureLog.event("import.committed", id: id)
        NotificationCenter.default.post(name: .externalCaptureCommitted, object: mediaStore.rootURL)
        try checkpoint?("afterSave")
        try inbox.remove(directory)
        CaptureLog.event("inbox.cleaned", id: id)
    }
}
