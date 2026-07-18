import Foundation
import SwiftData

enum TextSearchNormalizer {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

enum TagValidationError: Error, Equatable {
    case emptyName
    case duplicateName
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var displayName: String
    @Attribute(.unique) var normalizedName: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        normalizedName: String,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum LinkObjectType: String, Codable, Sendable {
    case entry
    case tag
}

enum ObjectLinkKind: String, Codable, Sendable {
    case entryUsesTag
}

@Model
final class ObjectLink {
    @Attribute(.unique) var id: UUID
    var sourceTypeRawValue: String
    var sourceID: UUID
    var targetTypeRawValue: String
    var targetID: UUID
    var kindRawValue: String
    @Attribute(.unique) var deduplicationKey: String
    var createdAt: Date

    var sourceType: LinkObjectType {
        LinkObjectType(rawValue: sourceTypeRawValue) ?? .entry
    }

    var targetType: LinkObjectType {
        LinkObjectType(rawValue: targetTypeRawValue) ?? .tag
    }

    var kind: ObjectLinkKind {
        ObjectLinkKind(rawValue: kindRawValue) ?? .entryUsesTag
    }

    init(
        id: UUID = UUID(),
        sourceType: LinkObjectType,
        sourceID: UUID,
        targetType: LinkObjectType,
        targetID: UUID,
        kind: ObjectLinkKind,
        createdAt: Date
    ) {
        self.id = id
        sourceTypeRawValue = sourceType.rawValue
        self.sourceID = sourceID
        targetTypeRawValue = targetType.rawValue
        self.targetID = targetID
        kindRawValue = kind.rawValue
        deduplicationKey = Self.makeDeduplicationKey(
            sourceType: sourceType,
            sourceID: sourceID,
            targetType: targetType,
            targetID: targetID,
            kind: kind
        )
        self.createdAt = createdAt
    }

    static func makeDeduplicationKey(
        sourceType: LinkObjectType,
        sourceID: UUID,
        targetType: LinkObjectType,
        targetID: UUID,
        kind: ObjectLinkKind
    ) -> String {
        [
            kind.rawValue,
            sourceType.rawValue,
            sourceID.uuidString.lowercased(),
            targetType.rawValue,
            targetID.uuidString.lowercased()
        ].joined(separator: "|")
    }
}

enum LinkIntegrityError: Error, Equatable {
    case danglingLinks([UUID])
}

@MainActor
enum LinkIntegrityService {
    static func validate(context: ModelContext) throws {
        let links = try context.fetch(FetchDescriptor<ObjectLink>())
        guard !links.isEmpty else { return }
        let entryIDs = Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id))
        let tagIDs = Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id))
        let danglingIDs = links.compactMap { link -> UUID? in
            guard link.kind == .entryUsesTag,
                  link.sourceType == .entry,
                  link.targetType == .tag,
                  entryIDs.contains(link.sourceID),
                  tagIDs.contains(link.targetID) else {
                return link.id
            }
            return nil
        }
        guard danglingIDs.isEmpty else {
            throw LinkIntegrityError.danglingLinks(danglingIDs.sorted { $0.uuidString < $1.uuidString })
        }
    }
}

@MainActor
final class TagLinkService {
    private let context: ModelContext
    private let now: () -> Date
    private let save: () throws -> Void

    init(
        context: ModelContext,
        now: @escaping () -> Date = Date.init,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.now = now
        self.save = save ?? { try context.save() }
    }

    func createTag(displayName: String) throws -> Tag {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TextSearchNormalizer.normalize(trimmed)
        guard !normalized.isEmpty else { throw TagValidationError.emptyName }
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else {
            throw TagValidationError.duplicateName
        }
        let timestamp = now()
        let tag = Tag(
            displayName: trimmed,
            normalizedName: normalized,
            createdAt: timestamp
        )
        context.insert(tag)
        do {
            try save()
            return tag
        } catch {
            context.rollback()
            throw error
        }
    }

    func attach(tag: Tag, to entry: Entry) throws {
        let key = ObjectLink.makeDeduplicationKey(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag
        )
        var descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.deduplicationKey == key }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(ObjectLink(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag,
            createdAt: now()
        ))
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func detach(tag: Tag, from entry: Entry) throws {
        let key = ObjectLink.makeDeduplicationKey(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag
        )
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.deduplicationKey == key }
        )
        try context.fetch(descriptor).forEach(context.delete)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteTag(_ tag: Tag) throws {
        let tagID = tag.id
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.targetID == tagID }
        )
        try context.fetch(descriptor).forEach(context.delete)
        context.delete(tag)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

struct LocalSearchResults {
    let entries: [Entry]
    let tags: [Tag]
}

@MainActor
final class LocalSearchService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func search(_ query: String) throws -> LocalSearchResults {
        let normalizedQuery = TextSearchNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return LocalSearchResults(entries: [], tags: [])
        }
        let entries = try context.fetch(FetchDescriptor<Entry>(sortBy: [
            SortDescriptor(\Entry.occurredAt, order: .reverse),
            SortDescriptor(\Entry.createdAt, order: .reverse),
            SortDescriptor(\Entry.id, order: .forward)
        ])).filter { entry in
            [entry.title, entry.body]
                .compactMap { $0 }
                .contains { TextSearchNormalizer.normalize($0).contains(normalizedQuery) }
        }
        let tags = try context.fetch(FetchDescriptor<Tag>(sortBy: [
            SortDescriptor(\Tag.normalizedName, order: .forward),
            SortDescriptor(\Tag.id, order: .forward)
        ])).filter { tag in
            tag.normalizedName.contains(normalizedQuery)
                || TextSearchNormalizer.normalize(tag.displayName).contains(normalizedQuery)
        }
        return LocalSearchResults(entries: entries, tags: tags)
    }
}

extension Tag: Identifiable {}
