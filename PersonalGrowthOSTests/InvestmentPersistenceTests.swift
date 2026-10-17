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
        let editor = workspace.edit(try XCTUnwrap(workspace.sessions.first))
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
        XCTAssertTrue(restored.sessions.isEmpty)
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

}
