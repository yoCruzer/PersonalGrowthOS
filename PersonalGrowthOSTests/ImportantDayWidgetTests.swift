import SwiftData
import XCTest
import SwiftUI
import UIKit
import ImageIO
@testable import PersonalGrowthOS

@MainActor
final class ImportantDayWidgetTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImportantWidget-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func make(_ context: ModelContext, title: String, authorized: Bool) throws -> ImportantDay {
        var p = ImportantDayPreferences(); p.desktopVisible = authorized
        let day = try ImportantDay(title: title, rule: .init(year: 2027, month: 1, day: 1), preferences: p)
        context.insert(day); try context.save(); return day
    }
    func testOnlyExplicitAuthorizedFactsAreProjectedAndNoEntryTextOrOriginalsLeak() throws {
        let root = try root(), container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        _ = try make(c, title: "Never publish this private day", authorized: false)
        let allowed = try make(c, title: "Chosen public title", authorized: true)
        c.insert(Entry(body: "PRIVATE-BODY-MUST-NOT-LEAK", createdAt: Date())); try c.save()
        let store = ImportantDayWidgetSnapshotStore(root: root.appendingPathComponent("Widget")), publisher = ImportantDayWidgetPublisher()
        publisher.rebuild(context: c, mediaStore: MediaStore(rootURL: root), store: store)
        XCTAssertFalse(publisher.lastError)
        let snapshot = try store.read()
        XCTAssertEqual(snapshot.records.map(\.id), [allowed.id])
        let text = String(decoding: try Data(contentsOf: store.manifest), as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE-BODY")); XCTAssertFalse(text.contains("Never publish"))
        XCTAssertNil(snapshot.records.first?.coverFilename)
    }
    func testRevocationArchiveDeletionAndCorruptFactsRemovePreviousReadableSnapshot() throws {
        let root = try root(), container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let day = try make(c, title: "Explicit", authorized: true)
        let store = ImportantDayWidgetSnapshotStore(root: root.appendingPathComponent("Widget")), publisher = ImportantDayWidgetPublisher()
        let media = MediaStore(rootURL: root)
        publisher.rebuild(context: c, mediaStore: media, store: store)
        let first = try store.read().generation
        var p = try day.preferences(); p.desktopVisible = false; day.preferencesData = try JSONEncoder().encode(p); try c.save()
        publisher.rebuild(context: c, mediaStore: media, store: store)
        XCTAssertTrue(try store.read().records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent(first.uuidString.lowercased()).path))
        p.desktopVisible = true; day.preferencesData = try JSONEncoder().encode(p); day.isArchived = true; try c.save()
        publisher.rebuild(context: c, mediaStore: media, store: store); XCTAssertTrue(try store.read().records.isEmpty)
        day.isArchived = false; try c.save(); publisher.rebuild(context: c, mediaStore: media, store: store)
        day.ruleData = Data("broken".utf8); try c.save()
        publisher.rebuild(context: c, mediaStore: media, store: store)
        XCTAssertTrue(publisher.lastError); XCTAssertFalse(FileManager.default.fileExists(atPath: store.manifest.path))
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<ImportantDay>()), 1)
        _ = try EntryCreationService(persistence: ModelContextEntryPersistence(context: c), mediaStore: media).create(.init(body: "Capture still works"))
        c.delete(day); try c.save(); publisher.rebuild(context: c, mediaStore: media, store: store)
        XCTAssertTrue(try store.read().records.isEmpty)
    }
    func testUnknownVersionCorruptOversizedAndMissingImageAreNeutralReadableFailures() throws {
        let root = try root(), store = ImportantDayWidgetSnapshotStore(root: root)
        let wrong = ImportantDayWidgetSnapshot(version: 99, generation: UUID(), generatedAt: Date(), records: [])
        try JSONEncoder().encode(wrong).write(to: store.manifest)
        XCTAssertThrowsError(try store.read())
        try Data("broken".utf8).write(to: store.manifest); XCTAssertThrowsError(try store.read())
        try Data(repeating: 0, count: 2_000_001).write(to: store.manifest); XCTAssertThrowsError(try store.read())
        try store.revoke()
        let id = UUID(), record = ImportantDayWidgetRecord(id: id, title: "Configured", rule: .init(year: 2027, month: 1, day: 1), photoStyle: true, cropX: 0.5, cropY: 0.5, coverFilename: id.uuidString.lowercased() + ".jpg")
        let snapshot = ImportantDayWidgetSnapshot(version: 1, generation: UUID(), generatedAt: Date(), records: [record])
        XCTAssertThrowsError(try store.publish(snapshot, covers: [:]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.manifest.path))
        XCTAssertNil(store.coverURL(record: .init(id: id, title: "Unsafe", rule: record.rule, photoStyle: true, cropX: 0.5, cropY: 0.5, coverFilename: "../private.jpg"), generation: snapshot.generation))
    }
    func testIndependentCoverIsDownsampledAndMissingOriginalDegradesWithoutOpeningAnotherDay() throws {
        let root = try root(), container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let source = root.appendingPathComponent("large.png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: format).pngData { renderer in
            UIColor.orange.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }; try bytes.write(to: source)
        let media = MediaStore(rootURL: root), service = ImportantDayService(context: c, mediaStore: media)
        var draft = ImportantDayDraft(); draft.title = "Photo"; draft.rule = .init(year: 2027, month: 1, day: 1)
        draft.preferences.desktopVisible = true; draft.preferences.photoStyle = true
        let day = try service.save(draft, coverSource: .init(url: source, originalFilename: "large.png", contentType: "image/png"))
        let store = ImportantDayWidgetSnapshotStore(root: root.appendingPathComponent("Widget")), publisher = ImportantDayWidgetPublisher()
        publisher.rebuild(context: c, mediaStore: media, store: store)
        let snapshot = try store.read(), record = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(record.id, day.id)
        let imageURL = try XCTUnwrap(store.coverURL(record: record, generation: snapshot.generation))
        let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 640)
        XCTAssertNotEqual(try Data(contentsOf: imageURL), bytes)
        let cover = try XCTUnwrap(c.fetch(FetchDescriptor<ImportantDayCover>()).first)
        try media.removeOriginal(at: cover.relativePath)
        publisher.rebuild(context: c, mediaStore: media, store: store)
        XCTAssertEqual(try store.read().records.first?.id, day.id); XCTAssertNil(try store.read().records.first?.coverFilename)
    }
    func testStableRouteRejectsMalformedOrUnrelatedURLAndQueueSurvivesReplacement() throws {
        let id = UUID(), url = ImportantDayRoute.url(id: id)
        XCTAssertEqual(ImportantDayRoute.parse(url), id)
        for text in ["suixinlog://important-day/nope", "https://important-day/\(id)", "suixinlog://important-day/\(id)/extra", "suixinlog://important-day/\(id)?other=1"] {
            XCTAssertNil(ImportantDayRoute.parse(try XCTUnwrap(URL(string: text))))
        }
        let router = ImportantDayExternalRouter(); router.receive(id: id, source: .notification)
        XCTAssertEqual(router.pending?.id, id); XCTAssertEqual(router.pending?.source, .notification)
        router.receive(id: id, source: .widget); XCTAssertEqual(router.pending?.source, .widget)
    }
    func testActualProviderDateSequenceSchedulesThirtyFiveLocalMidnightsAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for start in [ImportantCivilDay(year: 2026, month: 3, day: 7), .init(year: 2026, month: 10, day: 31)] {
            let now = try XCTUnwrap(start.instant(minutes: 720, timeZone: calendar.timeZone))
            let dates = ImportantDayWidgetTimeline.dates(from: now, calendar: calendar)
            XCTAssertEqual(dates.count, 36); XCTAssertEqual(dates.first, now)
            for offset in 1...35 {
                XCTAssertEqual(ImportantCivilDay(dates[offset], timeZone: calendar.timeZone), start.adding(days: offset))
                XCTAssertEqual(calendar.component(.hour, from: dates[offset]), 0)
            }
            let midnightHours = dates[2].timeIntervalSince(dates[1]) / 3600
            XCTAssertEqual(midnightHours, start.month == 3 ? 23 : 25)
        }
    }
    func testFutureTimelineInputsRecomputeDaysWithoutRepublishing() throws {
        let rule = ImportantDayDateRule(year: 2027, month: 1, day: 1)
        let first = try ImportantDayDateEngine.evaluate(rule, today: .init(year: 2026, month: 12, day: 31))
        let second = try ImportantDayDateEngine.evaluate(rule, today: .init(year: 2027, month: 1, day: 1))
        let third = try ImportantDayDateEngine.evaluate(rule, today: .init(year: 2027, month: 1, day: 2))
        XCTAssertEqual([first.signedDays, second.signedDays, third.signedDays], [1, 0, -1])
    }
}

