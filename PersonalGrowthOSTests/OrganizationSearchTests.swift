import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class OrganizationSearchTests: XCTestCase {
    func testV1StoreMigratesToV2WithoutChangingEntryIdentity() throws {
        let fixture = try OrganizationFixture()
        defer { fixture.remove() }
        let entryID = UUID()
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV1.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.insert(Entry(
                id: entryID,
                body: "Before S5",
                createdAt: Date(timeIntervalSince1970: 1_000)
            ))
            try legacy.mainContext.save()
        }

        let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)

        XCTAssertEqual(try EntryRepository(context: migrated.mainContext).fetch(id: entryID)?.body, "Before S5")
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Tag>()).count, 0)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<ObjectLink>()).count, 0)
    }

    func testTagNormalizationPreventsWidthAndCaseDuplicates() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let service = TagLinkService(context: container.mainContext)
        let tag = try service.createTag(displayName: " Focus ")

        XCTAssertEqual(tag.displayName, "Focus")
        XCTAssertEqual(tag.normalizedName, "focus")
        XCTAssertThrowsError(try service.createTag(displayName: "ＦＯＣＵＳ")) {
            XCTAssertEqual($0 as? TagValidationError, .duplicateName)
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Tag>()).count, 1)
    }

    func testEntryTagLinkIsUniqueAndTagDeleteCleansLinksOnly() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Linked entry", createdAt: Date())
        context.insert(entry)
        try context.save()
        let service = TagLinkService(context: context)
        let tag = try service.createTag(displayName: "Learning")

        try service.attach(tag: tag, to: entry)
        try service.attach(tag: tag, to: entry)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)

        try service.deleteTag(tag)

        XCTAssertNotNil(try EntryRepository(context: context).fetch(id: entry.id))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tag>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
    }

    func testFailedTagDeleteRollsBackTagAndLink() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Linked entry", createdAt: Date())
        context.insert(entry)
        try context.save()
        let healthy = TagLinkService(context: context)
        let tag = try healthy.createTag(displayName: "Keep")
        try healthy.attach(tag: tag, to: entry)
        let failing = TagLinkService(context: context, save: { throw InjectedOrganizationFailure.save })

        XCTAssertThrowsError(try failing.deleteTag(tag))

        XCTAssertEqual(try context.fetch(FetchDescriptor<Tag>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testEntryPermanentDeleteCleansLinksAndPreservesTag() throws {
        let fixture = try OrganizationFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let persistence = ModelContextEntryPersistence(context: context)
        let entry = Entry(body: "Delete me", createdAt: Date())
        context.insert(entry)
        try context.save()
        let tagService = TagLinkService(context: context)
        let tag = try tagService.createTag(displayName: "Reference")
        try tagService.attach(tag: tag, to: entry)

        try EntryDeletionService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).permanentlyDelete(entry)

        XCTAssertNil(try EntryRepository(context: context).fetch(id: entry.id))
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Tag>()).first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testFailedEntryDeleteRollsBackEntryAndLink() throws {
        let fixture = try OrganizationFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Keep me", createdAt: Date())
        context.insert(entry)
        try context.save()
        let tagService = TagLinkService(context: context)
        let tag = try tagService.createTag(displayName: "Keep Link")
        try tagService.attach(tag: tag, to: entry)

        XCTAssertThrowsError(try EntryDeletionService(
            persistence: FailingLinkAwareDeletionPersistence(context: context),
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).permanentlyDelete(entry))

        XCTAssertNotNil(try EntryRepository(context: context).fetch(id: entry.id))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testIntegrityValidatorRejectsDanglingEntryTagLink() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let tag = Tag(
            displayName: "Dangling",
            normalizedName: "dangling",
            createdAt: Date()
        )
        context.insert(tag)
        context.insert(ObjectLink(
            sourceType: .entry,
            sourceID: UUID(),
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag,
            createdAt: Date()
        ))
        try context.save()

        XCTAssertThrowsError(try LinkIntegrityService.validate(context: context)) {
            guard case LinkIntegrityError.danglingLinks(let ids) = $0 else {
                return XCTFail("Expected dangling Link error, got \($0)")
            }
            XCTAssertEqual(ids.count, 1)
        }
    }

    func testOrganizeAndArchivePreserveOptionalTagLinks() throws {
        let fixture = try OrganizationFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let persistence = ModelContextEntryPersistence(context: context)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let entry = Entry(body: "No required tag", createdAt: Date())
        context.insert(entry)
        try context.save()
        let statusService = EntryDeletionService(persistence: persistence, mediaStore: mediaStore)

        try statusService.organize(entry)
        XCTAssertEqual(entry.status, .organized)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)

        let tagService = TagLinkService(context: context)
        let tag = try tagService.createTag(displayName: "Optional")
        try tagService.attach(tag: tag, to: entry)
        try statusService.archive(entry)

        XCTAssertEqual(entry.status, .archived)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)
    }

    func testSearchSupportsChineseLiteralLatinNormalizationReviewAndTag() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(Entry(body: "今天跑步后的感受", createdAt: Date(timeIntervalSince1970: 1_000)))
        context.insert(Entry(title: "Ｆｏｃｕｓ Plan", body: "Deep work", createdAt: Date(timeIntervalSince1970: 2_000)))
        context.insert(Entry(
            kind: .review,
            body: "Weekly reflection needle",
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        try context.save()
        _ = try TagLinkService(context: context).createTag(displayName: "健康")
        let search = LocalSearchService(context: context)

        XCTAssertEqual(try search.search("跑步").entries.map(\.body), ["今天跑步后的感受"])
        XCTAssertEqual(try search.search("focus").entries.map(\.title), ["Ｆｏｃｕｓ Plan"])
        XCTAssertEqual(try search.search("NEEDLE").entries.first?.kind, .review)
        XCTAssertEqual(try search.search("健康").tags.map(\.displayName), ["健康"])
    }

    func testRepresentativeSearchFixtureMeetsSimulatorThreshold() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let baseDate = Date(timeIntervalSince1970: 1_000)
        for index in 0..<5_000 {
            context.insert(Entry(
                title: "Memory \(index)",
                body: index == 4_999 ? "唯一 needle 结果" : "ordinary personal note \(index)",
                createdAt: baseDate.addingTimeInterval(Double(index))
            ))
        }
        for index in 0..<250 {
            context.insert(Tag(
                displayName: "Tag \(index)",
                normalizedName: "tag \(index)",
                createdAt: baseDate
            ))
        }
        try context.save()
        let search = LocalSearchService(context: context)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            do {
                let results = try search.search("needle")
                XCTAssertEqual(results.entries.count, 1)
            } catch {
                XCTFail("Search measurement failed: \(error)")
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        let results = try search.search("needle")
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(results.entries.count, 1)
        XCTAssertLessThan(elapsed, 1.0, "5,000 Entries and 250 Tags should search without visible blocking")
    }
}

private enum InjectedOrganizationFailure: Error {
    case save
}

@MainActor
private final class FailingLinkAwareDeletionPersistence: EntryDeletingPersistence {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func deleteLinks(involving objectID: UUID) throws {
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                $0.sourceID == objectID || $0.targetID == objectID
            }
        )
        try context.fetch(descriptor).forEach(context.delete)
    }

    func delete(_ entry: Entry) {
        context.delete(entry)
    }

    func save() throws {
        throw InjectedOrganizationFailure.save
    }

    func rollback() {
        context.rollback()
    }
}

private struct OrganizationFixture {
    let root: URL
    let storeURL: URL
    let mediaRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S5-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        mediaRoot = root.appendingPathComponent("MediaRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
