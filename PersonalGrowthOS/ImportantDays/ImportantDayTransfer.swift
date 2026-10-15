import Foundation
import SwiftData

/// Common media transport fields; covers remain separate facts and never become synthetic Entries.
protocol TransferMediaAsset {
    var id: UUID { get }
    var relativePath: String { get }
    var mediaPath: String { get }
    var originalFilename: String { get }
    var contentType: String { get }
    var byteCount: Int64 { get }
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    var checksum: String { get }
}
extension ImageTransfer: TransferMediaAsset {}
struct ImportantDayTransfer: Codable, Equatable {
    let id: UUID
    let title: String
    let notes: String
    let rule: ImportantDayDateRule
    let preferences: ImportantDayPreferences
    let isArchived: Bool
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    let revision: Int
    init(_ day: ImportantDay) throws {
        id = day.id; title = day.title; notes = day.notes; rule = try day.rule(); preferences = try day.preferences()
        isArchived = day.isArchived; createdAt = day.createdAt; updatedAt = day.updatedAt; revision = day.revision
    }
    func model() throws -> ImportantDay {
        let day = try ImportantDay(id: id, title: title, notes: notes, rule: rule, preferences: preferences, createdAt: createdAt)
        day.isArchived = isArchived; day.updatedAt = updatedAt; day.revision = revision; return day
    }
}
struct ImportantDayEntryLinkTransfer: Codable, Equatable {
    let id: UUID; let dayID: UUID; let entryID: UUID; let occurrenceIdentifier: String?; @TodoTransferInstant var createdAt: Date
    init(_ link: ImportantDayEntryLink) { id = link.id; dayID = link.dayID; entryID = link.entryID; occurrenceIdentifier = link.occurrenceIdentifier; createdAt = link.createdAt }
    func model() -> ImportantDayEntryLink {
        let link = ImportantDayEntryLink(id: id, dayID: dayID, entryID: entryID, createdAt: createdAt)
        link.occurrenceIdentifier = occurrenceIdentifier; return link
    }
}
struct ImportantDayTodoLinkTransfer: Codable, Equatable {
    let id: UUID; let dayID: UUID; let taskID: UUID; let occurrenceIdentifier: String?; let dayRevisionAtLink: Int; @TodoTransferInstant var createdAt: Date
    init(_ link: ImportantDayTodoLink) { id = link.id; dayID = link.dayID; taskID = link.taskID; occurrenceIdentifier = link.occurrenceIdentifier; dayRevisionAtLink = link.dayRevisionAtLink; createdAt = link.createdAt }
    func model() -> ImportantDayTodoLink {
        let link = ImportantDayTodoLink(id: id, dayID: dayID, taskID: taskID, dayRevisionAtLink: dayRevisionAtLink, createdAt: createdAt)
        link.occurrenceIdentifier = occurrenceIdentifier; return link
    }
}
struct ImportantDayCoverTransfer: Codable, Equatable, TransferMediaAsset {
    let id: UUID; let dayID: UUID; let relativePath: String; let mediaPath: String
    let originalFilename: String; let contentType: String; let byteCount: Int64
    let pixelWidth: Int; let pixelHeight: Int; let checksum: String; @TodoTransferInstant var createdAt: Date
    init(_ cover: ImportantDayCover) {
        id = cover.id; dayID = cover.dayID; relativePath = cover.relativePath
        mediaPath = "media/cover-\(cover.id.uuidString.lowercased()).\(URL(fileURLWithPath: cover.relativePath).pathExtension)"
        originalFilename = cover.originalFilename; contentType = cover.contentType; byteCount = cover.byteCount
        pixelWidth = cover.pixelWidth; pixelHeight = cover.pixelHeight; checksum = cover.checksum; createdAt = cover.createdAt
    }
    func model() -> ImportantDayCover {
        ImportantDayCover(dayID: dayID, stored: StoredMediaFile(id: id, relativePath: relativePath, byteCount: byteCount,
            checksum: checksum, pixelWidth: pixelWidth, pixelHeight: pixelHeight),
            source: MediaSource(url: URL(fileURLWithPath: "/"), originalFilename: originalFilename, contentType: contentType), createdAt: createdAt)
    }
}
extension TransferData {
    var mediaAssets: [any TransferMediaAsset] { images.map { $0 as any TransferMediaAsset } + importantDayCovers.map { $0 as any TransferMediaAsset } }
    func validateImportantDays(packageVersion: Int, manifest: ExportManifest) throws {
        guard packageVersion >= 8 || (importantDays.isEmpty && importantDayEntryLinks.isEmpty && importantDayTodoLinks.isEmpty && importantDayCovers.isEmpty) else { throw TransferPackageError.invalidObject("important day schema") }
        func unique(_ ids: [UUID]) throws {
            guard Set(ids).count == ids.count else { throw TransferPackageError.duplicateID("important day") }
        }
        try unique(importantDays.map(\.id)); try unique(importantDayEntryLinks.map(\.id)); try unique(importantDayTodoLinks.map(\.id)); try unique(mediaAssets.map(\.id)); try unique(importantDayCovers.map(\.dayID))
        let dayIDs = Set(importantDays.map(\.id)), entryIDs = Set(entries.map(\.id)), taskIDs = Set(todoTasks.map(\.id))
        for day in importantDays {
            let name = day.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, day.notes.count <= 4000,
                  day.createdAt.timeIntervalSince1970.isFinite, day.updatedAt.timeIntervalSince1970.isFinite,
                  day.updatedAt >= day.createdAt, day.revision >= 0 else { throw TransferPackageError.invalidObject("important day") }
            do { try day.rule.validate(); try day.preferences.validate() } catch { throw TransferPackageError.invalidObject("important day rules") }
        }
        var pairs = Set<String>()
        for link in importantDayEntryLinks {
            guard dayIDs.contains(link.dayID), entryIDs.contains(link.entryID), ImportantDayIntegrity.validOccurrence(link.occurrenceIdentifier),
                  link.createdAt.timeIntervalSince1970.isFinite,
                  pairs.insert("\(link.dayID):\(link.entryID)").inserted else { throw TransferPackageError.invalidObject("important day entry link") }
        }
        pairs = []
        for link in importantDayTodoLinks {
            guard dayIDs.contains(link.dayID), taskIDs.contains(link.taskID), ImportantDayIntegrity.validOccurrence(link.occurrenceIdentifier),
                  link.createdAt.timeIntervalSince1970.isFinite, link.dayRevisionAtLink >= 0,
                  pairs.insert("\(link.dayID):\(link.taskID)").inserted else { throw TransferPackageError.invalidObject("important day todo link") }
        }
        let media = Dictionary(grouping: manifest.mediaFiles, by: \.imageID)
        for cover in importantDayCovers {
            guard dayIDs.contains(cover.dayID), cover.byteCount > 0, cover.byteCount <= MediaStore.maximumOriginalByteCount,
                  cover.pixelWidth > 0, cover.pixelHeight > 0, cover.pixelWidth <= MediaStore.maximumPixelCount / cover.pixelHeight,
                  cover.createdAt.timeIntervalSince1970.isFinite,
                  cover.checksum.count == 64, cover.checksum.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  let record = media[cover.id], record.count == 1,
                  record[0].path == cover.mediaPath, record[0].byteCount == cover.byteCount, record[0].sha256 == cover.checksum,
                  cover.relativePath == (try? MediaStore(rootURL: URL(fileURLWithPath: "/tmp")).originalRelativePath(id: cover.id, contentType: cover.contentType)) else {
                throw TransferPackageError.invalidObject("important day cover")
            }
        }
    }
    func insertImportantDays(into context: ModelContext) throws {
        for record in importantDays { try Task.checkCancellation(); context.insert(try record.model()) }
        for record in importantDayEntryLinks { try Task.checkCancellation(); context.insert(record.model()) }
        for record in importantDayTodoLinks { try Task.checkCancellation(); context.insert(record.model()) }
        for record in importantDayCovers { try Task.checkCancellation(); context.insert(record.model()) }
    }
}
