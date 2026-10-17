import Foundation
import SwiftData
import XCTest
import UIKit
@testable import PersonalGrowthOS

@MainActor final class InvestmentPersistenceTests: XCTestCase {
    let zone = TimeZone(identifier:"Asia/Shanghai")!
    var clock = InvestmentClock(wall:Date(timeIntervalSince1970:1792113600),uptime:1000,processID:"synthetic-export-process")
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InvestmentTests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        // Retain synthetic disk stores until the test host exits; deleting them during
        // teardown can unlink SQLite/WAL/SHM while CoreData still holds open handles.
        return url
    }
    func transfer(_ c: ModelContainer,_ root: URL,checkpoint: ((ImportPublicationCheckpoint) throws -> Void)? = nil) -> ImportExportService {
        .init(context:c.mainContext,mediaStore:MediaStore(rootURL:root),availableCapacity:{.max},now:{self.clock.wall},
              publicationCheckpoint:checkpoint,investmentClock:{self.clock})
    }
    func testT12AllUnfinishedStatesExportRestoreReopenWithoutAdvancingOriginal() async throws {
        for desired in [InvestmentTimerState.running,.paused,.targetReached,.pendingSave] {
            let sourceRoot = try root(), source = try PersistenceContainerFactory.makeOnDisk(at:sourceRoot.appendingPathComponent("source.sqlite"))
            let s = InvestmentService(context:source.mainContext,clock:{self.clock}), a = try s.createActivity(name:"Synthetic export activity")
            let p = try XCTUnwrap(ModelContext(source).fetch(FetchDescriptor<InvestmentParticipant>()).first).id, id = UUID()
            try s.start(activityID:a,participantID:p,operationID:id,target:desired == .targetReached ? 720 : nil,zone:zone)
            clock.wall.addTimeInterval(720); clock.uptime += 720
            if desired != .running {
                let op = try XCTUnwrap(s.operations().first)
                try s.command(desired == .paused ? .pause : desired == .pendingSave ? .finish : .checkpoint,id:id,revision:op.revision)
            }
            let before = try TransferSnapshot.make(context:ModelContext(source))
            let receipt = CaptureImportReceipt(id:UUID(),importedAt:clock.wall); source.mainContext.insert(receipt); try source.mainContext.save()
            let baseline = try TransferSnapshot.make(context:ModelContext(source))
            let lease = try await transfer(source,sourceRoot).exportPackage(); defer { lease.cleanup() }
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(source)),baseline)
            let targetRoot = try root(), url = targetRoot.appendingPathComponent("target.sqlite")
            let target = try PersistenceContainerFactory.makeOnDisk(at:url)
            clock.wall.addTimeInterval(7*86400); clock.uptime += 7*86400
            _ = try await transfer(target,targetRoot).importPackage(from:lease.url)
            let reopened = try PersistenceContainerFactory.makeOnDisk(at:url), read = ModelContext(reopened)
            try InvestmentIntegrity.validate(context:read)
            XCTAssertEqual(try read.fetchCount(FetchDescriptor<InvestmentSession>()),0)
            XCTAssertEqual(try read.fetchCount(FetchDescriptor<CaptureImportReceipt>()),1)
            let recovered = try XCTUnwrap(InvestmentService(context:read).operations().first)
            XCTAssertEqual(recovered.timer.state,.recoveryRequired); XCTAssertNil(recovered.timer.anchor)
            XCTAssertEqual(recovered.timer.values.seconds,720,accuracy:0.001)
            XCTAssertEqual(recovered.timer.restoredState,desired)
            XCTAssertEqual(recovered.participantID,p); XCTAssertEqual(recovered.activityID,a)
            XCTAssertEqual(before.investmentSessions.count,0)
            let resumed = InvestmentService(context:read,clock:{self.clock})
            try resumed.command(.resume,id:id,revision:recovered.revision)
            clock.wall.addTimeInterval(60); clock.uptime += 60
            let active = try XCTUnwrap(resumed.operations().first)
            try resumed.command(.finish,id:id,revision:active.revision)
            let pending = try XCTUnwrap(resumed.operations().first)
            XCTAssertEqual(pending.timer.values.seconds,780,accuracy:0.001)
        }
    }
    func testT13PreviewThenTimerCreationAndRepeatImportRejectWithoutMutation() async throws {
        let sourceRoot = try root(), c = try PersistenceContainerFactory.makeOnDisk(at:sourceRoot.appendingPathComponent("source.sqlite"))
        let sourceService = InvestmentService(context:c.mainContext), a = try sourceService.createActivity(name:"Synthetic source")
        XCTAssertNotNil(a)
        let lease = try await transfer(c,sourceRoot).exportPackage(); defer {lease.cleanup()}
        let targetRoot = try root(), target = try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("target.sqlite"))
        let importing = transfer(target,targetRoot); _ = try await importing.previewPackage(from:lease.url)
        let s = InvestmentService(context:target.mainContext), b = try s.createActivity(name:"Synthetic intervening timer")
        let p = try XCTUnwrap(ModelContext(target).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        try s.start(activityID:b,participantID:p,operationID:UUID())
        let before = try TransferSnapshot.make(context:ModelContext(target))
        do { _ = try await importing.importPackage(from:lease.url); XCTFail("Nonempty target accepted") } catch { XCTAssertEqual(error as? TransferPackageError,.targetNotEmpty) }
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(target)),before)
        let emptyRoot = try root(), empty = try PersistenceContainerFactory.makeOnDisk(at:emptyRoot.appendingPathComponent("empty.sqlite"))
        let service = transfer(empty,emptyRoot); _ = try await service.importPackage(from:lease.url)
        let imported = try TransferSnapshot.make(context:ModelContext(empty))
        do { _ = try await service.importPackage(from:lease.url); XCTFail("Repeated import accepted") } catch { XCTAssertEqual(error as? TransferPackageError,.targetNotEmpty) }
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(empty)),imported)
    }
    func testT13PublicationFailureLeavesEmptyStoreAndRetryRestoresOneFact() async throws {
        let sourceRoot = try root(), source = try PersistenceContainerFactory.makeOnDisk(at:sourceRoot.appendingPathComponent("source.sqlite"))
        let s = InvestmentService(context:source.mainContext,clock:{self.clock}), a = try s.createActivity(name:"Synthetic fact")
        let p = try XCTUnwrap(ModelContext(source).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let values = InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:45,evidence:.dateDuration,source:.manual)
        try s.saveManual(id:UUID(),participantID:p,activityID:a,values:values)
        let lease = try await transfer(source,sourceRoot).exportPackage(); defer { lease.cleanup() }
        let targetRoot = try root(), targetURL = targetRoot.appendingPathComponent("target.sqlite"), target = try PersistenceContainerFactory.makeOnDisk(at:targetURL)
        let fail = transfer(target,targetRoot,checkpoint:{ if $0 == .beforeSave {throw CocoaError(.fileWriteOutOfSpace)} })
        do { _ = try await fail.importPackage(from:lease.url); XCTFail("Injected failure ignored") } catch { }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at:targetURL)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)).totalObjectCount,0)
        _ = try await transfer(reopened,targetRoot).importPackage(from:lease.url)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<InvestmentSession>()),1)
    }
    func testReviewerR4ZeroSecondPauseAcrossMidnightInitializesDayFromFirstActualSpan() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), s = InvestmentService(context:c.mainContext,clock:{self.clock})
        clock.wall = ImportantCivilDay(identifier:"2026-10-15")!.instant(minutes:1439,timeZone:zone)!
        let a = try s.createActivity(name:"Synthetic midnight")
        let p = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id,id = UUID()
        try s.start(activityID:a,participantID:p,operationID:id,zone:zone)
        var op = try XCTUnwrap(s.operations().first); try s.command(.pause,id:id,revision:op.revision)
        clock.wall.addTimeInterval(120); clock.uptime += 120
        op = try XCTUnwrap(s.operations().first); try s.command(.resume,id:id,revision:op.revision)
        clock.wall.addTimeInterval(60); clock.uptime += 60
        op = try XCTUnwrap(s.operations().first); try s.command(.finish,id:id,revision:op.revision)
        op = try XCTUnwrap(s.operations().first)
        XCTAssertEqual(op.timer.values.day,"2026-10-16"); try op.timer.values.validate(now:clock.wall)
    }
    func testT14V13DiskUpgradePreservesSleepEntryAndReceiptThenReopensV14() throws {
        let root = try root(), url = root.appendingPathComponent("legacy.sqlite"), id = UUID(), receiptID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema:PersonalGrowthSchemaV13.self)
            let old = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
            old.mainContext.insert(Entry(id:id,body:"Synthetic V13 fact",createdAt:clock.wall))
            old.mainContext.insert(CaptureImportReceipt(id:receiptID,importedAt:clock.wall))
            let sleep = try SleepRecord(wakeDay:"2026-10-15",timeZoneID:zone.identifier,values:SleepValues(feeling:4),createdAt:clock.wall)
            old.mainContext.insert(sleep); try old.mainContext.save()
        }
        let upgraded = try PersistenceContainerFactory.makeOnDisk(at:url), read = ModelContext(upgraded)
        XCTAssertEqual(try read.fetch(FetchDescriptor<Entry>()).first?.id,id)
        XCTAssertEqual(try read.fetch(FetchDescriptor<CaptureImportReceipt>()).first?.id,receiptID)
        XCTAssertEqual(try read.fetch(FetchDescriptor<SleepRecord>()).first?.values().feeling,4)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<InvestmentParticipant>()),0)
        let s = InvestmentService(context:read,clock:{self.clock}), a = try s.createActivity(name:"Synthetic upgraded activity")
        let p = try XCTUnwrap(ModelContext(upgraded).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        try s.saveManual(id:UUID(),participantID:p,activityID:a,values:.init(day:"2026-10-15",timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual))
        let expected = try TransferSnapshot.make(context:ModelContext(upgraded)), reopened = try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
    }
    func testT14FiveHistoricalDiskSchemasDirectStartupUpgradeKeepsOriginalFactsAndMedia() throws {
        let versions: [any VersionedSchema.Type] = [PersonalGrowthSchemaV10.self,PersonalGrowthSchemaV11Original.self,PersonalGrowthSchemaV11.self,PersonalGrowthSchemaV12.self,PersonalGrowthSchemaV13.self]
        for version in versions {
            let root = try root(), store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"), media = MediaStore(rootURL:root)
            try FileManager.default.createDirectory(at:store.deletingLastPathComponent(),withIntermediateDirectories:true)
            let imageURL = root.appendingPathComponent("synthetic.png")
            let bytes = UIGraphicsImageRenderer(size:.init(width:4,height:4)).pngData { c in UIColor.blue.setFill();c.fill(.init(x:0,y:0,width:4,height:4)) }
            try bytes.write(to:imageURL)
            var entryID = UUID(), habitID = UUID(), goalID = UUID(), imagePath = "", sourceBytes = Data()
            let receiptID = UUID(), taskID = UUID(), dayID = UUID()
            let hasTodo = version.versionIdentifier != PersonalGrowthSchemaV10.versionIdentifier
            let hasDay = version.versionIdentifier == PersonalGrowthSchemaV12.versionIdentifier || version.versionIdentifier == PersonalGrowthSchemaV13.versionIdentifier
            let hasSleep = version.versionIdentifier == PersonalGrowthSchemaV13.versionIdentifier
            try autoreleasepool {
                let schema = Schema(versionedSchema:version)
                let old = try ModelContainer(for:schema,configurations:[ModelConfiguration("PersonalGrowthOSV1",schema:schema,url:store,cloudKitDatabase:.none)])
                old.mainContext.autosaveEnabled = false
                let entry = try EntryCreationService(persistence:ModelContextEntryPersistence(context:old.mainContext),mediaStore:media,now:{self.clock.wall})
                    .create(.init(body:"Synthetic historical fact",images:[MediaSource(url:imageURL,originalFilename:"synthetic.png",contentType:"image/png")]))
                entryID = entry.id; imagePath = try XCTUnwrap(entry.images.first).relativePath
                habitID = try HabitService(context:old.mainContext,now:{self.clock.wall}).create(name:"Synthetic historical habit").id
                goalID = try GoalService(context:old.mainContext,now:{self.clock.wall}).create(title:"Synthetic historical goal",kind:.standard).id
                _ = try WeightRecordService(context:old.mainContext,now:{self.clock.wall}).create(weightKilograms:70,recordedAt:clock.wall)
                let source = try EntryExternalSource(entryID:entry.id,source:CaptureSource(url:"https://example.invalid/synthetic",capturedAt:clock.wall,captureMode:.selectedContent))
                sourceBytes = source.encodedSource;old.mainContext.insert(source)
                old.mainContext.insert(CaptureImportReceipt(id:receiptID,importedAt:clock.wall))
                if hasTodo {
                    let task=TodoTask(id:taskID,title:"Synthetic historical task",createdAt:clock.wall)
                    old.mainContext.insert(task)
                    old.mainContext.insert(TodoTaskEvent(taskID:taskID,sequence:0,kind:.created,occurredAt:clock.wall,createdAt:clock.wall,beforeValue:nil,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
                    old.mainContext.insert(TodoTaskSource(taskID:taskID,entryID:entry.id))
                }
                if hasDay {
                    old.mainContext.insert(try ImportantDay(id:dayID,title:"Synthetic historical day",rule:.init(preset:.anniversary,year:2020,month:10,day:15),createdAt:clock.wall))
                    old.mainContext.insert(ImportantDayEntryLink(dayID:dayID,entryID:entry.id,createdAt:clock.wall))
                }
                if hasSleep {old.mainContext.insert(try SleepRecord(wakeDay:"2026-10-15",timeZoneID:zone.identifier,values:SleepValues(feeling:4),createdAt:clock.wall))}
                try old.mainContext.save()
            }
            XCTAssertFalse(StartupStoreProtection.isCurrentStore(at:store))
            let app = try AppContainer.make(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),rootURLOverride:root)
            let read = ModelContext(app.modelContainer)
            XCTAssertEqual(try read.fetch(FetchDescriptor<Entry>()).map(\.id),[entryID])
            XCTAssertEqual(try read.fetch(FetchDescriptor<Habit>()).map(\.id),[habitID])
            XCTAssertEqual(try read.fetch(FetchDescriptor<Goal>()).map(\.id),[goalID])
            XCTAssertEqual(try read.fetch(FetchDescriptor<CaptureImportReceipt>()).map(\.id),[receiptID])
            XCTAssertEqual(try read.fetch(FetchDescriptor<EntryExternalSource>()).first?.encodedSource,sourceBytes)
            XCTAssertEqual(try read.fetchCount(FetchDescriptor<WeightRecord>()),1)
            if hasTodo {XCTAssertEqual(try read.fetch(FetchDescriptor<TodoTask>()).map(\.id),[taskID]);XCTAssertEqual(try read.fetchCount(FetchDescriptor<TodoTaskSource>()),1)}
            if hasDay {XCTAssertEqual(try read.fetch(FetchDescriptor<ImportantDay>()).map(\.id),[dayID]);XCTAssertEqual(try read.fetchCount(FetchDescriptor<ImportantDayEntryLink>()),1)}
            if hasSleep {XCTAssertEqual(try read.fetchCount(FetchDescriptor<SleepRecord>()),1)}
            XCTAssertEqual(try Data(contentsOf:media.fileURL(for:imagePath)),bytes)
            XCTAssertEqual(try read.fetchCount(FetchDescriptor<InvestmentParticipant>()),0)
            XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite").path))
            let expected = try TransferSnapshot.make(context:read), reopened = try PersistenceContainerFactory.makeOnDisk(at:store)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
        }
    }

    func testReviewerR5CloseConfirmationContinueFinishReopensFreshTimeAndRevision() throws {
        let c=try PersistenceContainerFactory.makeInMemory(),s=InvestmentService(context:c.mainContext,clock:{self.clock})
        let a=try s.createActivity(name:"Synthetic editor lifecycle"),p=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id,id=UUID()
        try s.start(activityID:a,participantID:p,operationID:id,zone:zone)
        clock.wall.addTimeInterval(1200);clock.uptime += 1200
        var op=try XCTUnwrap(s.operations().first);try s.command(.finish,id:id,revision:op.revision)
        let workspace=InvestmentWorkspace();workspace.refresh(c.mainContext)
        let oldEditor=workspace.editor(for:try XCTUnwrap(workspace.unfinished.first));oldEditor.values.note="Synthetic retained feedback";oldEditor.persist(c.mainContext)
        try workspace.resume(id:id,context:c.mainContext,clock:{self.clock})
        clock.wall.addTimeInterval(60);clock.uptime += 60
        op=try XCTUnwrap(s.operations().first);try s.command(.finish,id:id,revision:op.revision);workspace.refresh(c.mainContext)
        let fresh=workspace.editor(for:try XCTUnwrap(workspace.unfinished.first))
        XCTAssertFalse(oldEditor === fresh);XCTAssertTrue(oldEditor.finished)
        XCTAssertEqual(fresh.values.seconds,1260);XCTAssertEqual(fresh.values.note,"Synthetic retained feedback")
        XCTAssertEqual(Double(fresh.durationText),21)
        try s.saveTimer(id:id,revision:try XCTUnwrap(fresh.operationRevision),values:fresh.values)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<InvestmentSession>()),1)
    }

    func testReviewerR6DetailUsesOriginalZoneAfterDeviceZoneChanges() {
        let old=NSTimeZone.default;defer {NSTimeZone.default=old}
        let start=ImportantCivilDay(identifier:"2026-12-31")!.instant(minutes:1430,timeZone:zone)!
        let span=InvestmentSpan(start:start,end:start.addingTimeInterval(1800))
        NSTimeZone.default=zone
        let before=InvestmentFormatting.span(span,zoneID:zone.identifier,locale:Locale(identifier:"en_GB"))
        NSTimeZone.default=TimeZone(identifier:"America/New_York")!
        let after=InvestmentFormatting.span(span,zoneID:zone.identifier,locale:Locale(identifier:"en_GB"))
        XCTAssertEqual(before,after);XCTAssertTrue(after.contains("23:50"),after);XCTAssertTrue(after.contains("0:20:00"),after)
    }

}
