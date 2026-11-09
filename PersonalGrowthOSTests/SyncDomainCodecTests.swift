import XCTest
import SwiftData
@testable import PersonalGrowthOS

@MainActor enum SyncDomainTestFixture {
    static let now = Date(timeIntervalSinceReferenceDate: 815292800.125)
    static func store() throws -> ModelContainer {
        let container = try PersistenceContainerFactory.makeInMemory()
        container.mainContext.autosaveEnabled = false
        return container
    }
    // Entirely synthetic metadata. Original-file verification belongs to the media
    // transport, so this fixture never reads a user's media or application support.
    private static func media(_ id: UUID = UUID()) throws -> StoredMediaFile {
        .init(id: id, relativePath: try MediaStore(rootURL: URL(fileURLWithPath: "/")).originalRelativePath(id: id, contentType: "image/png"),
              byteCount: 23, checksum: String(repeating: "a", count: 64), pixelWidth: 4, pixelHeight: 4)
    }
    static func make() throws -> ModelContainer {
        let container = try store(), c = container.mainContext
        let entry = Entry(title: "Synthetic original", body: "retained 📌", createdAt: now)
        let original = try media()
        entry.images = [ImageMetadata(id: original.id, relativePath: original.relativePath, originalFilename: "synthetic.png", contentType: "image/png",
            byteCount: original.byteCount, pixelWidth: 4, pixelHeight: 4, checksum: original.checksum, createdAt: now)]
        c.insert(entry)
        c.insert(EntryPin(entryID: entry.id, pinnedAt: now))
        c.insert(EntryFollowUp(entryID: entry.id, body: "retained follow-up", createdAt: now))
        c.insert(try EntryExternalSource(entryID: entry.id, source: CaptureSource(url: "https://example.com/synthetic", title: "source", capturedAt: now, captureMode: .selectedContent)))
        c.insert(CaptureImportReceipt(id: UUID(), importedAt: now)) // Deleted source receipt remains independent.
        let habit = Habit(name: "Synthetic habit", normalizedName: "synthetic habit", createdAt: now)
        c.insert(habit)
        c.insert(HabitConfiguration(habitID: habit.id, recordingMode: .multiplePerDay, dailyTargetCount: 3, updatedAt: now))
        let log = HabitLog(habitID: habit.id, occurredAt: now, isCompleted: true, quantity: 3, unit: "times", linkedEntryID: entry.id, createdAt: now)
        c.insert(log)
        c.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: "2026-09-22", localTimeZoneIdentifier: "Asia/Shanghai", provenance: .capturedAtWrite))
        let goal = Goal(kind: .flag, title: "Synthetic goal", normalizedTitle: "synthetic goal", createdAt: now)
        c.insert(goal); c.insert(GoalLifecycleEvent(goalID: goal.id, kind: .created, occurredAt: now, createdAt: now))
        let tag = Tag(displayName: "Synthetic tag", normalizedName: "synthetic tag", createdAt: now)
        c.insert(tag); c.insert(ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .tag, targetID: tag.id, kind: .entryUsesTag, createdAt: now))
        c.insert(WeightRecord(weightKilograms: 65.5, recordedAt: now, createdAt: now))
        c.insert(BodyReferenceSettings(heightCentimeters: 172.5, reference: .who))
        let week = try WeeklyReviewPeriod(containing: now)
        c.insert(WeeklyReview(weekIdentifier: week.identifier, periodStart: week.start, periodEnd: week.end, rememberedText: "remembered", focusText: "focus", createdAt: now))
        c.insert(try SleepRecord(wakeDay: "2026-09-22", timeZoneID: "Asia/Shanghai", values: .init(note: "synthetic sleep"), createdAt: now))
        c.insert(SleepGoalRule(effectiveDay: "2026-09-22", cutoffMinute: 1380, createdAt: now, observationTimeZoneID: "Asia/Shanghai"))
        let list = TodoList(name: "Synthetic list", createdAt: now); c.insert(list)
        try c.save()
        _ = try HabitAnalyticsMigrationBootstrap.apply(context: c, now: now)
        let todos = TodoTaskService(context: c, now: { now })
        let task = try todos.create(TodoDraft(title: "Synthetic repeated task", plannedDay: "2026-09-22", listID: list.id, frequency: .monthly), sourceEntryID: entry.id)
        try todos.transition(id: task.id, to: .completed)
        _ = try todos.create(TodoDraft(title: "Independent task"))
        let read = ModelContext(container); read.autosaveEnabled = false
        let seriesID = try XCTUnwrap(read.fetch(FetchDescriptor<TodoSeries>()).first?.id)
        if try read.fetch(FetchDescriptor<TodoSeriesPreferences>()).isEmpty {read.insert(TodoSeriesPreferences(seriesID: seriesID))}
        if try read.fetch(FetchDescriptor<TodoReminderIntent>()).isEmpty {read.insert(TodoReminderIntent(taskID: task.id, channel: .notification))}
        let day = try ImportantDay(title: "Synthetic day", notes: "retained notes", rule: .init(preset: .anniversary, year: 2000, month: 2, day: 29, leapDayRule: .february28), createdAt: now)
        read.insert(day)
        read.insert(ImportantDayEntryLink(dayID: day.id, entryID: entry.id, createdAt: now))
        read.insert(ImportantDayTodoLink(dayID: day.id, taskID: task.id, dayRevisionAtLink: 0, createdAt: now))
        read.insert(ImportantDayCover(dayID: day.id, stored: try media(), source: MediaSource(url: URL(fileURLWithPath: "/unused-synthetic"), originalFilename: "cover.png", contentType: "image/png"), createdAt: now))
        try read.save()
        let investment = InvestmentService(context: c, clock: { .init(wall: now, uptime: 100, processID: "synthetic") })
        let activity = try investment.createActivity(name: "Synthetic reading")
        let participant = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<InvestmentParticipant>()).first)
        _ = try investment.saveManual(id: UUID(), participantID: participant.id, activityID: activity, values: .init(day: "2026-09-22", timeZoneID: "Asia/Shanghai", seconds: 600, evidence: .dateDuration, source: .manual))
        let finances = NetWorthService(context: c, now: { now })
        _ = try finances.saveItem(.init(name: "Synthetic asset", side: .asset, category: .cash))
        var snapshot = try finances.begin(day: "2026-09-22")
        try snapshot.items[0].enter("12345.67", day: snapshot.day)
        snapshot.assetsConfirmed = true; snapshot.liabilitiesConfirmed = true
        _ = try finances.confirm(finances.saveDraft(snapshot))
        var draft = try finances.begin(day: "2026-09-23"); draft.items[0].inputText = "unfinished..input"
        _ = try finances.saveDraft(draft)
        return container
    }
}

