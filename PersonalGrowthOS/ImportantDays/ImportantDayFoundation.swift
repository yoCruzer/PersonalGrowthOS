import Foundation
import SwiftData

struct ImportantDayPreferences: Codable, Equatable, Sendable {
    var today: ImportantDayTodayPolicy = .automatic
    var favoriteOrder: Int?
    var reminderOffsets: [Int] = []
    var reminderMinutes = 9 * 60
    var genericNotification = true
    var desktopVisible = false
    var photoStyle = false
    var cropX = 0.5
    var cropY = 0.5
    func validate() throws {
        guard reminderOffsets.count <= 2, Set(reminderOffsets).count == reminderOffsets.count,
              reminderOffsets.allSatisfy({ [0, 1, 3, 7].contains($0) }),
              (0..<1440).contains(reminderMinutes), favoriteOrder.map({ $0 >= 0 }) ?? true,
              cropX.isFinite, cropY.isFinite, (0...1).contains(cropX), (0...1).contains(cropY) else {
            throw ImportantDayError.invalidPreferences
        }
    }
}
enum ImportantDayError: Error, Equatable { case invalidTitle, invalidPreferences, missingDay, missingEndpoint, duplicateRelation, invalidData }

/// Additive models only: no properties are added to historical Entry/Todo schemas.
@Model
final class ImportantDay {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var ruleData: Data
    var preferencesData: Data
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    init(id: UUID = UUID(), title: String, notes: String = "", rule: ImportantDayDateRule,
         preferences: ImportantDayPreferences = .init(), createdAt: Date = Date()) throws {
        self.id = id; self.title = title; self.notes = notes
        ruleData = try JSONEncoder().encode(rule); preferencesData = try JSONEncoder().encode(preferences)
        isArchived = false; self.createdAt = createdAt; updatedAt = createdAt; revision = 0
    }
    func rule() throws -> ImportantDayDateRule { try JSONDecoder().decode(ImportantDayDateRule.self, from: ruleData) }
    func preferences() throws -> ImportantDayPreferences { try JSONDecoder().decode(ImportantDayPreferences.self, from: preferencesData) }
}

@Model
final class ImportantDayEntryLink {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var pairKey: String
    var dayID: UUID
    var entryID: UUID
    /// Explicit actual Gregorian occurrence; nil means the day itself, never guessed from Entry time.
    var occurrenceIdentifier: String?
    var createdAt: Date
    init(id: UUID = UUID(), dayID: UUID, entryID: UUID, occurrence: ImportantCivilDay? = nil, createdAt: Date = Date()) {
        self.id = id; self.dayID = dayID; self.entryID = entryID
        pairKey = dayID.uuidString.lowercased() + ":" + entryID.uuidString.lowercased()
        occurrenceIdentifier = occurrence?.identifier; self.createdAt = createdAt
    }
}
@Model
final class ImportantDayTodoLink {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var pairKey: String
    var dayID: UUID
    var taskID: UUID
    var occurrenceIdentifier: String?
    var dayRevisionAtLink: Int
    var createdAt: Date
    init(id: UUID = UUID(), dayID: UUID, taskID: UUID, occurrence: ImportantCivilDay? = nil,
         dayRevisionAtLink: Int, createdAt: Date = Date()) {
        self.id = id; self.dayID = dayID; self.taskID = taskID
        pairKey = dayID.uuidString.lowercased() + ":" + taskID.uuidString.lowercased()
        occurrenceIdentifier = occurrence?.identifier; self.dayRevisionAtLink = dayRevisionAtLink; self.createdAt = createdAt
    }
}
@Model
final class ImportantDayCover {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dayID: UUID
    var relativePath: String
    var originalFilename: String
    var contentType: String
    var byteCount: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var checksum: String
    var createdAt: Date
    init(dayID: UUID, stored: StoredMediaFile, source: MediaSource, createdAt: Date = Date()) {
        id = stored.id; self.dayID = dayID; relativePath = stored.relativePath
        originalFilename = source.originalFilename; contentType = source.contentType
        byteCount = stored.byteCount; pixelWidth = stored.pixelWidth; pixelHeight = stored.pixelHeight
        checksum = stored.checksum; self.createdAt = createdAt
    }
}

