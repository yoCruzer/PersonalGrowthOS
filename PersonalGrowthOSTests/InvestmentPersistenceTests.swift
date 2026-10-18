import Foundation
import SwiftData
import XCTest
import UIKit
import CryptoKit
import Combine
import Darwin
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
    func zipData(_ archive: URL) throws -> (TransferData,URL) {
        let extracted=try root();try ZIPArchiveReader(archiveURL:archive,availableCapacity:.max).extractAll(to:extracted)
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .secondsSince1970
        return (try decoder.decode(TransferData.self,from:Data(contentsOf:extracted.appendingPathComponent("data.json"))),extracted)
    }
    func f1DiskStart(_ container:ModelContainer,clock:@escaping () -> InvestmentClock,target:Double?=nil) throws -> (InvestmentService,UUID) {
        let service=InvestmentService(context:container.mainContext,clock:clock),activity=try service.createActivity(name:"Synthetic F1 disk timer")
        let participant=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<InvestmentParticipant>()).first).id,id=UUID()
        try service.start(activityID:activity,participantID:participant,operationID:id,target:target,zone:zone)
        return (service,id)
    }
    func f1Command(_ service:InvestmentService,_ id:UUID,_ action:InvestmentService.Command) throws {
        try service.command(action,id:id,revision:XCTUnwrap(service.operations().first {$0.id==id}).revision)
    }
    func testF1WorkspaceSleepCheckpointReopensAndSavesExactlyOneFactWithoutForeignDraft() throws {
        var readings=InvestmentClockTestReadings()
        let folder=try root(),url=folder.appendingPathComponent("f1-workspace.sqlite"),container=try PersistenceContainerFactory.makeOnDisk(at:url)
        let (service,id)=try f1DiskStart(container,clock:{readings.sample()})
        readings.advance(wall:120,continuous:120,awake:120);try f1Command(service,id,.checkpoint)
        container.mainContext.autosaveEnabled=false
        let foreign=Entry(body:"Synthetic F1 foreign unsaved",createdAt:readings.wall);container.mainContext.insert(foreign)
        readings.advance(wall:1800,continuous:1800,awake:30)
        let workspace=InvestmentWorkspace();workspace.checkpoint(container.mainContext,clock:{readings.sample()})
        XCTAssertNil(workspace.error);XCTAssertEqual(workspace.unfinished.first?.timer.state,.running)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url),read=ModelContext(reopened)
        let op=try XCTUnwrap(read.fetch(FetchDescriptor<InvestmentOperation>()).first),timer=try op.timer()
        XCTAssertEqual(timer.values.seconds,1920);XCTAssertEqual(timer.state,.running);XCTAssertEqual(timer.anchorUptime,readings.continuousElapsed)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<Entry>()),0);XCTAssertTrue(container.mainContext.hasChanges)
        XCTAssertEqual(foreign.body,"Synthetic F1 foreign unsaved")
        let durable=InvestmentService(context:read,clock:{readings.sample()});try f1Command(durable,id,.finish)
        let pending=try XCTUnwrap(durable.operations().first)
        try durable.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        try durable.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        let final=try PersistenceContainerFactory.makeOnDisk(at:url)
        let facts=try ModelContext(final).fetch(FetchDescriptor<InvestmentSession>())
        XCTAssertEqual(facts.count,1);XCTAssertEqual(facts.first?.id,id);XCTAssertEqual(try facts.first?.values().seconds,1920)
    }
    func testF1SleepCheckpointBeforeAndAfterCommitFailureReopensAndRetriesWithoutDoubleCredit() throws {
        for afterSave in [false,true] {
            var readings=InvestmentClockTestReadings()
            let folder=try root(),url=folder.appendingPathComponent("f1-fault.sqlite"),container=try PersistenceContainerFactory.makeOnDisk(at:url)
            let (service,id)=try f1DiskStart(container,clock:{readings.sample()})
            readings.advance(wall:120,continuous:120,awake:120);try f1Command(service,id,.checkpoint)
            let before=try TransferSnapshot.make(context:ModelContext(container))
            readings.advance(wall:1800,continuous:1800,awake:30)
            let failing=InvestmentService(context:container.mainContext,clock:{readings.sample()},commit:{context in if afterSave {try context.save()};throw CocoaError(.fileWriteOutOfSpace)})
            XCTAssertThrowsError(try f1Command(failing,id,.checkpoint))
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
            if !afterSave {XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),before)}
            else {
                let timer=try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<InvestmentOperation>()).first).timer()
                XCTAssertEqual(timer.state,.running);XCTAssertEqual(timer.values.seconds,1920)
            }
            let durable=InvestmentService(context:reopened.mainContext,clock:{readings.sample()});try f1Command(durable,id,.checkpoint)
            let again=try PersistenceContainerFactory.makeOnDisk(at:url)
            XCTAssertEqual(try InvestmentService(context:again.mainContext).operations().first?.timer.values.seconds,1920)
            readings.advance(wall:60,continuous:60,awake:1);try f1Command(durable,id,.checkpoint)
            let final=try PersistenceContainerFactory.makeOnDisk(at:url)
            XCTAssertEqual(try InvestmentService(context:final.mainContext).operations().first?.timer.values.seconds,1980)
            XCTAssertEqual(try ModelContext(final).fetchCount(FetchDescriptor<InvestmentSession>()),0)
        }
    }
    func testF1ActualZIPExportAfterSleepKeepsSourceAndRestoresOnlyContinuousCheckpoint() async throws {
        for target in [nil,Double(1500)] {
            var readings=InvestmentClockTestReadings()
            let folder=try root(),url=folder.appendingPathComponent("f1-export.sqlite"),container=try PersistenceContainerFactory.makeOnDisk(at:url)
            let (service,id)=try f1DiskStart(container,clock:{readings.sample()},target:target)
            readings.advance(wall:120,continuous:120,awake:120);try f1Command(service,id,.checkpoint)
            let sourceBefore=try TransferSnapshot.make(context:ModelContext(container))
            let duration=target==nil ? 1800.0:3000.0
            readings.advance(wall:duration,continuous:duration,awake:30)
            let exportClock=readings.sample(),expectedSeconds=target==nil ? 1920.0:1500.0
            let exporter=ImportExportService(context:container.mainContext,mediaStore:MediaStore(rootURL:folder),availableCapacity:{.max},now:{exportClock.wall},investmentClock:{exportClock})
            let lease=try await exporter.exportPackage();defer {lease.cleanup()}
            let (data,_)=try zipData(lease.url),exported=try XCTUnwrap(data.investmentOperations.first {$0.id==id})
            XCTAssertEqual(exported.timer.values.seconds,expectedSeconds)
            XCTAssertEqual(exported.timer.state,target==nil ? .running:.targetReached)
            XCTAssertEqual(exported.timer.checkpointAt,readings.wall)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(container)),sourceBefore,"Export must not checkpoint or consume the live source")
            var importedReadings=readings
            importedReadings.advance(wall:7*86400,continuous:7*86400,awake:600);importedReadings.processID="continuous-v1:restored-process"
            let targetRoot=try root(),targetURL=targetRoot.appendingPathComponent("f1-restored.sqlite"),restoring=try PersistenceContainerFactory.makeOnDisk(at:targetURL)
            let importClock=importedReadings.sample()
            let importer=ImportExportService(context:restoring.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max},now:{importClock.wall},investmentClock:{importClock})
            _ = try await importer.importPackage(from:lease.url)
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:targetURL),restored=InvestmentService(context:reopened.mainContext,clock:{importedReadings.sample()})
            let recovered=try XCTUnwrap(restored.operations().first)
            XCTAssertEqual(recovered.timer.state,.recoveryRequired);XCTAssertEqual(recovered.timer.values.seconds,expectedSeconds)
            XCTAssertEqual(recovered.timer.restoredState,target==nil ? .running:.targetReached)
            XCTAssertNil(recovered.timer.anchor);XCTAssertNil(recovered.timer.anchorUptime);XCTAssertNil(recovered.timer.processID)
            try f1Command(restored,id,.checkpoint);XCTAssertEqual(try restored.operations().first,recovered)
            XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<InvestmentSession>()),0)
            try f1Command(restored,id,.resume)
            importedReadings.advance(wall:60,continuous:60,awake:1);try f1Command(restored,id,.finish)
            let pending=try XCTUnwrap(restored.operations().first)
            XCTAssertEqual(pending.timer.values.seconds,expectedSeconds+60)
            try restored.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
            let final=try PersistenceContainerFactory.makeOnDisk(at:targetURL)
            let facts=try ModelContext(final).fetch(FetchDescriptor<InvestmentSession>())
            XCTAssertEqual(facts.count,1);XCTAssertEqual(try facts.first?.values().seconds,expectedSeconds+60)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(container)),sourceBefore)
        }
    }
    func testF1LegacyAwakeAnchorNeverMixesWithNewProcessAndResumeEstablishesContinuousAnchor() throws {
        var readings=InvestmentClockTestReadings()
        let oldProcess=UUID().uuidString
        func legacyReading() -> InvestmentClock {.init(wall:readings.wall,uptime:readings.awakeUptime,processID:oldProcess)}
        let folder=try root(),url=folder.appendingPathComponent("f1-legacy.sqlite"),container=try PersistenceContainerFactory.makeOnDisk(at:url)
        let (legacy,id)=try f1DiskStart(container,clock:legacyReading)
        readings.advance(wall:120,continuous:120,awake:120);try f1Command(legacy,id,.checkpoint)
        let known=try XCTUnwrap(legacy.operations().first).timer
        XCTAssertEqual(known.anchorUptime,320);XCTAssertEqual(known.values.seconds,120)
        readings.continuousElapsed=200000;readings.processID=InvestmentClock.current().processID
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url),current=InvestmentService(context:reopened.mainContext,clock:{readings.sample()})
        try f1Command(current,id,.checkpoint)
        let recovered=try XCTUnwrap(current.operations().first).timer
        XCTAssertEqual(recovered.state,.recoveryRequired);XCTAssertEqual(recovered.values,known.values)
        XCTAssertEqual(recovered.checkpointAt,known.checkpointAt);XCTAssertNil(recovered.anchorUptime);XCTAssertNil(recovered.processID)
        try f1Command(current,id,.resume)
        let resumed=try XCTUnwrap(current.operations().first).timer
        XCTAssertEqual(resumed.anchorUptime,200000);XCTAssertEqual(resumed.processID,readings.processID)
        readings.advance(wall:1800,continuous:1800,awake:30);try f1Command(current,id,.checkpoint)
        let final=try PersistenceContainerFactory.makeOnDisk(at:url)
        let result=try XCTUnwrap(InvestmentService(context:final.mainContext).operations().first).timer
        XCTAssertEqual(result.state,.running);XCTAssertEqual(result.values.seconds,1920)
    }
    func testExternalR1DeleteAndLinkedDraftFaultsReopenAtomicallyAndRejectNewStaleEditors() throws {
        for afterSave in [false,true] {
            let folder=try root(),url=folder.appendingPathComponent("delete-fault.sqlite"),c=try PersistenceContainerFactory.makeOnDisk(at:url)
            let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic atomic deletion")
            let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
            var values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:600,evidence:.dateDuration,source:.manual)
            values.note="Synthetic fact and linked draft secret";values.feeling=4
            let id=UUID(),linked=[UUID(),UUID()],healthy=UUID()
            try service.saveManual(id:id,participantID:participant,activityID:activity,values:values)
            var revisions=[UUID:Int]()
            for draft in linked {revisions[draft]=try service.storeDraft(id:draft,participantID:participant,activityID:activity,values:values,durationText:"Synthetic linked raw",editingSessionID:id,editingRevision:0)}
            try service.storeDraft(id:healthy,participantID:participant,activityID:activity,values:values,durationText:"10")
            let foreign=InvestmentParticipant(name:"Synthetic foreign editor");c.mainContext.insert(foreign);try c.mainContext.save()
            let foreignActivity=try service.createActivity(name:"Synthetic foreign activity",participantID:foreign.id)
            let before=try TransferSnapshot.make(context:ModelContext(c))
            XCTAssertThrowsError(try service.storeDraft(id:UUID(),participantID:foreign.id,activityID:foreignActivity,values:values,durationText:"10",editingSessionID:id,editingRevision:0))
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
            let failing=InvestmentService(context:c.mainContext,clock:{self.clock},commit:{context in if afterSave {try context.save()};throw CocoaError(.fileWriteOutOfSpace)})
            XCTAssertThrowsError(try failing.delete(id:id,revision:0))
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
            if !afterSave {
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),before,"Before-save failure must preserve fact and every draft/revision")
                try InvestmentService(context:reopened.mainContext,clock:{self.clock}).delete(id:id,revision:0)
            }
            let final=try PersistenceContainerFactory.makeOnDisk(at:url),read=ModelContext(final)
            XCTAssertEqual(try read.fetchCount(FetchDescriptor<InvestmentSession>()),0)
            let rows=try read.fetch(FetchDescriptor<InvestmentOperation>())
            XCTAssertEqual(rows.count,4)
            for row in rows {
                let timer=try row.timer()
                if row.id == healthy {XCTAssertEqual(timer.values,values);XCTAssertEqual(timer.state,.draft)}
                else {XCTAssertEqual(timer,timer.erasingConsumedContent());XCTAssertTrue(timer.erasesContent);XCTAssertEqual(timer.values.seconds,0);XCTAssertTrue(timer.values.note.isEmpty);XCTAssertNil(timer.durationText)}
            }
            let finalService=InvestmentService(context:final.mainContext,clock:{self.clock}),erased=try TransferSnapshot.make(context:read)
            XCTAssertThrowsError(try finalService.delete(id:id,revision:0))
            XCTAssertThrowsError(try finalService.saveManual(id:id,participantID:participant,activityID:activity,values:values))
            for draft in linked {XCTAssertThrowsError(try finalService.storeDraft(id:draft,participantID:participant,activityID:activity,values:values,durationText:"10",editingSessionID:id,editingRevision:0,expectedRevision:revisions[draft]))}
            XCTAssertThrowsError(try finalService.storeDraft(id:UUID(),participantID:participant,activityID:activity,values:values,durationText:"10",editingSessionID:id,editingRevision:0))
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(final)),erased,"No stale callback may recreate or alter erased content")
        }
    }
    func testExternalR1LegacyDiskStartupAndLegacyZIPRestoreEraseOnlyConsumedContent() async throws {
        let folder=try root(),store=folder.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at:store,withIntermediateDirectories:true)
        let url=store.appendingPathComponent("PersonalGrowthOS.sqlite"),c=try PersistenceContainerFactory.makeOnDisk(at:url)
        let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic legacy privacy")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        var values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:600,evidence:.dateDuration,source:.manual)
        values.note="Synthetic legacy deleted secret";values.feeling=5
        let deletedID=UUID(),linkedID=UUID(),healthyID=UUID()
        var terminal=InvestmentTimer(state:.deleted,values:values,target:1500,checkpointAt:clock.wall)
        terminal.durationText="Synthetic legacy raw text";terminal.editingSessionID=UUID();terminal.editingRevision=3;terminal.restoredState = .paused
        let deleted=try InvestmentOperation(id:deletedID,participantID:participant,activityID:activity,timer:terminal,now:clock.wall)
        deleted.revision=7
        var linkedTimer=InvestmentTimer(state:.draft,values:values,target:nil,checkpointAt:clock.wall)
        linkedTimer.editingSessionID=deletedID;linkedTimer.editingRevision=0;linkedTimer.durationText="Synthetic linked legacy raw"
        let linked=try InvestmentOperation(id:linkedID,participantID:participant,activityID:activity,timer:linkedTimer,now:clock.wall)
        var healthyValues=values;healthyValues.note="Synthetic healthy draft retained"
        let healthy=try InvestmentOperation(id:healthyID,participantID:participant,activityID:activity,timer:.init(state:.draft,values:healthyValues,target:nil,checkpointAt:clock.wall),now:clock.wall)
        for model in [deleted,linked,healthy] {c.mainContext.insert(model)}
        try c.mainContext.save()
        let originalPayload=deleted.payload,originalLinked=linked.payload
        let lease=try await transfer(c,folder).exportPackage();defer {lease.cleanup()}
        let (exported,extracted)=try zipData(lease.url)
        for op in exported.investmentOperations where op.id != healthyID {XCTAssertTrue(op.timer.erasesContent);XCTAssertEqual(op.timer.values.seconds,0);XCTAssertTrue(op.timer.values.note.isEmpty)}
        XCTAssertEqual(deleted.payload,originalPayload,"Export must not mutate the source")
        XCTAssertEqual(linked.payload,originalLinked)
        // Rebuild an actual pre-fix v10 ZIP with valid original legacy terminal payloads.
        var legacy=exported
        legacy.investmentOperations=try [deleted,linked,healthy].map {model in
            var op=try InvestmentOperationTransfer(model);op.timer=try model.timer();return op
        }.sorted {$0.id.uuidString < $1.id.uuidString}
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .secondsSince1970
        var payload=try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(legacy)) as? [String:Any])
        for key in ["todoSeriesPreferences","todoReminderIntents","bodyReferenceSettings"] {payload.removeValue(forKey:key)}
        let bytes=try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys);try bytes.write(to:extracted.appendingPathComponent("data.json"))
        let manifestURL=extracted.appendingPathComponent("manifest.json")
        var manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:manifestURL)) as? [String:Any])
        manifest["packageSchemaVersion"]=10;manifest["objectCounts"]=legacy.objectCounts(forPackageSchemaVersion:10)
        var dataFile=try XCTUnwrap(manifest["dataFile"] as? [String:Any]);dataFile["byteCount"]=bytes.count;dataFile["sha256"]=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined();manifest["dataFile"]=dataFile
        try JSONSerialization.data(withJSONObject:manifest,options:.sortedKeys).write(to:manifestURL)
        let archive=folder.appendingPathComponent("legacy-terminal.zip")
        try ZIPArchiveWriter.write(sources:[.init(path:"manifest.json",fileURL:manifestURL),.init(path:"data.json",fileURL:extracted.appendingPathComponent("data.json"))],to:archive)
        let targetRoot=try root(),targetURL=targetRoot.appendingPathComponent("target.sqlite"),target=try PersistenceContainerFactory.makeOnDisk(at:targetURL)
        _ = try await transfer(target,targetRoot).importPackage(from:archive)
        let restored=try PersistenceContainerFactory.makeOnDisk(at:targetURL)
        for model in try ModelContext(restored).fetch(FetchDescriptor<InvestmentOperation>()) {
            let timer=try model.timer()
            if model.id == healthyID {XCTAssertEqual(timer.values,healthyValues)}
            else {XCTAssertTrue(timer.erasesContent);XCTAssertEqual(timer.values.seconds,0);XCTAssertTrue(timer.values.note.isEmpty);XCTAssertNil(timer.durationText)}
        }
        let reexport=try await transfer(restored,targetRoot).exportPackage();defer {reexport.cleanup()}
        let (_,restoredExtracted)=try zipData(reexport.url)
        let restoredText=String(decoding:try Data(contentsOf:restoredExtracted.appendingPathComponent("data.json")),as:UTF8.self)
        XCTAssertFalse(restoredText.contains("Synthetic legacy deleted secret"));XCTAssertFalse(restoredText.contains("Synthetic linked legacy raw"));XCTAssertTrue(restoredText.contains("Synthetic healthy draft retained"))
        let app=try AppContainer.make(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),rootURLOverride:folder)
        let appRead=ModelContext(app.modelContainer)
        for model in try appRead.fetch(FetchDescriptor<InvestmentOperation>()) {
            let timer=try model.timer()
            if model.id == healthyID {XCTAssertEqual(timer.values,healthyValues)}
            else {XCTAssertTrue(timer.erasesContent);XCTAssertEqual(timer.values.seconds,0);XCTAssertTrue(timer.values.note.isEmpty);XCTAssertNil(timer.editingSessionID)}
            if model.id == deletedID {XCTAssertEqual(model.revision,7);XCTAssertEqual(model.createdAt,clock.wall)}
        }
    }
    func testExternalR1CleanupFaultsAreAtomicAndInvalidLegacyPayloadStillRejects() throws {
        for mode in ["before","after","invalid"] {
            let folder=try root(),store=folder.appendingPathComponent("Store");try FileManager.default.createDirectory(at:store,withIntermediateDirectories:true)
            let url=store.appendingPathComponent("PersonalGrowthOS.sqlite"),c=try PersistenceContainerFactory.makeOnDisk(at:url)
            let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic cleanup fault")
            let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
            var value=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:mode == "invalid" ? -1 : 600,evidence:.dateDuration,source:.manual);value.note="Synthetic old consumed content"
            let model=try InvestmentOperation(id:UUID(),participantID:participant,activityID:activity,timer:.init(state:.discarded,values:value,target:nil,checkpointAt:clock.wall),now:clock.wall)
            c.mainContext.insert(model);try c.mainContext.save();let before=model.payload
            let failing=InvestmentService(context:c.mainContext,commit:{context in if mode == "after" {try context.save()};throw CocoaError(.fileWriteOutOfSpace)})
            XCTAssertThrowsError(try failing.erasePreviouslyConsumedContent())
            let read=try PersistenceContainerFactory.makeOnDisk(at:url)
            let row=try XCTUnwrap(ModelContext(read).fetch(FetchDescriptor<InvestmentOperation>()).first)
            if mode == "after" {XCTAssertEqual(try row.timer().values.seconds,0);XCTAssertTrue(try row.timer().values.note.isEmpty)}
            else {XCTAssertEqual(row.payload,before)}
            if mode == "invalid" {
                XCTAssertThrowsError(try InvestmentIntegrity.validate(context:ModelContext(read)))
                XCTAssertThrowsError(try AppContainer.make(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),rootURLOverride:folder))
                XCTAssertEqual(try XCTUnwrap(ModelContext(read).fetch(FetchDescriptor<InvestmentOperation>()).first).payload,before)
            } else {
                try service.erasePreviouslyConsumedContent()
                var commits=0
                try InvestmentService(context:c.mainContext,commit:{_ in commits += 1}).erasePreviouslyConsumedContent()
                XCTAssertEqual(commits,0,"Already erased stores must not be saved again")
            }
        }
    }
    func testExternalR1ConsumedEditDraftIsErasedWhileSavedFactAndForeignParticipantRemain() throws {
        let folder=try root(),c=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("consume.sqlite"))
        let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic consumed editor")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        var values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:600,evidence:.dateDuration,source:.manual);values.note="Synthetic saved fact retained"
        let id=UUID();try service.saveManual(id:id,participantID:participant,activityID:activity,values:values)
        for changed in [false,true] {
            let draft=UUID(),session=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentSession>()).first)
            if changed {values.note="Synthetic changed fact retained"}
            try service.storeDraft(id:draft,participantID:participant,activityID:activity,values:values,durationText:"Synthetic consumed raw duration",editingSessionID:id,editingRevision:session.revision)
            try service.saveManual(id:id,participantID:participant,activityID:activity,values:values,expectedRevision:session.revision,draftID:draft)
            let row=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentOperation>()).first {$0.id == draft})
            XCTAssertEqual(try row.timer().state,.discarded);XCTAssertEqual(try row.timer().values.seconds,0);XCTAssertNil(try row.timer().durationText)
            XCTAssertEqual(try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentSession>()).first).values(),values)
        }
        let second=InvestmentParticipant(name:"Synthetic second");c.mainContext.insert(second);try c.mainContext.save()
        let secondActivity=try service.createActivity(name:"Synthetic foreign activity",participantID:second.id),foreignID=UUID()
        try service.storeDraft(id:foreignID,participantID:second.id,activityID:secondActivity,values:values,durationText:"10")
        let before=try TransferSnapshot.make(context:ModelContext(c))
        let record=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentSession>()).first)
        XCTAssertThrowsError(try service.saveManual(id:id,participantID:participant,activityID:activity,values:values,expectedRevision:record.revision,draftID:foreignID))
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
    }
    func testExternalR2FirstAmbiguousCommitReconcilesOnlyExactInput() throws {
        let folder=try root(),c=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("first-draft.sqlite"))
        let service=InvestmentService(context:c.mainContext),activity=try service.createActivity(name:"Synthetic first commit")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let editor=InvestmentEditorState(participantID:participant,activityID:activity,values:.init(day:"2026-10-15",timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual))
        XCTAssertFalse(editor.persist(c.mainContext,commit:{try $0.save();throw CocoaError(.fileWriteUnknown)}));XCTAssertNil(editor.operationRevision)
        let committed=try TransferSnapshot.make(context:ModelContext(c))
        editor.values.note="Synthetic changed after ambiguous commit"
        XCTAssertFalse(editor.persist(c.mainContext));XCTAssertEqual(editor.values.note,"Synthetic changed after ambiguous commit")
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),committed)
        editor.values.note=""
        XCTAssertTrue(editor.persist(c.mainContext));XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),committed)
    }
    func testExternalR1DeletedAndDiscardedContentIsAbsentFromDiskAndZIPAndCannotResurrect() async throws {
        let folder=try root(),url=folder.appendingPathComponent("privacy.sqlite")
        let c=try PersistenceContainerFactory.makeOnDisk(at:url)
        let service=InvestmentService(context:c.mainContext,clock:{self.clock})
        let activity=try service.createActivity(name:"Synthetic privacy activity")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let start=clock.wall.addingTimeInterval(-600)
        var values=InvestmentValues(day:ImportantCivilDay(start,timeZone:zone).identifier,timeZoneID:zone.identifier,seconds:600,evidence:.intervals,source:.manual,spans:[.init(start:start,end:clock.wall)])
        values.note="Synthetic deleted secret";values.feeling=4
        let record=UUID(),linked=UUID(),discarded=UUID()
        try service.saveManual(id:record,participantID:participant,activityID:activity,values:values)
        let linkedRevision=try service.storeDraft(id:linked,participantID:participant,activityID:activity,values:values,durationText:"Synthetic raw deleted duration",editingSessionID:record,editingRevision:0)
        values.note="Synthetic discarded secret"
        let discardRevision=try service.storeDraft(id:discarded,participantID:participant,activityID:activity,values:values,durationText:"Synthetic raw discarded duration")
        try service.command(.discard,id:discarded,revision:discardRevision)
        try service.delete(id:record,revision:0)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<InvestmentSession>()),0)
        for model in try ModelContext(reopened).fetch(FetchDescriptor<InvestmentOperation>()) {
            let timer=try model.timer()
            XCTAssertTrue([InvestmentTimerState.deleted,.discarded].contains(timer.state))
            XCTAssertEqual(timer.values.seconds,0);XCTAssertTrue(timer.values.spans.isEmpty)
            XCTAssertTrue(timer.values.note.isEmpty);XCTAssertNil(timer.values.feeling)
            XCTAssertNotEqual(timer.values.day,values.day);XCTAssertEqual(timer.values.timeZoneID,"UTC")
            XCTAssertNil(timer.durationText);XCTAssertNil(timer.editingSessionID);XCTAssertNil(timer.editingRevision)
            let raw=String(decoding:model.payload,as:UTF8.self)
            XCTAssertFalse(raw.contains("Synthetic deleted secret"));XCTAssertFalse(raw.contains("Synthetic discarded secret"))
        }
        let workspace=InvestmentWorkspace();workspace.refresh(reopened.mainContext)
        XCTAssertTrue(workspace.drafts.isEmpty);XCTAssertTrue(try workspace.contributions().isEmpty)
        let lease=try await transfer(reopened,folder).exportPackage();defer {lease.cleanup()}
        let extracted=try root();try ZIPArchiveReader(archiveURL:lease.url,availableCapacity:.max).extractAll(to:extracted)
        let raw=try Data(contentsOf:extracted.appendingPathComponent("data.json"))
        let text=String(decoding:raw,as:UTF8.self)
        for marker in ["Synthetic deleted secret","Synthetic discarded secret","Synthetic raw deleted duration","Synthetic raw discarded duration"] {XCTAssertFalse(text.contains(marker),marker)}
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .secondsSince1970
        let data=try decoder.decode(TransferData.self,from:raw)
        XCTAssertTrue(data.investmentSessions.isEmpty);XCTAssertEqual(data.investmentOperations.count,3)
        XCTAssertTrue(data.investmentOperations.allSatisfy {$0.timer.values.seconds == 0 && $0.timer.values.spans.isEmpty})
        let restoredRoot=try root(),restoredURL=restoredRoot.appendingPathComponent("restored.sqlite")
        let restored=try PersistenceContainerFactory.makeOnDisk(at:restoredURL)
        _ = try await transfer(restored,restoredRoot).importPackage(from:lease.url)
        let again=try PersistenceContainerFactory.makeOnDisk(at:restoredURL)
        let restoredService=InvestmentService(context:again.mainContext,clock:{self.clock})
        XCTAssertThrowsError(try restoredService.storeDraft(id:linked,participantID:participant,activityID:activity,values:values,durationText:"stale",expectedRevision:linkedRevision))
        XCTAssertThrowsError(try restoredService.saveManual(id:record,participantID:participant,activityID:activity,values:values))
        try restoredService.start(activityID:activity,participantID:participant,operationID:discarded,zone:zone)
        XCTAssertEqual(try ModelContext(again).fetchCount(FetchDescriptor<InvestmentSession>()),0)
        XCTAssertTrue(try restoredService.operations().allSatisfy {!$0.timer.state.unfinished && $0.timer.state != .draft})
    }
    func testExternalR2DraftFailuresRetainInputAndAmbiguousCommitCanRetry() throws {
        let folder=try root(),url=folder.appendingPathComponent("draft-failures.sqlite")
        let c=try PersistenceContainerFactory.makeOnDisk(at:url)
        let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic draft failure")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let editor=InvestmentEditorState(participantID:participant,activityID:activity,values:.init(day:"2026-10-15",timeZoneID:zone.identifier,seconds:2700,evidence:.dateDuration,source:.manual))
        editor.persist(c.mainContext);XCTAssertNil(editor.error)
        c.mainContext.autosaveEnabled=false;let foreign=Entry(body:"Synthetic foreign unsaved",createdAt:clock.wall);c.mainContext.insert(foreign)
        editor.values.note="Synthetic latest unsaved input";editor.durationText="invalid raw duration"
        editor.persist(c.mainContext,commit:{_ in throw CocoaError(.fileWriteOutOfSpace)})
        XCTAssertNotNil(editor.error);XCTAssertFalse(editor.finished)
        XCTAssertEqual(editor.values.note,"Synthetic latest unsaved input");XCTAssertEqual(editor.durationText,"invalid raw duration")
        let failed=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try InvestmentService(context:failed.mainContext).operations().first?.timer.values.note,"")
        editor.persist(c.mainContext);XCTAssertNil(editor.error)
        editor.values.note="Synthetic actually committed before error"
        editor.persist(c.mainContext,commit:{try $0.save();throw CocoaError(.fileWriteUnknown)})
        XCTAssertNotNil(editor.error)
        let ambiguous=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try InvestmentService(context:ambiguous.mainContext).operations().first?.timer.values.note,editor.values.note)
        editor.persist(c.mainContext)
        XCTAssertNil(editor.error,"Matching actual commit must remain retryable")
        XCTAssertTrue(c.mainContext.hasChanges);XCTAssertEqual(foreign.body,"Synthetic foreign unsaved")
        XCTAssertEqual(try ModelContext(ambiguous).fetchCount(FetchDescriptor<Entry>()),0)
    }
    func testExternalR3UnconfirmedContinuousEnvelopePreservesSegmentsAcrossSaveReopenAndZIP() async throws {
        let folder=try root(),url=folder.appendingPathComponent("segments.sqlite"),c=try PersistenceContainerFactory.makeOnDisk(at:url)
        let service=InvestmentService(context:c.mainContext,clock:{self.clock}),activity=try service.createActivity(name:"Synthetic segment evidence")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id,id=UUID()
        try service.start(activityID:activity,participantID:participant,operationID:id,zone:zone)
        func command(_ action: InvestmentService.Command) throws {try service.command(action,id:id,revision:XCTUnwrap(service.operations().first).revision)}
        clock.wall.addTimeInterval(600);clock.uptime += 600;try command(.pause)
        clock.wall.addTimeInterval(300);clock.uptime += 300;try command(.resume)
        clock.wall.addTimeInterval(600);clock.uptime += 600;try command(.finish)
        let pending=try XCTUnwrap(service.operations().first)
        try service.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        let fact=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentSession>()).first),original=try fact.values()
        XCTAssertEqual(original.seconds,1200);XCTAssertEqual(original.spans.count,2)
        let editor=InvestmentEditorState(participantID:participant,activityID:activity,values:original,editingSessionID:id,editingRevision:fact.revision)
        XCTAssertFalse(try editor.requestExactInterval(start:XCTUnwrap(original.spans.first).start,end:XCTUnwrap(original.spans.last).end,now:clock.wall))
        XCTAssertEqual(editor.values,original)
        editor.values.note="Synthetic note-only edit"
        try service.saveManual(id:id,participantID:participant,activityID:activity,values:editor.values,expectedRevision:fact.revision)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url),read=ModelContext(reopened)
        let value=try XCTUnwrap(read.fetch(FetchDescriptor<InvestmentSession>()).first).values()
        XCTAssertEqual(value.seconds,1200);XCTAssertEqual(value.spans,original.spans)
        let workspace=InvestmentWorkspace();workspace.refresh(read)
        XCTAssertEqual(try workspace.contributions().reduce(0) {$0+$1.seconds},1200)
        let lease=try await transfer(reopened,folder).exportPackage();defer {lease.cleanup()}
        let targetRoot=try root(),target=try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("target.sqlite"))
        _ = try await transfer(target,targetRoot).importPackage(from:lease.url)
        let restored=try XCTUnwrap(ModelContext(target).fetch(FetchDescriptor<InvestmentSession>()).first).values()
        XCTAssertEqual(restored.seconds,1200);XCTAssertEqual(restored.spans,original.spans)
        editor.cancelExactIntervalReplacement()
        XCTAssertFalse(try editor.requestExactInterval(start:XCTUnwrap(original.spans.first).start,end:XCTUnwrap(original.spans.last).end,now:clock.wall))
        editor.values.note="Synthetic changed while confirmation pending"
        XCTAssertThrowsError(try editor.confirmExactIntervalReplacement(now:clock.wall))
        XCTAssertEqual(editor.values.spans,original.spans)
        editor.cancelExactIntervalReplacement()
        XCTAssertFalse(try editor.requestExactInterval(start:XCTUnwrap(original.spans.first).start,end:XCTUnwrap(original.spans.last).end,now:clock.wall))
        try editor.confirmExactIntervalReplacement(now:clock.wall)
        XCTAssertEqual(editor.values.seconds,1500);XCTAssertEqual(editor.values.spans.count,1);XCTAssertTrue(editor.values.corrected)
        let current=try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<InvestmentSession>()).first)
        try InvestmentService(context:reopened.mainContext,clock:{self.clock}).saveManual(id:id,participantID:participant,activityID:activity,values:editor.values,expectedRevision:current.revision)
        let final=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try XCTUnwrap(ModelContext(final).fetch(FetchDescriptor<InvestmentSession>()).first).values(),editor.values)
        let finalLease=try await transfer(final,folder).exportPackage();defer {finalLease.cleanup()}
        let (finalData,_)=try zipData(finalLease.url)
        XCTAssertEqual(finalData.investmentSessions.first?.values.seconds,1500)
        XCTAssertEqual(finalData.investmentSessions.first?.values.spans.count,1)
    }
    func testT4DiskCommitFailuresReopenAsPendingOrExactlyOneFactAndNeverSaveForeignDraft() throws {
        let url=try root().appendingPathComponent("commit.sqlite")
        let original=try PersistenceContainerFactory.makeOnDisk(at:url)
        let service=InvestmentService(context:original.mainContext,clock:{self.clock})
        let activity=try service.createActivity(name:"Synthetic commit boundary")
        let participant=try XCTUnwrap(ModelContext(original).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let id=UUID()
        try service.start(activityID:activity,participantID:participant,operationID:id,zone:zone)
        clock.wall.addTimeInterval(60);clock.uptime += 60
        let running=try XCTUnwrap(service.operations().first)
        try service.command(.finish,id:id,revision:running.revision)
        let pending=try XCTUnwrap(service.operations().first)
        XCTAssertEqual(pending.timer.values.seconds,60)
        XCTAssertEqual(pending.timer.state,.pendingSave)
        original.mainContext.autosaveEnabled=false
        let foreign=Entry(body:"Synthetic unsaved foreign draft",createdAt:clock.wall)
        original.mainContext.insert(foreign)
        let failBefore=InvestmentService(context:original.mainContext,clock:{self.clock},commit:{ _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failBefore.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        let before=try PersistenceContainerFactory.makeOnDisk(at:url)
        let beforeService=InvestmentService(context:before.mainContext,clock:{self.clock})
        XCTAssertEqual(try beforeService.operations().first,pending)
        XCTAssertEqual(try ModelContext(before).fetchCount(FetchDescriptor<InvestmentSession>()),0)
        XCTAssertEqual(try ModelContext(before).fetchCount(FetchDescriptor<Entry>()),0)
        XCTAssertEqual(foreign.body,"Synthetic unsaved foreign draft")
        XCTAssertTrue(original.mainContext.hasChanges)
        let failAfter=InvestmentService(context:original.mainContext,clock:{self.clock},commit:{ try $0.save();throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try failAfter.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        let after=try PersistenceContainerFactory.makeOnDisk(at:url)
        let afterService=InvestmentService(context:after.mainContext,clock:{self.clock})
        XCTAssertEqual(try afterService.operations().first?.timer.state,.saved)
        let saved=try XCTUnwrap(ModelContext(after).fetch(FetchDescriptor<InvestmentSession>()).first)
        XCTAssertEqual(saved.id,id)
        XCTAssertEqual(try saved.values(),pending.timer.values)
        try afterService.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        XCTAssertEqual(try ModelContext(after).fetchCount(FetchDescriptor<InvestmentSession>()),1)
        XCTAssertEqual(try ModelContext(after).fetchCount(FetchDescriptor<Entry>()),0)
        XCTAssertEqual(foreign.body,"Synthetic unsaved foreign draft")
        XCTAssertTrue(original.mainContext.hasChanges)
        try afterService.delete(id:id,revision:saved.revision)
        XCTAssertThrowsError(try afterService.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        let final=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try ModelContext(final).fetchCount(FetchDescriptor<InvestmentSession>()),0)
        XCTAssertEqual(try InvestmentService(context:final.mainContext).operations().first?.timer.state,.deleted)
        XCTAssertEqual(try ModelContext(final).fetchCount(FetchDescriptor<Entry>()),0)
    }
    func testRevisionExhaustionZIPReopensAndEveryMutationFailsWithoutLosingFacts() async throws {
        let sourceRoot=try root(),source=try PersistenceContainerFactory.makeOnDisk(at:sourceRoot.appendingPathComponent("source.sqlite"))
        let service=InvestmentService(context:source.mainContext,clock:{self.clock})
        let activity=try service.createActivity(name:"Synthetic revision boundary")
        let participant=try XCTUnwrap(ModelContext(source).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let recordID=UUID(),pendingID=UUID(),draftID=UUID()
        let values=InvestmentValues(day:ImportantCivilDay(clock.wall,timeZone:zone).identifier,timeZoneID:zone.identifier,seconds:45,evidence:.dateDuration,source:.manual)
        try service.saveManual(id:recordID,participantID:participant,activityID:activity,values:values)
        try service.start(activityID:activity,participantID:participant,operationID:pendingID,zone:zone)
        clock.wall.addTimeInterval(60);clock.uptime += 60
        let running=try XCTUnwrap(service.operations().first { $0.id == pendingID })
        try service.command(.finish,id:pendingID,revision:running.revision)
        try service.storeDraft(id:draftID,participantID:participant,activityID:activity,values:values,durationText:"0.75")
        let boundary=ModelContext(source)
        for op in try boundary.fetch(FetchDescriptor<InvestmentOperation>()) {op.revision=Int.max-1}
        try boundary.save()
        let sourceBefore=try TransferSnapshot.make(context:ModelContext(source))
        let lease=try await transfer(source,sourceRoot).exportPackage();defer {lease.cleanup()}
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(source)),sourceBefore)
        let targetRoot=try root(),url=targetRoot.appendingPathComponent("restored.sqlite")
        let target=try PersistenceContainerFactory.makeOnDisk(at:url)
        _ = try await transfer(target,targetRoot).importPackage(from:lease.url)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
        let restored=InvestmentService(context:reopened.mainContext,clock:{self.clock})
        let pending=try XCTUnwrap(restored.operations().first { $0.id == pendingID })
        XCTAssertEqual(pending.timer.state,.recoveryRequired)
        XCTAssertEqual(pending.timer.values.seconds,60)
        var baseline=try TransferSnapshot.make(context:ModelContext(reopened))
        XCTAssertEqual(baseline.investmentSessions.count,1)
        func unchanged(_ action: () throws -> Void) throws {
            XCTAssertThrowsError(try action()) {XCTAssertEqual($0 as? InvestmentFailure,.invalid)}
            let disk=try PersistenceContainerFactory.makeOnDisk(at:url)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(disk)),baseline)
            try InvestmentIntegrity.validate(context:ModelContext(disk))
        }
        for command in [InvestmentService.Command.pause,.resume,.finish,.discard,.checkpoint] {
            // A non-running checkpoint is deliberately a no-op; it consumes no revision.
            if case .checkpoint=command {
                try restored.command(command,id:pendingID,revision:Int.max-1)
            } else {try unchanged {try restored.command(command,id:pendingID,revision:Int.max-1)}}
        }
        try unchanged {try restored.saveTimer(id:pendingID,revision:Int.max-1,values:pending.timer.values,confirmDuplicate:true)}
        try unchanged {try restored.storeDraft(id:draftID,participantID:participant,activityID:activity,values:values,durationText:"0.75",expectedRevision:Int.max-1)}
        var edited=values;edited.note="Synthetic edit at boundary"
        try unchanged {try restored.saveManual(id:recordID,participantID:participant,activityID:activity,values:edited,expectedRevision:0,confirmDuplicate:true)}
        try unchanged {try restored.saveManual(id:recordID,participantID:participant,activityID:activity,values:values,expectedRevision:0,draftID:draftID)}
        try unchanged {try restored.saveManual(id:UUID(),participantID:participant,activityID:activity,values:values,confirmDuplicate:true,draftID:draftID)}
        try unchanged {try restored.saveManual(id:draftID,participantID:participant,activityID:activity,values:values,confirmDuplicate:true)}
        try unchanged {try restored.delete(id:recordID,revision:0)}
        let editContext=ModelContext(reopened)
        let fact=try XCTUnwrap(editContext.fetch(FetchDescriptor<InvestmentSession>()).first)
        fact.revision=Int.max-1;try editContext.save()
        baseline=try TransferSnapshot.make(context:ModelContext(reopened))
        try unchanged {try restored.saveManual(id:recordID,participantID:participant,activityID:activity,values:edited,expectedRevision:Int.max-1,confirmDuplicate:true)}
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

    func testReviewerR9ReadableMinutesPreserveSubsecondFactThroughNoteEditAndReopen() throws {
        for seconds in [1.23456789123,1e-8,Double.leastNonzeroMagnitude] {
        let root = try root(), url = root.appendingPathComponent("precision.sqlite")
        let c = try PersistenceContainerFactory.makeOnDisk(at:url)
        let service = InvestmentService(context:c.mainContext)
        let activity = try service.createActivity(name:"Synthetic precision")
        let participant = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let id = UUID()
        let values = InvestmentValues(day:ImportantCivilDay(Date(),timeZone:zone).identifier,
            timeZoneID:zone.identifier,seconds:seconds,evidence:.dateDuration,source:.manual)
        try service.saveManual(id:id,participantID:participant,activityID:activity,values:values)
        let workspace = InvestmentWorkspace(); workspace.refresh(c.mainContext)
        let editor = workspace.edit(try XCTUnwrap(workspace.session(id:id,context:c.mainContext)))
        XCTAssertEqual(InvestmentFormatting.minutes(2700),"45")
        XCTAssertTrue(editor.hasValidDuration,editor.durationText)
        XCTAssertGreaterThan(try XCTUnwrap(Double(editor.durationText)),0)
        XCTAssertEqual(try XCTUnwrap(Double(editor.durationText))*60,seconds,accuracy:0.000001)
        editor.values.note = "Synthetic note only"; editor.persist(c.mainContext)
        try service.saveManual(id:id,participantID:participant,activityID:activity,values:editor.values,
            expectedRevision:editor.editingRevision,draftID:editor.id)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at:url)
        let saved = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<InvestmentSession>()).first)
        XCTAssertEqual(try saved.values().seconds,seconds)
        XCTAssertEqual(try saved.values().note,"Synthetic note only")
        let revision = saved.revision, timestamp = saved.updatedAt
        try InvestmentService(context:reopened.mainContext).saveManual(id:id,
            participantID:participant,activityID:activity,values:try saved.values(),expectedRevision:revision)
        let fresh = ModelContext(reopened)
        let afterNoOp = try XCTUnwrap(fresh.fetch(FetchDescriptor<InvestmentSession>()).first)
        XCTAssertEqual(afterNoOp.revision,revision); XCTAssertEqual(afterNoOp.updatedAt,timestamp)
        XCTAssertEqual(try afterNoOp.values().seconds,seconds)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<InvestmentSession>()),1)
        }
    }

    func testManualDraftActualZIPRetainsInvalidInputWithoutCreatingFormalFact() async throws {
        let sourceRoot=try root(),source=try PersistenceContainerFactory.makeOnDisk(at:sourceRoot.appendingPathComponent("source.sqlite"))
        let service=InvestmentService(context:source.mainContext)
        let activity=try service.createActivity(name:"Synthetic draft transfer")
        let workspace=InvestmentWorkspace();workspace.refresh(source.mainContext)
        let editor=try workspace.newEditor(activityID:activity)
        editor.durationText="invalid synthetic duration";editor.values.note="Synthetic unsaved note";editor.persist(source.mainContext)
        XCTAssertNil(editor.error)
        let before=try TransferSnapshot.make(context:ModelContext(source))
        let lease=try await ImportExportService(context:source.mainContext,mediaStore:MediaStore(rootURL:sourceRoot),availableCapacity:{.max}).exportPackage()
        defer {lease.cleanup()}
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(source)),before)
        let targetRoot=try root(),url=targetRoot.appendingPathComponent("target.sqlite")
        let target=try PersistenceContainerFactory.makeOnDisk(at:url)
        _ = try await ImportExportService(context:target.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max}).importPackage(from:lease.url)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
        let restored=InvestmentWorkspace();restored.refresh(reopened.mainContext)
        XCTAssertTrue(restored.review?.orderedSessionIDs.isEmpty == true)
        let draft=try XCTUnwrap(restored.drafts.first);XCTAssertEqual(draft.id,editor.id)
        let restoredEditor=restored.editor(for:draft)
        XCTAssertEqual(restoredEditor.durationText,"invalid synthetic duration")
        XCTAssertEqual(restoredEditor.values.note,"Synthetic unsaved note");XCTAssertNil(restoredEditor.values.feeling)
        XCTAssertFalse(restoredEditor.hasValidDuration)
        restoredEditor.durationText="30";restoredEditor.values.changeDuration(1800);restoredEditor.persist(reopened.mainContext)
        XCTAssertNil(restoredEditor.error)
        try InvestmentService(context:reopened.mainContext).saveManual(id:restoredEditor.id,
            participantID:restoredEditor.participantID,activityID:restoredEditor.activityID,
            values:restoredEditor.values,draftID:restoredEditor.id)
        let saved=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try saved.mainContext.fetchCount(FetchDescriptor<InvestmentSession>()),1)
        XCTAssertEqual(try XCTUnwrap(saved.mainContext.fetch(FetchDescriptor<InvestmentSession>()).first).values().seconds,1800)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(source)),before)
    }

    func testUsageFiveYearSnapshotReusesStatisticsAndBoundsRealDiskPageThenRefreshesChanges() async throws {
        let folder=try root(),container=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("usage-review.sqlite"))
        let context=ModelContext(container),p=InvestmentParticipant(name:"Synthetic default",isDefault:true)
        let a=InvestmentActivity(participantID:p.id,name:"Synthetic archive history")
        a.isArchived=true;context.insert(p);context.insert(a)
        let today=ImportantCivilDay(identifier:"2026-10-18")!
        for i in 0..<10000 {
            let day=today.adding(days:-(i % 1826))!
            var values=InvestmentValues(day:day.identifier,timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual)
            if i % 100 == 0 {
                let start=day.instant(minutes:600,timeZone:zone)!
                values.evidence = .intervals;values.spans=[.init(start:start,end:start.addingTimeInterval(30)),.init(start:start.addingTimeInterval(60),end:start.addingTimeInterval(90))]
                values.note=String(repeating:"Synthetic long saved note ",count:100)
            }
            let id=UUID()
            context.insert(try InvestmentSession(id:id,participantID:p.id,activityID:a.id,values:values,now:day.date!.addingTimeInterval(86400)))
            context.insert(try InvestmentOperation(id:id,participantID:p.id,activityID:a.id,
                timer:.init(state:.saved,values:values,target:nil,checkpointAt:day.date!.addingTimeInterval(86400)),now:day.date!.addingTimeInterval(86400)))
        }
        try context.save();try InvestmentIntegrity.validate(context:ModelContext(container))
        var events: [InvestmentReadEvent] = [],readFailure=false
        let reader=InvestmentUIReader(observe:{event in
            events.append(event) // Count attempts before any injected read failure.
            if readFailure && event.purpose == .factBatch {throw CocoaError(.fileReadUnknown)}
        })
        func peakResidentBytes() -> Int64 {var value=rusage();getrusage(RUSAGE_SELF,&value);return Int64(value.ru_maxrss)}
        let peakBefore=peakResidentBytes()
        let workspace=InvestmentWorkspace(reader:reader),start=Date();workspace.refresh(context)
        print("USAGE_INVESTMENT_10000_DISK_REFRESH_SECONDS=\(Date().timeIntervalSince(start))")
        print("REVIEW_F5_HOST_PEAK_RSS_BYTES beforeRefresh=\(peakBefore) afterRefresh=\(peakResidentBytes()) includesFixtureAndTestHost=true")
        XCTAssertNil(workspace.reviewError)
        let snapshot=try XCTUnwrap(workspace.review)
        XCTAssertEqual(snapshot.activitySeconds[a.id],600000)
        XCTAssertEqual(snapshot.selection(days:nil,today:today,activityID:a.id,day:nil).daySeconds.count,1826)
        XCTAssertEqual(events.filter {$0.purpose == .factBatch}.reduce(0) {$0+$1.decoded},10000)
        XCTAssertEqual(events.filter {$0.purpose == .operationBatch}.reduce(0) {$0+$1.decoded},10000)
        XCTAssertTrue(workspace.operations.isEmpty) // no saved Operation payloads are retained
        var delivered: XCTestExpectation?,awaitedSequences=Set<Int>()
        let subscription=NotificationCenter.default.publisher(for:.investmentChanged).receive(on:RunLoop.main).sink {notification in
            MainActor.assumeIsolated {
                guard notification.object as? ModelContainer === container else {return}
                workspace.receive(notification,context:context)
                if let sequence=notification.userInfo?["sequence"] as? Int,awaitedSequences.remove(sequence) != nil {delivered?.fulfill()}
            }
        }
        defer {subscription.cancel()}
        func event(count: Int = 1,_ action: () throws -> Void) async throws {
            let expected=expectation(description:"Service → event → Workspace")
            expected.expectedFulfillmentCount=count;delivered=expected
            let before=InvestmentChanges.version(container).sequence
            try action()
            let after=InvestmentChanges.version(container).sequence
            XCTAssertEqual(after-before,count)
            awaitedSequences=Set((before+1)...after)
            await fulfillment(of:[expected],timeout:5);delivered=nil
        }
        var time=InvestmentClock(wall:Date(),uptime:100,processID:"review-f5-continuous")
        let live=InvestmentService(context:context,clock:{time})
        let originalFactReads=events.filter {$0.purpose == .factBatch}.reduce(0) {$0+$1.decoded}
        let originalOperationReads=events.filter {$0.purpose == .operationBatch}.reduce(0) {$0+$1.decoded}
        let initialFactFetches=events.filter {$0.purpose == .factBatch && $0.rows == 0}.count
        let initialOperationFetches=events.filter {$0.purpose == .operationBatch && $0.rows == 0}.count
        XCTAssertEqual(initialFactFetches,40);XCTAssertEqual(initialOperationFetches,40)
        try await event {try live.updateActivity(id:a.id,name:"Renamed history",archived:false)}
        let draft=try workspace.newEditor(activityID:a.id)
        for i in 0..<4 {
            draft.values.note="Last durable draft \(i)";draft.durationText=String(31+i);draft.values.changeDuration(Double(31+i)*60)
            try await event {XCTAssertTrue(draft.persist(context))}
        }
        let timerID=UUID()
        try await event {_ = try live.start(activityID:a.id,participantID:p.id,operationID:timerID,zone:zone)}
        time.wall.addTimeInterval(10);time.uptime += 10
        try await event(count:2) {workspace.checkpoint(context,clock:{time})}
        try await event {try live.command(.pause,id:timerID,revision:XCTUnwrap(workspace.unfinished.first?.revision))}
        try await event {try live.command(.resume,id:timerID,revision:XCTUnwrap(workspace.unfinished.first?.revision))}
        XCTAssertEqual(events.filter {$0.purpose == .factBatch}.reduce(0) {$0+$1.decoded},originalFactReads)
        XCTAssertEqual(events.filter {$0.purpose == .operationBatch}.reduce(0) {$0+$1.decoded},originalOperationReads)
        let cold=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("usage-review.sqlite"))
        let recovered=InvestmentWorkspace();recovered.refresh(cold.mainContext)
        XCTAssertEqual(recovered.drafts.first?.timer.values.note,"Last durable draft 3")
        XCTAssertEqual(recovered.drafts.first?.timer.durationText,"34")
        draft.values.note="Unsaved retained input"
        XCTAssertFalse(draft.persist(context,commit:{_ in throw CocoaError(.fileWriteOutOfSpace)}))
        XCTAssertNotNil(draft.error);XCTAssertEqual(draft.values.note,"Unsaved retained input")
        let disk=try InvestmentService(context:cold.mainContext).operations().first {$0.id == draft.id}
        XCTAssertEqual(disk?.timer.values.note,"Last durable draft 3")
        print("REVIEW_F5_CHAIN factDecoded=\(originalFactReads) operationBatchDecoded=\(originalOperationReads) initialFactFetches=\(initialFactFetches) initialOperationFetches=\(initialOperationFetches) afterDraftAndTimerFactFetches=\(events.filter {$0.purpose == .factBatch && $0.rows == 0}.count) afterDraftAndTimerOperationFetches=\(events.filter {$0.purpose == .operationBatch && $0.rows == 0}.count) afterDraftAndTimerFactDecoded=\(events.filter {$0.purpose == .factBatch}.reduce(0) {$0+$1.decoded}) operationIDDecoded=\(events.filter {$0.purpose == .operationIDs}.reduce(0) {$0+$1.decoded})")
        let generation=workspace.reviewGeneration
        workspace.refresh(context);XCTAssertEqual(workspace.reviewGeneration,generation)
        let chosen=snapshot.selection(days:nil,today:today,activityID:a.id,day:nil)
        let first=chosen.pageIDs(offset:0),second=chosen.pageIDs(offset:20)
        XCTAssertEqual(first.count,20);XCTAssertEqual(second.count,20);XCTAssertTrue(Set(first).isDisjoint(with:second))
        let decodedBefore=events.reduce(0) {$0+($1.purpose == .page ? $1.decoded:0)}
        let page=try reader.page(container,ids:first)
        let nextPage=try reader.page(container,ids:second)
        XCTAssertEqual(nextPage.map(\.id),second)
        XCTAssertEqual(events.reduce(0) {$0+($1.purpose == .page ? $1.decoded:0)}-decodedBefore,40)
        let detailed=try workspace.session(id:second[0],context:context)
        XCTAssertEqual(detailed?.id,second[0]);XCTAssertEqual(events.filter {$0.purpose == .detail}.reduce(0) {$0+$1.decoded},1)
        XCTAssertEqual(page.count,20);XCTAssertEqual(Set(page.map(\.id)),Set(first))
        let edit=try XCTUnwrap(page.first)
        let service=InvestmentService(context:context)
        var values=edit.values;values.changeDuration(120)
        try service.saveManual(id:edit.id,participantID:p.id,activityID:a.id,values:values,expectedRevision:edit.revision,confirmDuplicate:true)
        workspace.refresh(context);XCTAssertEqual(workspace.review?.activitySeconds[a.id],600060)
        XCTAssertGreaterThan(workspace.reviewGeneration,generation)
        let changed=try XCTUnwrap(workspace.session(id:edit.id,context:context))
        try service.delete(id:edit.id,revision:changed.revision)
        workspace.refresh(context);XCTAssertEqual(workspace.review?.activitySeconds[a.id],599940)
        XCTAssertEqual(workspace.review?.orderedSessionIDs.count,9999)
        // Corrupt payload is an explicit read failure, followed by successful retry, never a false zero.
        let read=ModelContext(container),bad=try XCTUnwrap(read.fetch(FetchDescriptor<InvestmentSession>()).first)
        let original=bad.valueData;bad.valueData=Data("invalid synthetic payload".utf8);try read.save();InvestmentChanges.publish(.all,container:container)
        workspace.refresh(context);XCTAssertNil(workspace.review);XCTAssertNotNil(workspace.reviewError)
        bad.valueData=original;try read.save();InvestmentChanges.publish(.all,container:container);workspace.refresh(context)
        XCTAssertNil(workspace.reviewError);XCTAssertEqual(workspace.review?.activitySeconds[a.id],599940)
        readFailure=true;InvestmentChanges.publish(.all,container:container);workspace.refresh(context)
        XCTAssertNil(workspace.review);XCTAssertNotNil(workspace.reviewError)
        let failedReads=events.filter {$0.purpose == .factBatch}.count
        for index in 0..<2 {
            draft.values.note="Draft while statistics unavailable \(index)"
            try await event {XCTAssertTrue(draft.persist(context))}
        }
        XCTAssertNil(workspace.review);XCTAssertNotNil(workspace.reviewError)
        XCTAssertEqual(events.filter {$0.purpose == .factBatch}.count,failedReads)
        readFailure=false;workspace.refresh(context,retry:true)
        XCTAssertEqual(workspace.review?.activitySeconds[a.id],599940)
        let export=try await transfer(container,folder).exportPackage();defer {export.cleanup()}
        let targetRoot=try root(),target=try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("imported.sqlite"))
        let imported=InvestmentWorkspace();imported.refresh(target.mainContext)
        XCTAssertEqual(imported.review?.orderedSessionIDs.count,0)
        let importedEvent=expectation(description:"Import → event → Workspace")
        let importSubscription=NotificationCenter.default.publisher(for:.investmentChanged).receive(on:RunLoop.main).sink {notification in
            MainActor.assumeIsolated {
                guard notification.object as? ModelContainer === target else {return}
                imported.receive(notification,context:target.mainContext);importedEvent.fulfill()
            }
        }
        _ = try await transfer(target,targetRoot).importPackage(from:export.url)
        await fulfillment(of:[importedEvent],timeout:5);importSubscription.cancel()
        XCTAssertEqual(imported.review?.orderedSessionIDs.count,9999)
        XCTAssertEqual(imported.review?.activitySeconds[a.id],599940)
        XCTAssertNil(try imported.session(id:edit.id,context:target.mainContext))
        let importedIDs=Array(try XCTUnwrap(imported.review?.orderedSessionIDs).prefix(20))
        XCTAssertEqual(try imported.reader.page(target,ids:importedIDs).map(\.id),importedIDs)
        print("REVIEW_F5_PAGE pageDecoded=40 detailDecodedBeforeEdits=1 initialSavedPayloadsRetained=0 batchesOfAtMost=256 peakRSSScope=wholeHostIncludingFixture")
    }

    func testUsageV14StartupMigrationKeepsLatestProtectionAndAddsNoDefaultSettings() throws {
        let folder=try root(),url=folder.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let entryID=UUID(),factID=UUID(),taskID=UUID()
        var latestProtection: URL!
        try autoreleasepool {
            let schema=Schema(versionedSchema:PersonalGrowthSchemaV14.self)
            let old=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
            let context=old.mainContext
            let entry=Entry(id:entryID,body:"Synthetic older protection",createdAt:clock.wall);context.insert(entry)
            let participant=InvestmentParticipant(),activity=InvestmentActivity(participantID:participant.id,name:"Synthetic V14 activity")
            context.insert(participant);context.insert(activity)
            let values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:300,evidence:.dateDuration,source:.manual)
            context.insert(try InvestmentSession(id:factID,participantID:participant.id,activityID:activity.id,values:values,now:clock.wall))
            context.insert(try InvestmentOperation(id:factID,participantID:participant.id,activityID:activity.id,timer:.init(state:.saved,values:values,target:nil,checkpointAt:clock.wall),now:clock.wall))
            let task=TodoTask(id:taskID,title:"Synthetic V14 todo",createdAt:clock.wall);context.insert(task)
            context.insert(TodoTaskEvent(taskID:task.id,sequence:0,kind:.created,occurredAt:clock.wall,createdAt:clock.wall,beforeValue:nil,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
            context.insert(WeightRecord(weightKilograms:72,recordedAt:clock.wall,createdAt:clock.wall))
            context.insert(try SleepRecord(wakeDay:"2026-10-15",timeZoneID:zone.identifier,values:SleepValues(feeling:4),createdAt:clock.wall))
            try context.save()
            let older=try StartupRetainedData.capture(rootURL:folder,purpose:.beforeMigration)
            entry.body="Synthetic latest V14 fact";try context.save()
            latestProtection=try StartupRetainedData.capture(rootURL:folder,purpose:.beforeMigration).snapshotURL
            XCTAssertNotEqual(older.snapshotURL,latestProtection)
            XCTAssertFalse(StartupStoreProtection.isCurrentStore(at:url))
        }
        let app=try AppContainer.make(configuration:AppConfiguration(launchMode:.uiTesting,resetDataOnLaunch:false),rootURLOverride:folder)
        let read=ModelContext(app.modelContainer)
        XCTAssertTrue(StartupStoreProtection.isCurrentStore(at:url))
        XCTAssertEqual(try read.fetch(FetchDescriptor<Entry>()).first?.body,"Synthetic latest V14 fact")
        XCTAssertEqual(try read.fetch(FetchDescriptor<TodoTask>()).first?.id,taskID)
        XCTAssertEqual(try read.fetch(FetchDescriptor<InvestmentSession>()).first?.id,factID)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<BodyReferenceSettings>()),0)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<TodoSeriesPreferences>()),0)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<TodoReminderIntent>()),0)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<TodoReminderDeviceRecord>()),0)
        let schema=Schema(versionedSchema:PersonalGrowthSchemaV14.self),retainedURL=latestProtection.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        let retained=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:retainedURL,allowsSave:false,cloudKitDatabase:.none)])
        XCTAssertEqual(try retained.mainContext.fetch(FetchDescriptor<Entry>()).first?.body,"Synthetic latest V14 fact")
        let expected=try TransferSnapshot.make(context:read),reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
    }
    func testUsageV11ActualZIPSettingsRoundTripRollbackEmptyGuardAndDeviceJournalExclusion() async throws {
        let folder=try root(),source=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("source.sqlite"))
        let service=TodoTaskService(context:source.mainContext,now:{self.clock.wall})
        let task=try service.create(.init(title:"Synthetic alarm intent",plannedDay:"2026-10-16",remindAt:clock.wall.addingTimeInterval(3600),frequency:.daily,reminderChannel:.alarm))
        try service.rescheduleReminder(id:task.id,to:clock.wall.addingTimeInterval(4800),channel:.alarm)
        let intent=try XCTUnwrap(service.reminderIntent(for:task.id))
        XCTAssertTrue(intent.isInstanceOverride)
        source.mainContext.insert(BodyReferenceSettings(heightCentimeters:175.5,reference:.who))
        source.mainContext.insert(TodoReminderDeviceRecord(taskID:task.id,intentGeneration:intent.generation,channel:.alarm,fireAt:try XCTUnwrap(service.task(id:task.id).remindAt),phase:.accepted))
        try source.mainContext.save();try UsagePreferencesIntegrity.validate(context:ModelContext(source))
        let before=try TransferSnapshot.make(context:ModelContext(source))
        let lease=try await transfer(source,folder).exportPackage();defer {lease.cleanup()}
        let (exported,extracted)=try zipData(lease.url)
        XCTAssertEqual(exported,before);XCTAssertEqual(ExportManifest.currentPackageSchemaVersion,11)
        let bytes=try Data(contentsOf:extracted.appendingPathComponent("data.json"))
        XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("intentGeneration"))
        let destination=try root(),targetURL=destination.appendingPathComponent("target.sqlite"),target=try PersistenceContainerFactory.makeOnDisk(at:targetURL)
        let failing=transfer(target,destination,checkpoint:{if $0 == .beforeSave {throw CocoaError(.fileWriteOutOfSpace)}})
        do {_ = try await failing.importPackage(from:lease.url);XCTFail("Injected publication failure ignored")} catch {}
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(target)).totalObjectCount,0)
        _ = try await transfer(target,destination).importPackage(from:lease.url)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:targetURL),read=ModelContext(reopened)
        XCTAssertEqual(try TransferSnapshot.make(context:read),before)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<TodoReminderDeviceRecord>()),0)
        let onlySettings=try root(),settingsStore=try PersistenceContainerFactory.makeOnDisk(at:onlySettings.appendingPathComponent("settings.sqlite"))
        settingsStore.mainContext.insert(BodyReferenceSettings(heightCentimeters:180));try settingsStore.mainContext.save()
        do {_ = try await transfer(settingsStore,onlySettings).importPackage(from:lease.url);XCTFail("Settings-only target accepted")} catch {XCTAssertEqual(error as? TransferPackageError,.targetNotEmpty)}
        XCTAssertEqual(try ModelContext(settingsStore).fetch(FetchDescriptor<BodyReferenceSettings>()).first?.heightCentimeters,180)
        XCTAssertThrowsError(try exported.validateUsagePreferences(packageVersion:10))
        var body=try XCTUnwrap(exported.bodyReferenceSettings.first);body.heightCentimeters = .infinity
        let invalid=TransferData(entries:[],images:[],tags:[],links:[],habits:[],habitLogs:[],goals:[],goalEvents:[],bodyReferenceSettings:[body])
        XCTAssertThrowsError(try invalid.validateUsagePreferences(packageVersion:11))
    }

    func testUsageV11RawRequiredArraysRejectAndRealLegacyV10DefaultsRestore() async throws {
        let folder=try root(),source=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("wire-source.sqlite"))
        source.mainContext.insert(Entry(body:"Synthetic v10 compatibility fact",createdAt:clock.wall))
        source.mainContext.insert(BodyReferenceSettings(heightCentimeters:180,reference:.who));try source.mainContext.save()
        let lease=try await transfer(source,folder).exportPackage();defer {lease.cleanup()}
        let (data,extracted)=try zipData(lease.url)
        let originalPayload=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("data.json"))) as? [String:Any])
        let originalManifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("manifest.json"))) as? [String:Any])
        let keys=["todoSeriesPreferences","todoReminderIntents","bodyReferenceSettings"]
        for scenario in 0..<5 {
            var payload=originalPayload,manifest=originalManifest
            let version=scenario < 3 ? 11 : 10
            if scenario < 3 {payload.removeValue(forKey:keys[scenario])}
            if scenario == 4 {for key in keys {payload.removeValue(forKey:key)}}
            let bytes=try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)
            let dataURL=extracted.appendingPathComponent("data.json"),manifestURL=extracted.appendingPathComponent("manifest.json")
            try bytes.write(to:dataURL)
            manifest["packageSchemaVersion"]=version;manifest["objectCounts"]=data.objectCounts(forPackageSchemaVersion:version)
            var file=try XCTUnwrap(manifest["dataFile"] as? [String:Any]);file["byteCount"]=bytes.count
            file["sha256"]=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined();manifest["dataFile"]=file
            try JSONSerialization.data(withJSONObject:manifest,options:.sortedKeys).write(to:manifestURL)
            let archive=folder.appendingPathComponent("usage-wire-\(scenario).zip")
            try ZIPArchiveWriter.write(sources:[.init(path:"manifest.json",fileURL:manifestURL),.init(path:"data.json",fileURL:dataURL)],to:archive)
            let destination=try root(),target=try PersistenceContainerFactory.makeOnDisk(at:destination.appendingPathComponent("target.sqlite"))
            if scenario < 4 {
                do {_ = try await transfer(target,destination).importPackage(from:archive);XCTFail("Invalid usage metadata accepted")} catch {}
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(target)).totalObjectCount,0)
            } else {
                _ = try await transfer(target,destination).importPackage(from:archive)
                XCTAssertEqual(try ModelContext(target).fetch(FetchDescriptor<Entry>()).first?.body,"Synthetic v10 compatibility fact")
                XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<BodyReferenceSettings>()),0)
                XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<TodoReminderIntent>()),0)
            }
        }
        // The actual new-format ZIP retains the custom weekday set through import and successor generation.
        let task=try TodoTaskService(context:source.mainContext,now:{self.clock.wall},timeZone:{self.zone}).create(.init(title:"Synthetic exported weekdays",plannedDay:"2026-10-16",frequency:.customWeekdays,weekdays:[2,7]))
        let current=try await transfer(source,folder).exportPackage();defer {current.cleanup()}
        let destination=try root(),target=try PersistenceContainerFactory.makeOnDisk(at:destination.appendingPathComponent("current.sqlite"))
        _ = try await transfer(target,destination).importPackage(from:current.url)
        let service=TodoTaskService(context:target.mainContext,now:{self.clock.wall},timeZone:{self.zone})
        XCTAssertEqual(try service.preferences(for:XCTUnwrap(task.seriesID))?.weekdaysMask,66)
        try service.transition(id:task.id,to:.completed)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open}?.plannedDay,"2026-10-18")
    }

}