@MainActor final class SyncDomainCodecTests: XCTestCase {
    private let now = SyncDomainTestFixture.now
    private let emptySupplement = SyncDomainSupplement(habitConfigurations: [], habitLogMetadata: [])
    private func store() throws -> ModelContainer { try SyncDomainTestFixture.store() }
    private func fixture() throws -> ModelContainer { try SyncDomainTestFixture.make() }
    func testAllBusinessAggregatesPreserveEveryTransferFieldAndSupplementIdentity() throws {
        let container = try fixture(), c = ModelContext(container)
        let truth = try TransferSnapshot.make(context: c), supplement = try SyncDomainSupplement.capture(context: c)
        XCTAssertTrue(truth.objectCounts.values.allSatisfy { $0 > 0 }, "Fixture covers every published transfer entity")
        let docs = try SyncDomainCodec.capture(context: c)
        XCTAssertEqual(Set(docs.map(\.key.kind)), Set(SyncDomainKind.allCases))
        for doc in docs { XCTAssertEqual(try SyncDomainCodec.decode(SyncDomainCodec.encode(doc)), doc) }
        let restored = try SyncDomainCodec.reconstruct(completeDocuments: docs.reversed())
        XCTAssertEqual(restored.transfer, truth)
        XCTAssertEqual(restored.supplement.habitConfigurations, supplement.habitConfigurations)
        XCTAssertEqual(restored.supplement.habitLogMetadata, supplement.habitLogMetadata)
        XCTAssertEqual(try truth.netWorthSnapshots.first { $0.confirmed }?.totals().net, 1234567)
        XCTAssertEqual(restored.transfer.netWorthSnapshots.first { !$0.confirmed }?.items[0].inputText, "unfinished..input")
        XCTAssertTrue(docs.first { $0.key.kind == .importantDayTodoLink }!.dependencies.contains { $0.kind == .todoSeries })
    }
    func testAggregateEditsLeaveOtherDocumentsByteIdentical() throws {
        let container = try fixture(), c = ModelContext(container)
        let before = try SyncDomainCodec.capture(context: c)
        let followUp = try XCTUnwrap(c.fetch(FetchDescriptor<EntryFollowUp>()).first)
        followUp.body = "changed follow-up"
        let after = try SyncDomainCodec.capture(context: c)
        XCTAssertEqual(zip(before, after).filter { $0 != $1 }.map { $0.0.key.kind }, [.entry])
        XCTAssertEqual(try SyncDomainCodec.capture(context: c, kinds: [.entry]), after.filter { $0.key.kind == .entry })
    }
    func testUnknownAndMissingFieldsVersionIdentityAndDependenciesAreRejected() throws {
        let container = try fixture(), docs = try SyncDomainCodec.capture(context: ModelContext(container))
        let doc = try XCTUnwrap(docs.first { $0.key.kind == .entry })
        func changed(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); edit(&object)
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        let wire = try SyncDomainCodec.encode(doc)
        XCTAssertThrowsError(try SyncDomainCodec.decode(changed(wire) { $0["futureField"] = 1 }))
        XCTAssertThrowsError(try SyncDomainCodec.decode(changed(wire) { $0.removeValue(forKey: "media") }))
        let missingChildList = try changed(doc.payload) { object in
            var entry = object["entry"] as! [String: Any]
            var aggregate = entry["_0"] as! [String: Any]
            aggregate.removeValue(forKey: "pins"); entry["_0"] = aggregate; object["entry"] = entry
        }
        XCTAssertThrowsError(try SyncDomainCodec.encode(.init(version: 1, key: doc.key, payload: missingChildList, dependencies: doc.dependencies, media: doc.media)))
        let unknownPayload = try changed(doc.payload) { $0["futureAggregate"] = [:] }
        XCTAssertThrowsError(try SyncDomainCodec.encode(.init(version: 1, key: doc.key, payload: unknownPayload, dependencies: doc.dependencies, media: doc.media)))
        XCTAssertThrowsError(try SyncDomainCodec.encode(.init(version: 2, key: doc.key, payload: doc.payload, dependencies: doc.dependencies, media: doc.media)))
        XCTAssertThrowsError(try SyncDomainCodec.encode(.init(version: 1, key: .init(kind: .entry, id: UUID()), payload: doc.payload, dependencies: doc.dependencies, media: doc.media)))
        XCTAssertThrowsError(try SyncDomainCodec.reconstruct(completeDocuments: docs + [doc]))
        XCTAssertThrowsError(try SyncDomainCodec.reconstruct(completeDocuments: docs.filter { $0.key.kind != .tag }))
        let link = try XCTUnwrap(docs.first { $0.key.kind == .objectLink })
        let forged = SyncDomainDocument(version: 1, key: link.key, payload: link.payload, dependencies: [], media: [])
        XCTAssertThrowsError(try SyncDomainCodec.reconstruct(completeDocuments: docs.filter { $0.key != link.key } + [forged]))
    }
    func testTypedIdentityAllowsSameUUIDAcrossDifferentEntityKinds() throws {
        let container = try store(), c = container.mainContext, id = UUID()
        let entry = Entry(id: id, title: "entry", body: "synthetic body", createdAt: now)
        c.insert(entry)
        c.insert(Tag(id: id, displayName: "tag", normalizedName: "tag", createdAt: now))
        let docs = try SyncDomainCodec.capture(context: c)
        XCTAssertEqual(docs.count, 2); XCTAssertEqual(Set(docs.map(\.key)).count, 2)
        let result = try SyncDomainCodec.reconstruct(completeDocuments: docs)
        XCTAssertEqual(result.transfer.entries[0].id, id); XCTAssertEqual(result.transfer.tags[0].id, id)
        entry.body = ""
        XCTAssertThrowsError(try SyncDomainCodec.capture(context: c)) { error in
            XCTAssertEqual(error as? EntryValidationError, .emptyContent)
        }
    }
    func testServiceCreatedOnceDailyHabitRetainsRawConfigurationThroughSync() throws {
        let source = try store(), target = try store(), c = source.mainContext
        let habit = try HabitService(context: c, now: { self.now }).create(
            name: "Once daily synthetic", plan: .legacy(mode: .oncePerDay, target: nil))
        let raw = try SyncDomainSupplement.capture(context: c)
        XCTAssertEqual(raw.habitConfigurations.first?.dailyTargetCount, 1)
        let truth = try TransferSnapshot.make(context: c)
        XCTAssertNil(truth.habits.first?.dailyTargetCount)
        let documents = try SyncDomainCodec.capture(context: c)
        let projection = try SyncDomainCodec.reconstruct(completeDocuments: documents)
        XCTAssertEqual(projection.transfer, truth)
        XCTAssertEqual(projection.supplement, raw)
        try SyncDomainInstaller.install(projection, affectedKeys: [.init(kind: .habit, id: habit.id)], in: target.mainContext)
        try target.mainContext.save()
        XCTAssertEqual(try SyncDomainSupplement.capture(context: target.mainContext), raw)
        XCTAssertEqual(try SyncDomainCodec.capture(context: target.mainContext), documents)
    }
    func testEffectiveSettingsComparisonStillRejectsActiveTargetAndModeMismatch() throws {
        let source = try store(), c = source.mainContext
        _ = try HabitService(context: c, now: { self.now }).create(
            name: "Multiple synthetic", plan: .legacy(mode: .multiplePerDay, target: 3))
        let data = try TransferSnapshot.make(context: c)
        let raw = try XCTUnwrap(SyncDomainSupplement.capture(context: c).habitConfigurations.first)
        for (mode, target) in [(HabitRecordingMode.multiplePerDay.rawValue, 4), (HabitRecordingMode.oncePerDay.rawValue, 3), ("unknown", 3)] {
            let supplement = SyncDomainSupplement(habitConfigurations: [.init(id: raw.id, habitID: raw.habitID,
                recordingModeRawValue: mode, dailyTargetCount: target, updatedAt: raw.updatedAt)], habitLogMetadata: [])
            XCTAssertThrowsError(try SyncDomainCodec.documents(from: data, supplement: supplement)) {
                XCTAssertEqual($0 as? SyncDomainCodecError, .missingSupplement)
            }
        }
    }
    func testSupplementLossAndOrphanChildrenFailClosed() throws {
        let container = try fixture(), c = ModelContext(container)
        let data = try TransferSnapshot.make(context: c)
        XCTAssertThrowsError(try SyncDomainCodec.documents(from: data, supplement: emptySupplement))
        c.insert(EntryFollowUp(entryID: UUID(), body: "orphan", createdAt: now))
        XCTAssertThrowsError(try SyncDomainCodec.capture(context: c, kinds: [.entry]))
    }
    func testSelectiveCaptureSkipsUnrelatedCorruptNetWorthPayloadAndDoesNotSave() throws {
        let container = try store(), c = container.mainContext
        let bad = try NetWorthSnapshot(.init(day: "2026-09-22")); bad.payload = Data("not JSON".utf8); c.insert(bad)
        c.insert(Entry(title: "unsaved synthetic", body: "synthetic body", createdAt: now))
        XCTAssertTrue(c.hasChanges)
        let docs = try SyncDomainCodec.capture(context: c, kinds: [.entry])
        XCTAssertEqual(docs.map(\.key.kind), [.entry]); XCTAssertTrue(c.hasChanges)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertThrowsError(try SyncDomainCodec.capture(context: c))
        XCTAssertTrue(try SyncDomainCodec.capture(context: c, kinds: []).isEmpty)
    }
    func testDevicePermissionTimerAndPathsNeverBecomeWireState() throws {
        let container = try fixture(), c = ModelContext(container)
        let day = try XCTUnwrap(c.fetch(FetchDescriptor<ImportantDay>()).first)
        var prefs = try day.preferences(); prefs.desktopVisible = true; day.preferencesData = try JSONEncoder().encode(prefs)
        let participant = try XCTUnwrap(c.fetch(FetchDescriptor<InvestmentParticipant>()).first)
        let activity = try XCTUnwrap(c.fetch(FetchDescriptor<InvestmentActivity>()).first)
        var timer = InvestmentTimer(state: .running, values: .init(day: "2026-09-22", timeZoneID: "Asia/Shanghai", seconds: 60, evidence: .dateDuration, source: .timer), target: 600, checkpointAt: now)
        timer.anchor = now; timer.anchorUptime = 20; timer.processID = "SECRET-DEVICE-PROCESS"
        c.insert(try InvestmentOperation(id: UUID(), participantID: participant.id, activityID: activity.id, timer: timer, now: now))
        let task = try XCTUnwrap(c.fetch(FetchDescriptor<TodoTask>()).first)
        let record = TodoReminderDeviceRecord(taskID: task.id, intentGeneration: UUID(), channel: .notification, fireAt: now, requestedTitle: "DEVICE-ONLY-SECRET")
        c.insert(record)
        let docs = try SyncDomainCodec.capture(context: c)
        let text = docs.map { String(decoding: $0.payload, as: UTF8.self) }.joined()
        for forbidden in ["desktopVisible", "anchorUptime", "processID", "SECRET-DEVICE", "DEVICE-ONLY-SECRET", "relativePath", "mediaPath", "Media/Originals"] { XCTAssertFalse(text.contains(forbidden), forbidden) }
        let restored = try SyncDomainCodec.reconstruct(completeDocuments: docs)
        XCTAssertFalse(try XCTUnwrap(restored.transfer.importantDays.first).preferences.desktopVisible)
        let restoredTimer = try XCTUnwrap(restored.transfer.investmentOperations.first { $0.timer.state == .recoveryRequired }).timer
        XCTAssertEqual(restoredTimer.restoredState, .running); XCTAssertNil(restoredTimer.anchor); XCTAssertNil(restoredTimer.processID)
        XCTAssertEqual(docs.flatMap(\.media).count, 2)
        XCTAssertEqual(Set(docs.flatMap(\.media).map(\.id)), Set(restored.transfer.mediaAssets.map(\.id)))
    }
    func testConflictPreviewShowsFullEntryDifferencesWithoutTransportMetadata() throws {
        let container = try fixture(), c = ModelContext(container)
        let entry = try XCTUnwrap(c.fetch(FetchDescriptor<Entry>()).first)
        entry.body = "First full paragraph.\nSecond paragraph with the decision: keep version A."
        let first = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key.kind == .entry })
        let immutablePayload = first.payload
        let firstPreview = try SyncDomainCodec.conflictPreview(first)
        XCTAssertTrue(firstPreview.contains(entry.body!))
        XCTAssertTrue(firstPreview.contains("retained follow-up")); XCTAssertTrue(firstPreview.contains("synthetic.png"))
        entry.body = "First full paragraph.\nSecond paragraph with the decision: keep version B."
        let second = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key.kind == .entry })
        let secondPreview = try SyncDomainCodec.conflictPreview(second)
        XCTAssertTrue(secondPreview.contains(entry.body!)); XCTAssertNotEqual(firstPreview, secondPreview)
        XCTAssertEqual(first.payload, immutablePayload)
        for doc in try SyncDomainCodec.capture(context: c) {
            let preview = try SyncDomainCodec.conflictPreview(doc)
            XCTAssertFalse(preview.isEmpty)
            XCTAssertFalse(preview.contains(doc.key.id.uuidString))
            XCTAssertFalse(preview.contains(doc.key.id.uuidString.lowercased()))
            for media in doc.media { XCTAssertFalse(preview.contains(media.sha256)) }
            XCTAssertFalse(preview.contains("anchorUptime")); XCTAssertFalse(preview.contains("\"_0\""))
        }
    }
    func testNetWorthConflictPreviewUsesFrozenNamesAmountsAndRetainedDraftText() throws {
        let container = try fixture(), c = ModelContext(container)
        let snapshot = try XCTUnwrap(c.fetch(FetchDescriptor<NetWorthSnapshot>()).first { try $0.value().confirmed })
        let first = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key.id == snapshot.id && $0.key.kind == .netWorthSnapshot })
        let preview = try SyncDomainCodec.conflictPreview(first)
        XCTAssertTrue(preview.contains("Synthetic asset")); XCTAssertTrue(preview.contains("12345.67")); XCTAssertTrue(preview.contains("2026-09-22"))
        let current = try XCTUnwrap(c.fetch(FetchDescriptor<NetWorthItem>()).first)
        var currentValue = try current.value(); currentValue.name = "Renamed current account"; current.payload = try JSONEncoder().encode(currentValue)
        let afterRename = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key == first.key })
        XCTAssertEqual(try SyncDomainCodec.conflictPreview(afterRename), preview)
        XCTAssertFalse(preview.contains("Renamed current account"))
        var changed = try snapshot.value(); changed.items[0].cents = 2_000_000; snapshot.payload = try JSONEncoder().encode(changed)
        let afterAmount = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key == first.key })
        XCTAssertTrue(try SyncDomainCodec.conflictPreview(afterAmount).contains("20000.00"))
        XCTAssertNotEqual(try SyncDomainCodec.conflictPreview(afterAmount), preview)
        let draftID = try XCTUnwrap(c.fetch(FetchDescriptor<NetWorthSnapshot>()).first { try !$0.value().confirmed }).id
        let draft = try XCTUnwrap(SyncDomainCodec.capture(context: c).first { $0.key.kind == .netWorthSnapshot && $0.key.id == draftID })
        XCTAssertTrue(try SyncDomainCodec.conflictPreview(draft).contains("unfinished..input"))
    }

}