struct ImportantDayDraft {
    var title = ""
    var notes = ""
    var rule = ImportantDayDateRule()
    var preferences = ImportantDayPreferences()
    var archived = false
    init() {}
    init(_ day: ImportantDay) throws {
        title = day.title; notes = day.notes; rule = try day.rule(); preferences = try day.preferences(); archived = day.isArchived
    }
    func validate() throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, notes.count <= 4000 else { throw ImportantDayError.invalidTitle }
        try rule.validate(); try preferences.validate()
    }
}

@MainActor
final class ImportantDayService {
    private let context: ModelContext
    private let mediaStore: MediaStore
    private let now: () -> Date
    private let commit: () throws -> Void
    init(context: ModelContext, mediaStore: MediaStore, now: @escaping () -> Date = Date.init, commit: (() throws -> Void)? = nil) {
        self.context = context; self.mediaStore = mediaStore; self.now = now; self.commit = commit ?? { try context.save() }
    }
    func day(id: UUID) throws -> ImportantDay {
        guard let day = try context.fetch(FetchDescriptor<ImportantDay>(predicate: #Predicate { $0.id == id })).first else { throw ImportantDayError.missingDay }
        return day
    }
    /// One commit for the day, optional source link and independent cover. Failed saves remove only this operation's new file.
    @discardableResult
    func save(_ draft: ImportantDayDraft, id: UUID = UUID(), sourceEntryID: UUID? = nil,
              coverSource: MediaSource? = nil, removeCover: Bool = false) throws -> ImportantDay {
        try draft.validate()
        return try StorePublication.perform(at: mediaStore.rootURL) {
            var newFile: StoredMediaFile?
            var retiredPath: String?
            do {
                let existing = try context.fetch(FetchDescriptor<ImportantDay>(predicate: #Predicate { $0.id == id })).first
                let day = try existing ?? ImportantDay(id: id, title: draft.title, rule: draft.rule, createdAt: now())
                let changedDate = try day.rule() != draft.rule
                day.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines); day.notes = draft.notes
                day.ruleData = try JSONEncoder().encode(draft.rule); day.preferencesData = try JSONEncoder().encode(draft.preferences)
                day.isArchived = draft.archived
                day.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: day.createdAt, previous: day.updatedAt)
                if changedDate { day.revision += 1 }
                context.insert(day)
                if let sourceEntryID { try linkEntry(dayID: id, entryID: sourceEntryID, save: false) }
                if coverSource != nil || removeCover {
                    let old = try context.fetch(FetchDescriptor<ImportantDayCover>(predicate: #Predicate { $0.dayID == id })).first
                    if let old { retiredPath = old.relativePath; context.delete(old) }
                    if let coverSource {
                        let stored = try mediaStore.storeOriginal(coverSource); newFile = stored
                        context.insert(ImportantDayCover(dayID: id, stored: stored, source: coverSource, createdAt: now()))
                    }
                }
                try commit()
                if let retiredPath { try? mediaStore.removeOriginal(at: retiredPath) }
                NotificationCenter.default.post(name: .importantDaysChanged, object: context.container)
                return day
            } catch {
                context.rollback(); if let newFile { try? mediaStore.removeOriginal(at: newFile.relativePath) }; throw error
            }
        }
    }
    func linkEntry(dayID: UUID, entryID: UUID, occurrence: ImportantCivilDay? = nil, save: Bool = true) throws {
        _ = try day(id: dayID)
        guard try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })).first != nil else { throw ImportantDayError.missingEndpoint }
        if let occurrence, occurrence.date == nil { throw ImportantDayError.invalidData }
        let links = try context.fetch(FetchDescriptor<ImportantDayEntryLink>(predicate: #Predicate { $0.dayID == dayID && $0.entryID == entryID }))
        // Retrying an already successful association is idempotent; explicit period can be updated.
        if let existing = links.first { existing.occurrenceIdentifier = occurrence?.identifier }
        else { context.insert(ImportantDayEntryLink(dayID: dayID, entryID: entryID, occurrence: occurrence, createdAt: now())) }
        if save { do { try commit() } catch { context.rollback(); throw error } }
    }
    func createEntry(_ draft: EntryCreationDraft, dayID: UUID, occurrence: ImportantCivilDay? = nil) throws -> Entry {
        let day = try day(id: dayID)
        guard !day.isArchived, occurrence.map({ $0.date != nil }) ?? true else { throw ImportantDayError.missingDay }
        let persistence = ImportantDayLinkedEntryPersistence(context: context, dayID: dayID, occurrence: occurrence, commit: commit)
        return try StorePublication.perform(at: mediaStore.rootURL) {
            try EntryCreationService(persistence: persistence, mediaStore: mediaStore, now: now).create(draft)
        }
    }
    func unlinkEntry(dayID: UUID, entryID: UUID) throws {
        do {
            try context.fetch(FetchDescriptor<ImportantDayEntryLink>(predicate: #Predicate { $0.dayID == dayID && $0.entryID == entryID })).forEach(context.delete)
            try commit()
        } catch { context.rollback(); throw error }
    }
    func delete(id: UUID) throws {
        try StorePublication.perform(at: mediaStore.rootURL) {
            let object = try day(id: id)
            let covers = try context.fetch(FetchDescriptor<ImportantDayCover>(predicate: #Predicate { $0.dayID == id }))
            do {
                try context.fetch(FetchDescriptor<ImportantDayEntryLink>(predicate: #Predicate { $0.dayID == id })).forEach(context.delete)
                try context.fetch(FetchDescriptor<ImportantDayTodoLink>(predicate: #Predicate { $0.dayID == id })).forEach(context.delete)
                covers.forEach(context.delete); context.delete(object); try commit()
            } catch { context.rollback(); throw error }
            for cover in covers { try? mediaStore.removeOriginal(at: cover.relativePath) }
            NotificationCenter.default.post(name: .importantDaysChanged, object: context.container)
        }
    }
}

extension Notification.Name { static let importantDaysChanged = Notification.Name("ImportantDaysChanged") }

/// Shared by startup/export and tests. Invalid facts are preserved by existing startup recovery.
enum ImportantDayIntegrity {
    static func validate(context: ModelContext) throws {
        let days = try context.fetch(FetchDescriptor<ImportantDay>())
        for day in days {
            try ImportantDayDraft(day).validate()
            guard day.updatedAt >= day.createdAt, day.revision >= 0 else { throw ImportantDayError.invalidData }
        }
        let ids = Set(days.map(\.id)), entries = Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id))
        let tasks = Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.id))
        for link in try context.fetch(FetchDescriptor<ImportantDayEntryLink>()) {
            guard ids.contains(link.dayID), entries.contains(link.entryID),
                  link.pairKey == link.dayID.uuidString.lowercased() + ":" + link.entryID.uuidString.lowercased(),
                  validOccurrence(link.occurrenceIdentifier) else { throw ImportantDayError.missingEndpoint }
        }
        for link in try context.fetch(FetchDescriptor<ImportantDayTodoLink>()) {
            guard ids.contains(link.dayID), tasks.contains(link.taskID), link.dayRevisionAtLink >= 0,
                  link.pairKey == link.dayID.uuidString.lowercased() + ":" + link.taskID.uuidString.lowercased(),
                  validOccurrence(link.occurrenceIdentifier) else { throw ImportantDayError.missingEndpoint }
        }
        for cover in try context.fetch(FetchDescriptor<ImportantDayCover>()) {
            guard ids.contains(cover.dayID) else { throw ImportantDayError.missingEndpoint }
        }
    }
    static func validOccurrence(_ text: String?) -> Bool {
        guard let text else { return true }
        let p = text.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return false }
        let day = ImportantCivilDay(year: p[0], month: p[1], day: p[2])
        return day.date != nil && day.identifier == text
    }
}

@MainActor
private final class ImportantDayLinkedEntryPersistence: EntryPersisting {
    let context: ModelContext
    let dayID: UUID
    let occurrence: ImportantCivilDay?
    let commit: () throws -> Void
    init(context: ModelContext, dayID: UUID, occurrence: ImportantCivilDay?, commit: @escaping () throws -> Void) {
        self.context = context; self.dayID = dayID; self.occurrence = occurrence; self.commit = commit
    }
    func insert(_ entry: Entry) {
        context.insert(entry)
        context.insert(ImportantDayEntryLink(dayID: dayID, entryID: entry.id, occurrence: occurrence))
    }
    func save() throws { try commit() }
    func rollback() { context.rollback() }
}