@MainActor
extension ImportantDayWidgetTests {
    func testPrivacyRedactionRemovesPhotoPixelsAndPrivateTextWithNormalPositiveControl() throws {
        let id = UUID(), date = ImportantCivilDay(year: 2026, month: 6, day: 20).date!
        func photo(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 340, height: 170)).image { c in
                color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 340, height: 170))
            }
        }
        func render(title: String, image: UIImage, privacy: Bool) throws -> Data {
            let record = ImportantDayWidgetRecord(id: id, title: title, rule: .init(year: 2027, month: 1, day: 1), photoStyle: true, cropX: 0.5, cropY: 0.5, coverFilename: nil)
            let entry = DayWidgetEntry(date: date, ids: [id], snapshot: .init(version: 1, generation: UUID(), generatedAt: date, records: [record]), sample: false)
            let renderer = ImageRenderer(content: SingleDayWidgetView(entry: entry, previewMode: true, previewImage: image)
                .frame(width: 340, height: 170).environment(\.colorScheme, .dark)
                .environment(\.redactionReasons, privacy ? .privacy : []))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        let orange = photo(.orange), teal = photo(.systemTeal)
        let normal = try render(title: "PRIVATE A", image: orange, privacy: false)
        let privateA = try render(title: "PRIVATE A", image: orange, privacy: true)
        let privateB = try render(title: "OTHER PRIVATE B", image: teal, privacy: true)
        XCTAssertNotEqual(normal, try render(title: "OTHER PRIVATE B", image: teal, privacy: false))
        XCTAssertNotEqual(normal, privateA)
        XCTAssertEqual(privateA, privateB, "Neither private text nor different cover pixels may survive privacy redaction")
        let directory = URL(fileURLWithPath: "/tmp/pgos-important-days-evidence/widget-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try normal.write(to: directory.appendingPathComponent("privacy-positive-normal.png"))
        try privateA.write(to: directory.appendingPathComponent("privacy-neutral.png"))
    }
    func testActualWidgetViewsRenderNumericPhotoListLongTitlesAndLargeCounts() throws {
        let directory = URL(fileURLWithPath: "/tmp/pgos-important-days-evidence/widget-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), other = UUID(), today = ImportantCivilDay(year: 2100, month: 1, day: 1)
        let record = ImportantDayWidgetRecord(id: id, title: "值得回看的人生起点 · A long meaningful beginning", rule: .init(preset: .beginning, year: 1901, month: 1, day: 1, perspective: .elapsed), photoStyle: false, cropX: 0.25, cropY: 0.5, coverFilename: nil)
        let second = ImportantDayWidgetRecord(id: other, title: "下一次周年 · Anniversary", rule: .init(preset: .anniversary, year: nil, month: 12, day: 31), photoStyle: false, cropX: 0.5, cropY: 0.5, coverFilename: nil)
        let date = try XCTUnwrap(today.date)
        let snapshot = ImportantDayWidgetSnapshot(version: 1, generation: UUID(), generatedAt: date, records: [record, second])
        let entry = DayWidgetEntry(date: date, ids: [id, other, nil], snapshot: snapshot, sample: false)
        func save<V: View>(_ view: V, name: String) throws {
            let renderer = ImageRenderer(content: view); renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage), data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 1000)
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        try save(SingleDayWidgetView(entry: entry, previewMode: true).frame(width: 170, height: 170).environment(\.locale, Locale(identifier: "zh-Hans")).environment(\.colorScheme, .light), name: "numeric-small-light")
        try save(SingleDayWidgetView(entry: entry, previewMode: true).frame(width: 170, height: 170).environment(\.locale, Locale(identifier: "zh-Hans")).environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .accessibility3), name: "numeric-small-dark-AX")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { c in
            UIColor.systemOrange.setFill(); c.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 320, y: 0, width: 320, height: 480))
        }
        let photoRecord = ImportantDayWidgetRecord(id: id, title: record.title, rule: record.rule, photoStyle: true, cropX: 0.8, cropY: 0.5, coverFilename: nil)
        let photoEntry = DayWidgetEntry(date: date, ids: [id], snapshot: .init(version: 1, generation: UUID(), generatedAt: date, records: [photoRecord]), sample: false)
        try save(SingleDayWidgetView(entry: photoEntry, previewMode: true, previewImage: image).frame(width: 340, height: 170).environment(\.colorScheme, .dark), name: "photo-medium-dark")
        try save(DayListWidgetView(entry: entry, previewMode: true).frame(width: 340, height: 170).environment(\.colorScheme, .light), name: "list-medium-light")
        try save(DayListWidgetView(entry: entry, previewMode: true).frame(width: 340, height: 170).environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .accessibility3), name: "list-medium-dark-AX")
    }
}
