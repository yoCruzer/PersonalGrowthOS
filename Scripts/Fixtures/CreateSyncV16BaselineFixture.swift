import CryptoKit
// Append only to archived 96f72339a1a3082c43018e06d6115dd93df1df97 PersistenceMediaFoundationTests.swift.
// Synthetic V16/v12 input fixture; never opens the daily application store.
@MainActor
final class SyncV16BaselineFixtureGenerationTests: XCTestCase {
    func testGenerateFixedV16Baseline() async throws {
        let output = URL(fileURLWithPath: "/tmp/pgos-sync-v16-fixture-20261107-r2", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        let root = output.appendingPathComponent("working")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        container.mainContext.autosaveEnabled = false
        XCTAssertTrue(StartupStoreProtection.isCurrentStore(at: storeURL))
        XCTAssertEqual(ExportManifest.currentPackageSchemaVersion, 12)
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_793_600_000)
        let entry = Entry(title: "合成 V11 来源", body: "原文 📌", createdAt: date)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let bytes = try XCTUnwrap(renderer.image { c in UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }.pngData())
        let media = MediaStore(rootURL: root)
        let source = root.appendingPathComponent("fixture.png")
        try bytes.write(to: source)
        let image = try media.storeOriginal(MediaSource(url: source, originalFilename: "fixture.png", contentType: "image/png"))
        entry.images = [ImageMetadata(id: image.id, relativePath: image.relativePath, originalFilename: "fixture.png",
            contentType: "image/png", byteCount: image.byteCount, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
            checksum: image.checksum, createdAt: date)]
        context.insert(entry)
        context.insert(EntryPin(entryID: entry.id, pinnedAt: date))
        context.insert(EntryFollowUp(entryID: entry.id, body: "后续补充", createdAt: date))
        context.insert(try EntryExternalSource(entryID: entry.id, source: CaptureSource(url: "https://example.com/v11", title: "原始分享", capturedAt: date, captureMode: .selectedContent)))
        context.insert(CaptureImportReceipt(id: entry.id, importedAt: date))
        let habit = Habit(name: "保持习惯", normalizedName: "保持习惯", createdAt: date)
        context.insert(habit)
        let log = HabitLog(habitID: habit.id, occurredAt: date, isCompleted: true, quantity: 3, unit: "次", linkedEntryID: entry.id, createdAt: date)
        context.insert(log)
        context.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: "2026-09-22", localTimeZoneIdentifier: "Asia/Shanghai", provenance: .capturedAtWrite))
        let goal = Goal(kind: .flag, title: "旧目标", normalizedTitle: "旧目标", createdAt: date)
        context.insert(goal)
        context.insert(GoalLifecycleEvent(goalID: goal.id, kind: .created, occurredAt: date, createdAt: date))
        let tag = Tag(displayName: "旧标签", normalizedName: "旧标签", createdAt: date)
        context.insert(tag)
        context.insert(ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .tag, targetID: tag.id, kind: .entryUsesTag, createdAt: date))
        context.insert(WeightRecord(weightKilograms: 65.5, recordedAt: date, createdAt: date))
        let week = try WeeklyReviewPeriod(containing: date)
        context.insert(WeeklyReview(weekIdentifier: week.identifier, periodStart: week.start, periodEnd: week.end, rememberedText: "保留回顾", focusText: "保留重点", createdAt: date))
        try context.save()
        _ = try HabitAnalyticsMigrationBootstrap.apply(context: context, now: date)
        let todos = TodoTaskService(context: context, now: { date })
        let task = try todos.create(TodoDraft(title: "合成月度待办", plannedDay: "2026-09-22", remindAt: date.addingTimeInterval(3600), frequency: .monthly), sourceEntryID: entry.id)
        try todos.transition(id: task.id, to: .completed)
        var dayDraft = ImportantDayDraft(); dayDraft.title = "合成纪念日"; dayDraft.rule = .init(preset: .anniversary, year: 2000, month: 2, day: 29, leapDayRule: .february28)
        _ = try ImportantDayService(context: context, mediaStore: media).save(dayDraft)
        context.insert(try SleepRecord(wakeDay: "2026-09-22", timeZoneID: "Asia/Shanghai", values: .init(note: "合成睡眠记录"), createdAt: date))
        try context.save()
        let investment = InvestmentService(context: context)
        let activity = try investment.createActivity(name: "合成阅读")
        let participant = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<InvestmentParticipant>()).first)
        _ = try investment.saveManual(id: UUID(), participantID: participant.id, activityID: activity, values: .init(day: "2026-09-22", timeZoneID: "Asia/Shanghai", seconds: 600, evidence: .dateDuration, source: .manual))
        let finances = NetWorthService(context: context, now: { date })
        _ = try finances.saveItem(.init(name: "Synthetic asset", side: .asset, category: .cash))
        _ = try finances.saveItem(.init(name: "Synthetic liability", side: .liability, category: .mortgage))
        var snapshot = try finances.begin(day: "2026-09-22")
        for i in snapshot.items.indices {
            try snapshot.items[i].enter(snapshot.items[i].side == .asset ? "12345.67" : "234.56", day: snapshot.day)
        }
        snapshot.assetsConfirmed = true; snapshot.liabilitiesConfirmed = true
        let confirmed = try finances.confirm(finances.saveDraft(snapshot))
        XCTAssertEqual(try confirmed.totals().net, 1211111)
        var draft = try finances.begin(day: "2026-09-23")
        draft.items[0].inputText = "unfinished..input"
        _ = try finances.saveDraft(draft)
        let expectedBeforeReceipts = try TransferSnapshot.make(context: ModelContext(container))
        XCTAssertEqual(expectedBeforeReceipts.netWorthItems.count, 2)
        XCTAssertEqual(expectedBeforeReceipts.netWorthSnapshots.count, 2)
        context.insert(CaptureImportReceipt(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, importedAt: date))
        try context.save()
        let receiptIDs = try context.fetch(FetchDescriptor<CaptureImportReceipt>()).map(\.id)
        XCTAssertEqual(Set(receiptIDs), [entry.id, UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!])
        let expected = try TransferSnapshot.make(context: ModelContext(container))
        let retained = try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration)
        let frozen = output.appendingPathComponent("frozen")
        try FileManager.default.createDirectory(at: frozen, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: retained.snapshotURL.appendingPathComponent("Store"), to: frozen.appendingPathComponent("Store"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("Media"), to: frozen.appendingPathComponent("Media"))
        let lease = try await ImportExportService(context: context, mediaStore: media).exportPackage()
        try FileManager.default.copyItem(at: lease.url, to: frozen.appendingPathComponent("expected-v12.zip"))
        // Verify an independent destination against every transferred field and original bytes.
        let restoredRoot = output.appendingPathComponent("restored")
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        let restored = try PersistenceContainerFactory.makeOnDisk(at: restoredRoot.appendingPathComponent("store.sqlite"))
        _ = try await ImportExportService(context: restored.mainContext, mediaStore: MediaStore(rootURL: restoredRoot), availableCapacity: { .max }).importPackage(from: lease.url)
        XCTAssertEqual(try TransferSnapshot.make(context: ModelContext(restored)), expected)
        for metadata in expected.images {
            XCTAssertEqual(try Data(contentsOf: frozen.appendingPathComponent(metadata.relativePath)), try Data(contentsOf: restoredRoot.appendingPathComponent(metadata.relativePath)))
        }
        XCTAssertEqual(Set(try restored.mainContext.fetch(FetchDescriptor<CaptureImportReceipt>()).map(\.id)), Set(receiptIDs), "v12 must retain receipts, including a deleted source receipt, to prevent share replay")
        XCTAssertThrowsError(try NetWorthService(context: restored.mainContext).confirm(draft))
        func hashes(_ directory: URL) throws -> [String: String] {
            var result: [String: String] = [:]
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let file as URL in enumerator {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[String(file.path.dropFirst(directory.path.count))] = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
                }
            }
            return result
        }
        let frozenBefore = try hashes(frozen)
        let replayRoot = output.appendingPathComponent("reopened-copy")
        try FileManager.default.copyItem(at: frozen, to: replayRoot)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: replayRoot.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        XCTAssertEqual(try TransferSnapshot.make(context: ModelContext(reopened)), expected)
        XCTAssertEqual(Set(try reopened.mainContext.fetch(FetchDescriptor<CaptureImportReceipt>()).map(\.id)), Set(receiptIDs))
        XCTAssertEqual(try hashes(frozen), frozenBefore, "Opening only a copy must preserve frozen inputs byte-for-byte")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(expected).write(to: frozen.appendingPathComponent("expected-transfer.json"))
        lease.cleanup()
        try Data("96f72339a1a3082c43018e06d6115dd93df1df97\nSchema V16 / backup v12, generated by exact archived baseline source\n".utf8).write(to: frozen.appendingPathComponent("SOURCE.txt"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
    }
}