extension InvestmentPersistenceTests {
    func testReviewFixF5PageDetailReadFailureRetriesAndDeletionErasesCachedEditor() throws {
        let folder=try root(),c=try PersistenceContainerFactory.makeOnDisk(at:folder.appendingPathComponent("cache-errors.sqlite"))
        let service=InvestmentService(context:c.mainContext),a=try service.createActivity(name:"Synthetic cache")
        let p=try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<InvestmentParticipant>()).first).id,id=UUID()
        let start=ImportantCivilDay(identifier:"2026-09-01")!.instant(minutes:600,timeZone:zone)!
        let values=InvestmentValues(day:"2026-09-01",timeZoneID:zone.identifier,seconds:2700,evidence:.intervals,source:.manual,
            spans:[.init(start:start,end:start.addingTimeInterval(1200)),.init(start:start.addingTimeInterval(1500),end:start.addingTimeInterval(3000))],note:"Synthetic detail to erase")
        try service.saveManual(id:id,participantID:p,activityID:a,values:values)
        var failing=false,metadataFailure=false
        let reader=InvestmentUIReader(observe:{event in
            if metadataFailure && event.purpose == .metadata {throw CocoaError(.fileReadUnknown)}
            if failing && [.page,.detail].contains(event.purpose) {throw CocoaError(.fileReadUnknown)}
        })
        let workspace=InvestmentWorkspace(reader:reader);workspace.refresh(c.mainContext)
        failing=true
        XCTAssertThrowsError(try reader.page(c,ids:[id]))
        XCTAssertThrowsError(try workspace.session(id:id,context:c.mainContext))
        failing=false
        metadataFailure=true;InvestmentChanges.publish(.metadata,container:c);workspace.refresh(c.mainContext)
        XCTAssertNotNil(workspace.error);XCTAssertTrue(workspace.activities.isEmpty)
        metadataFailure=false;workspace.refresh(c.mainContext)
        XCTAssertNotNil(workspace.error)
        workspace.refresh(c.mainContext,retry:true)
        XCTAssertNil(workspace.error);XCTAssertEqual(workspace.myActivities.count,1)
        XCTAssertEqual(try reader.page(c,ids:[id]).map(\.id),[id])
        let editor=workspace.edit(try XCTUnwrap(workspace.session(id:id,context:c.mainContext)))
        editor.showDuplicates([id]);editor.values.note="Changed input invalidates candidate cache"
        XCTAssertTrue(editor.persist(c.mainContext))
        XCTAssertFalse(editor.duplicate);XCTAssertNil(editor.duplicateValues)
        editor.showDuplicates([id])
        XCTAssertFalse(try editor.requestExactInterval(start:start,end:start.addingTimeInterval(3000),now:Date()))
        XCTAssertNotNil(editor.pendingExactInterval)
        XCTAssertNotNil(editor.duplicateValues)
        XCTAssertTrue(editor.persist(c.mainContext));workspace.refresh(c.mainContext)
        XCTAssertEqual(workspace.drafts.count,1)
        try service.delete(id:id,revision:0);workspace.refresh(c.mainContext)
        XCTAssertNil(try workspace.session(id:id,context:c.mainContext))
        XCTAssertTrue(workspace.drafts.isEmpty);XCTAssertTrue(workspace.editors.isEmpty)
        XCTAssertTrue(editor.finished);XCTAssertEqual(editor.values.note,"");XCTAssertTrue(editor.values.spans.isEmpty)
        XCTAssertEqual(editor.durationText,"")
        XCTAssertNil(editor.duplicateValues);XCTAssertNil(editor.duplicateDuration);XCTAssertNil(editor.duplicateActivity)
        XCTAssertTrue(editor.duplicateIDs.isEmpty);XCTAssertFalse(editor.duplicate);XCTAssertNil(editor.pendingExactInterval)
    }
}
