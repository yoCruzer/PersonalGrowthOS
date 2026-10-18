import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor final class InvestmentFoundationTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    var clock = InvestmentClock(wall: Date(timeIntervalSince1970: 1792113600), uptime: 1000, processID: "synthetic-process")
    func advance(_ seconds: Double) { clock.wall.addTimeInterval(seconds); clock.uptime += seconds }
    func service(_ c: ModelContainer) -> InvestmentService { .init(context: c.mainContext, clock: { self.clock }) }
    func setup(_ c: ModelContainer) throws -> (InvestmentService, UUID, UUID, UUID) {
        let s = service(c), a = try s.createActivity(name: "Synthetic reading")
        let p = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id, op = UUID()
        try s.start(activityID: a, participantID: p, operationID: op, zone: zone)
        return (s, a, p, op)
    }
    func op(_ s: InvestmentService, _ id: UUID) throws -> InvestmentOperationSnapshot { try XCTUnwrap(s.operations().first { $0.id == id }) }
    func command(_ s: InvestmentService, _ id: UUID, _ command: InvestmentService.Command) throws {
        try s.command(command, id: id, revision: op(s, id).revision)
    }
    func sessions(_ c: ModelContainer) throws -> [InvestmentSession] { try ModelContext(c).fetch(FetchDescriptor<InvestmentSession>()) }
    func f1Start(_ container: ModelContainer, readings: @escaping () -> InvestmentClock, target: Double? = nil) throws -> (InvestmentService,UUID) {
        let service=InvestmentService(context:container.mainContext,clock:readings)
        let activity=try service.createActivity(name:"Synthetic F1 clock evidence")
        let participant=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        let id=UUID();try service.start(activityID:activity,participantID:participant,operationID:id,target:target,zone:zone)
        return (service,id)
    }
    func testF1ProductionSamplerSelectsContinuousNotAwakeAndLiveClockIsProcessScoped() {
        let wall=Date(timeIntervalSince1970:1792113600)
        let reading=InvestmentClock.sample(wall:wall,continuousElapsed:123456.75,awakeUptime:12.5,processID:"synthetic-continuous-process")
        XCTAssertEqual(reading.wall,wall);XCTAssertEqual(reading.uptime,123456.75)
        let notAwake=InvestmentClock.sample(wall:wall,continuousElapsed:25,awakeUptime:.nan,processID:reading.processID)
        XCTAssertEqual(notAwake.uptime,25)
        let first=InvestmentClock.current(),second=InvestmentClock.current()
        XCTAssertTrue(first.uptime.isFinite);XCTAssertGreaterThanOrEqual(first.uptime,0)
        XCTAssertGreaterThanOrEqual(second.uptime,first.uptime);XCTAssertEqual(first.processID,second.processID)
        XCTAssertTrue(first.processID.hasPrefix("continuous-v1:"),"Legacy awake-only process tokens must not identify new clock anchors")
    }
    func testF1ServiceStopwatchIncludesSleepWhileAwakeAdvancesOnlyThirtySeconds() throws {
        var readings=InvestmentClockTestReadings()
        let container=try PersistenceContainerFactory.makeInMemory()
        let (service,id)=try f1Start(container,readings:{readings.sample()})
        readings.advance(wall:120,continuous:120,awake:120);try command(service,id,.checkpoint)
        readings.advance(wall:1800,continuous:1800,awake:30);try command(service,id,.checkpoint)
        let timer=try op(service,id).timer
        XCTAssertEqual(timer.state,.running);XCTAssertEqual(timer.values.seconds,1920)
        XCTAssertEqual(timer.anchorUptime,readings.continuousElapsed);XCTAssertEqual(timer.checkpointAt,readings.wall)
        XCTAssertEqual(timer.values.spans.map(\.seconds),[120,1800]);try timer.values.validate(now:readings.wall)
    }
    func testF1ServiceCountdownSleepCapsAtTargetAndExplicitContinueOmitsLateGap() throws {
        var readings=InvestmentClockTestReadings()
        let container=try PersistenceContainerFactory.makeInMemory()
        let (service,id)=try f1Start(container,readings:{readings.sample()},target:1500)
        readings.advance(wall:120,continuous:120,awake:120);try command(service,id,.checkpoint)
        readings.advance(wall:3000,continuous:3000,awake:30);try command(service,id,.checkpoint)
        let reached=try op(service,id).timer
        XCTAssertEqual(reached.state,.targetReached);XCTAssertEqual(reached.values.seconds,1500)
        XCTAssertNil(reached.anchor);XCTAssertNil(reached.anchorUptime)
        try command(service,id,.resume);XCTAssertNil(try op(service,id).timer.target)
        let resumedAt=readings.wall
        readings.advance(wall:60,continuous:60,awake:5);try command(service,id,.finish)
        let finished=try op(service,id).timer
        XCTAssertEqual(finished.state,.pendingSave);XCTAssertEqual(finished.values.seconds,1560)
        XCTAssertEqual(finished.values.spans.last?.start,resumedAt)
        XCTAssertEqual(finished.values.spans.count,3);try finished.values.validate(now:readings.wall)
    }
    func testF1PausedSleepDoesNotAccumulateOrConsumeCountdown() throws {
        var readings=InvestmentClockTestReadings()
        let container=try PersistenceContainerFactory.makeInMemory()
        let (service,id)=try f1Start(container,readings:{readings.sample()},target:1500)
        readings.advance(wall:120,continuous:120,awake:120);try command(service,id,.pause)
        let paused=try op(service,id)
        readings.advance(wall:3000,continuous:3000,awake:30);try command(service,id,.checkpoint)
        XCTAssertEqual(try op(service,id),paused)
        try command(service,id,.finish)
        XCTAssertEqual(try op(service,id).timer.values.seconds,120);XCTAssertEqual(try op(service,id).timer.target,1500)
    }
    func testF1TrueWallJumpsContinuousRegressionAndProcessChangeRetainCheckpoint() throws {
        for scenario in ["forward","backward","elapsed-regression","elapsed-nonfinite","process-change","reboot"] {
            var readings=InvestmentClockTestReadings()
            let container=try PersistenceContainerFactory.makeInMemory()
            let (service,id)=try f1Start(container,readings:{readings.sample()})
            readings.advance(wall:120,continuous:120,awake:120);try command(service,id,.checkpoint)
            let original=try op(service,id).timer
            switch scenario {
            case "forward":readings.advance(wall:3630,continuous:30,awake:30)
            case "backward":readings.advance(wall:-3570,continuous:30,awake:30)
            case "elapsed-regression":readings.advance(wall:30,continuous:-1,awake:30)
            case "elapsed-nonfinite":readings.advance(wall:30,continuous:.infinity,awake:30)
            case "process-change":readings.advance(wall:30,continuous:30,awake:30);readings.processID="synthetic-next-process"
            default:readings.advance(wall:30,continuous:30,awake:30);readings.continuousElapsed=0;readings.awakeUptime=0;readings.processID="synthetic-after-reboot"
            }
            try command(service,id,.checkpoint);let result=try op(service,id).timer
            XCTAssertEqual(result.state,.recoveryRequired,scenario);XCTAssertEqual(result.values,original.values,scenario)
            XCTAssertEqual(result.checkpointAt,original.checkpointAt,scenario)
            XCTAssertNil(result.anchor,scenario);XCTAssertNil(result.anchorUptime,scenario);XCTAssertNil(result.processID,scenario)
        }
    }
    func testF1SleepMicrodriftKeepsAdjacentSpansAndEighteenHourGuard() throws {
        var readings=InvestmentClockTestReadings()
        let container=try PersistenceContainerFactory.makeInMemory()
        let (service,id)=try f1Start(container,readings:{readings.sample()})
        readings.advance(wall:60.000001,continuous:60,awake:1);try command(service,id,.checkpoint)
        readings.advance(wall:60,continuous:60,awake:2);try command(service,id,.finish)
        let value=try op(service,id).timer.values
        XCTAssertEqual(value.seconds,120.000001,accuracy:0.000001);XCTAssertEqual(value.spans.count,2)
        if value.spans.count==2 {XCTAssertEqual(value.spans[0].end,value.spans[1].start)}
        try value.validate(now:readings.wall)
        for duration in [18.0*3600,18.0*3600+0.001] {
            var bounded=InvestmentClockTestReadings()
            let disk=try PersistenceContainerFactory.makeInMemory(),(s,opID)=try f1Start(disk,readings:{bounded.sample()})
            bounded.advance(wall:duration,continuous:duration,awake:30);try command(s,opID,.checkpoint)
            let timer=try op(s,opID).timer
            XCTAssertEqual(timer.state,duration==64800 ? .running:.recoveryRequired)
            XCTAssertEqual(timer.values.seconds,duration==64800 ? 64800:0)
        }
    }
    func testT1PauseExcludesFiveMinutesAndDoesNotDependOnTicks() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s, _, _, id) = try setup(c)
        advance(600); try command(s,id,.pause); advance(300); try command(s,id,.resume); advance(900); try command(s,id,.finish)
        let pending = try op(s,id); XCTAssertEqual(pending.timer.values.seconds,1500); XCTAssertEqual(pending.timer.state,.pendingSave)
        XCTAssertTrue(try sessions(c).isEmpty)
        try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        XCTAssertEqual(try sessions(c).first?.values().seconds,1500)
    }
    func testT2CountdownCapsAtTargetAndExplicitContinueOmitsLateGap() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,a,p,first) = try setup(c)
        try command(s,first,.discard)
        let id = UUID(); try s.start(activityID:a,participantID:p,operationID:id,target:1500,zone:zone)
        advance(3000); try command(s,id,.checkpoint)
        XCTAssertEqual(try op(s,id).timer.state,.targetReached); XCTAssertEqual(try op(s,id).timer.values.seconds,1500)
        try command(s,id,.resume); advance(60); try command(s,id,.finish)
        let result = try op(s,id).timer.values
        XCTAssertEqual(result.seconds,1560); XCTAssertEqual(result.spans.count,2)
        XCTAssertEqual(result.spans[1].start.timeIntervalSince(result.spans[0].end),1500)
        try result.validate(now:clock.wall)
    }
    func testT2EarlyEndDoesNotFillTargetAndPausedTargetDoesNotRun() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,a,p,old) = try setup(c); try command(s,old,.discard)
        let id = UUID(); try s.start(activityID:a,participantID:p,operationID:id,target:1500,zone:zone)
        advance(600); try command(s,id,.pause); advance(3600); try command(s,id,.finish)
        XCTAssertEqual(try op(s,id).timer.values.seconds,600)
    }
    func testT3FinishRemainsFrozenAcrossConfirmationDelayAndNewService() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,_,id) = try setup(c)
        advance(1200); try command(s,id,.finish); advance(600)
        let reopened = service(c), pending = try op(reopened,id)
        XCTAssertEqual(pending.timer.projected(at:clock).values.seconds,1200); XCTAssertTrue(try sessions(c).isEmpty)
        try reopened.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        XCTAssertEqual(try sessions(c).count,1)
    }
    func testT4RepeatedStartFinishSaveAndDeletedCallbacksNeverResurrect() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,a,p,id) = try setup(c)
        try s.start(activityID:a,participantID:p,operationID:id,zone:zone)
        XCTAssertThrowsError(try s.start(activityID:a,participantID:p,operationID:UUID(),zone:zone))
        advance(60); let initial = try op(s,id); try command(s,id,.finish)
        XCTAssertThrowsError(try s.command(.finish,id:id,revision:initial.revision))
        let pending = try op(s,id); try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values); XCTAssertEqual(try sessions(c).count,1)
        let session = try XCTUnwrap(sessions(c).first); try s.delete(id:id,revision:session.revision)
        XCTAssertThrowsError(try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        try s.start(activityID:a,participantID:p,operationID:id,zone:zone)
        XCTAssertTrue(try sessions(c).isEmpty); XCTAssertEqual(try op(s,id).timer.state,.deleted)
    }
    func testT4CommitBeforeAndAfterFailureHasOneRecoverableOutcome() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,_,id) = try setup(c)
        advance(60); try command(s,id,.finish); let pending = try op(s,id)
        let before = InvestmentService(context:c.mainContext,clock:{self.clock},commit:{ _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try before.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        XCTAssertTrue(try sessions(c).isEmpty); XCTAssertEqual(try op(s,id),pending)
        let after = InvestmentService(context:c.mainContext,clock:{self.clock},commit:{ try $0.save(); throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try after.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        XCTAssertEqual(try sessions(c).count,1); XCTAssertEqual(try op(s,id).timer.state,.saved)
        try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values); XCTAssertEqual(try sessions(c).count,1)
    }
    func testT5DurationCorrectionDropsIntervalsButPreservesTimerOrigin() throws {
        var v = InvestmentValues(day:"2026-10-16",timeZoneID:zone.identifier,seconds:3600,evidence:.intervals,source:.timer,
            spans:[.init(start:clock.wall.addingTimeInterval(-3600),end:clock.wall)])
        v.changeDuration(2700); try v.validate(now:clock.wall)
        XCTAssertEqual(v.evidence,.correctedDuration); XCTAssertEqual(v.source,.timer); XCTAssertTrue(v.corrected); XCTAssertTrue(v.spans.isEmpty)
        v.feeling = nil; v.note = "Synthetic note"; XCTAssertEqual(v.day,"2026-10-16")
        var invalid = v; invalid.seconds = -.infinity; XCTAssertThrowsError(try invalid.validate())
        invalid = v; invalid.seconds = 0; XCTAssertThrowsError(try invalid.validate())
        invalid = v; invalid.day = "2027-01-01"; XCTAssertThrowsError(try invalid.validate(now:clock.wall))
    }
    func testT6CrossDayPauseAllocationAndCountUseOriginalZone() throws {
        let start = ImportantCivilDay(identifier:"2026-12-31")!.instant(minutes:1430,timeZone:zone)!
        let v = InvestmentValues(day:"2026-12-31",timeZoneID:zone.identifier,seconds:1200,evidence:.intervals,source:.timer,
            spans:[.init(start:start,end:start.addingTimeInterval(300)),.init(start:start.addingTimeInterval(900),end:start.addingTimeInterval(1800))])
        let rows = try InvestmentReview.contributions(id:UUID(),activityID:UUID(),values:v)
        XCTAssertEqual(rows.map(\.day),["2026-12-31","2027-01-01"]); XCTAssertEqual(rows.map(\.seconds),[300,900]); XCTAssertEqual(InvestmentReview.count(rows),1)
        XCTAssertEqual(InvestmentReview.window(rows,days:7,today:ImportantCivilDay(identifier:"2027-01-01")!).count,2)
    }
    func testT7DSTLeapDayAndNaturalWindowUseCivilDays() throws {
        let ny = TimeZone(identifier:"America/New_York")!
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = ny
        let start = calendar.date(from:DateComponents(year:2026,month:3,day:8,hour:0))!
        let end = calendar.date(byAdding:.day,value:1,to:start)!
        let v = InvestmentValues(day:"2026-03-08",timeZoneID:ny.identifier,seconds:23*3600,evidence:.intervals,source:.manual,spans:[.init(start:start,end:end)])
        XCTAssertEqual(try InvestmentReview.contributions(id:UUID(),activityID:UUID(),values:v).map(\.seconds),[23*3600])
        let leap = ImportantCivilDay(identifier:"2024-02-29")!; XCTAssertEqual(leap.adding(days:1)?.identifier,"2024-03-01")
    }
    func testT7ClockJumpRebootAndProcessChangeRetainCheckpointForReview() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,_,id) = try setup(c)
        advance(60); try command(s,id,.checkpoint); let before = try op(s,id)
        var bad = clock; bad.wall.addTimeInterval(-3600); bad.uptime += 30
        XCTAssertEqual(before.timer.projected(at:bad).state,.recoveryRequired)
        bad = clock; bad.processID = "new-process"; bad.wall.addTimeInterval(7*86400)
        let restored = before.timer.projected(at:bad)
        XCTAssertEqual(restored.state,.recoveryRequired); XCTAssertEqual(restored.values.seconds,60); XCTAssertNil(restored.anchor)
        bad = clock; bad.uptime = 0; XCTAssertEqual(before.timer.projected(at:bad).state,.recoveryRequired)
    }
    func testT8TwoParticipantsAreIsolatedAndSameParticipantCannotDoubleStart() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,p,_) = try setup(c)
        let p2 = InvestmentParticipant(name:"Synthetic second participant"); c.mainContext.insert(p2); try c.mainContext.save()
        let a2 = try s.createActivity(name:"Synthetic activity",participantID:p2.id)
        advance(30)
        let secondID=UUID()
        try s.start(activityID:a2,participantID:p2.id,operationID:secondID,zone:zone)
        XCTAssertEqual(try s.operations().filter { $0.timer.state.unfinished }.count,2)
        let recorders=try ModelContext(c).fetch(FetchDescriptor<InvestmentOperation>()).map(\.recorderID)
        XCTAssertEqual(Set(recorders),[p])
        XCTAssertThrowsError(try s.start(activityID:a2,participantID:p,operationID:UUID(),zone:zone))
        advance(60)
        let identities=try s.operations().map { $0.id }
        for id in identities {
            try command(s,id,.finish)
            let pending=try op(s,id)
            try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        }
        let facts=try sessions(c).map(InvestmentSessionTransfer.init)
        let firstRows=try InvestmentReview.contributions(sessions:facts,participantID:p)
        let secondRows=try InvestmentReview.contributions(sessions:facts,participantID:p2.id)
        XCTAssertEqual(firstRows.reduce(0) { $0+$1.seconds },90)
        XCTAssertEqual(secondRows.reduce(0) { $0+$1.seconds },60)
        XCTAssertEqual(InvestmentReview.count(firstRows),1)
        XCTAssertEqual(InvestmentReview.count(secondRows),1)
        XCTAssertEqual(Set(firstRows.map(\.sessionID)),Set(identities.filter { $0 != secondID }))
        XCTAssertEqual(Set(secondRows.map(\.sessionID)),[secondID])
        XCTAssertTrue(try InvestmentReview.contributions(sessions:facts,participantID:UUID()).isEmpty)
        XCTAssertEqual(Set(facts.map(\.recorderID)),[p])
        let workspace=InvestmentWorkspace();workspace.refresh(c.mainContext)
        XCTAssertEqual(try workspace.contributions(),firstRows)
        let invalid=InvestmentValues(day:"2026-10-16",timeZoneID:zone.identifier,seconds:45,evidence:.dateDuration,source:.manual)
        XCTAssertThrowsError(try s.saveManual(id:UUID(),participantID:p,activityID:a2,values:invalid,confirmDuplicate:true)) {
            XCTAssertEqual($0 as? InvestmentFailure,.missing)
        }
    }
    func testT9NilFeedbackArchiveLongTermAndSameSnapshotEdits() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,a,p,old) = try setup(c); try command(s,old,.discard)
        let id = UUID(); var v = InvestmentValues(day:"2020-01-01",timeZoneID:zone.identifier,seconds:2700,evidence:.dateDuration,source:.manual)
        try s.saveManual(id:id,participantID:p,activityID:a,values:v)
        var model = try XCTUnwrap(sessions(c).first); XCTAssertNil(try model.values().feeling)
        v.feeling = 5; try s.saveManual(id:id,participantID:p,activityID:a,values:v,expectedRevision:model.revision)
        try s.updateActivity(id:a,name:"Renamed",archived:true)
        model = try XCTUnwrap(sessions(c).first); XCTAssertEqual(try model.values().feeling,5)
        let rows = try InvestmentReview.contributions(id:id,activityID:a,values:model.values())
        XCTAssertEqual(InvestmentReview.window(rows,days:nil,today:ImportantCivilDay(clock.wall,timeZone:zone)).count,1)
        XCTAssertTrue(InvestmentReview.window(rows,days:30,today:ImportantCivilDay(clock.wall,timeZone:zone)).isEmpty)
        XCTAssertThrowsError(try s.start(activityID:a,participantID:p,operationID:UUID(),zone:zone))
        try s.delete(id:id,revision:model.revision); XCTAssertTrue(try sessions(c).isEmpty)
    }
    func testT10TimerTransactionsNeitherSaveNorRollbackForeignDraft() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,_,id) = try setup(c)
        let unsaved = Entry(body:"Unsaved foreign synthetic draft",createdAt:clock.wall); c.mainContext.autosaveEnabled = false; c.mainContext.insert(unsaved)
        advance(60); try command(s,id,.finish); let pending = try op(s,id)
        let fail = InvestmentService(context:c.mainContext,clock:{self.clock},commit:{ _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try fail.saveTimer(id:id,revision:pending.revision,values:pending.timer.values))
        XCTAssertEqual(unsaved.body,"Unsaved foreign synthetic draft"); XCTAssertTrue(c.mainContext.hasChanges)
        try s.saveTimer(id:id,revision:pending.revision,values:pending.timer.values)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<Entry>()),0); XCTAssertTrue(c.mainContext.hasChanges)
    }
    func testT11BrowsingDoesNotCreateParticipantAndActualCreationIsIdempotent() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), s = service(c)
        _ = try s.operations(); XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<InvestmentParticipant>()),0)
        let id = UUID(); try s.createActivity(name:"Synthetic",id:id); try s.createActivity(name:"Synthetic",id:id)
        try s.createActivity(name:"Other")
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<InvestmentParticipant>()),1)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<InvestmentActivity>()),2)
    }
    func testReviewerR1MovingSessionToAnotherActivityKeepsOperationIdentityConsistent() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,a,p,old) = try setup(c); try command(s,old,.discard)
        let id = UUID(), values = InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:600,evidence:.dateDuration,source:.manual)
        try s.saveManual(id:id,participantID:p,activityID:a,values:values)
        let other = try s.createActivity(name:"Other synthetic activity")
        let session = try XCTUnwrap(sessions(c).first)
        try s.saveManual(id:id,participantID:p,activityID:other,values:values,expectedRevision:session.revision,confirmDuplicate:true)
        XCTAssertEqual(try op(s,id).activityID,other)
        try InvestmentIntegrity.validate(context:ModelContext(c))
    }

    func testReviewerR2ClockDriftHasConsistentSpansOrRequiresReview() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), (s,_,_,id) = try setup(c)
        clock.wall.addTimeInterval(60.000001); clock.uptime += 60
        try command(s,id,.checkpoint); advance(60); try command(s,id,.finish)
        let values = try op(s,id).timer.values; try values.validate(now:clock.wall)
        XCTAssertEqual(values.spans[0].end,values.spans[1].start)
        let c2 = try PersistenceContainerFactory.makeInMemory(), (s2,_,_,id2) = try setup(c2)
        clock.wall.addTimeInterval(59); clock.uptime += 60; try command(s2,id2,.checkpoint)
        XCTAssertEqual(try op(s2,id2).timer.state,.recoveryRequired)
        XCTAssertEqual(try op(s2,id2).timer.values.seconds,0)
    }

    func testReviewerR3RestoredTargetReachedExplicitContinueRecordsNewSegment() throws {
        let source = try PersistenceContainerFactory.makeInMemory(), (s,a,p,old) = try setup(source); try command(s,old,.discard)
        let id=UUID();try s.start(activityID:a,participantID:p,operationID:id,target:1500,zone:zone)
        advance(1500);try command(s,id,.checkpoint)
        let read=ModelContext(source), transfer=try InvestmentOperationTransfer(XCTUnwrap(read.fetch(FetchDescriptor<InvestmentOperation>()).first { $0.id == id }))
        let target=try PersistenceContainerFactory.makeInMemory()
        for participant in try read.fetch(FetchDescriptor<InvestmentParticipant>()) {target.mainContext.insert(InvestmentParticipantTransfer(participant).model())}
        for activity in try read.fetch(FetchDescriptor<InvestmentActivity>()) {target.mainContext.insert(InvestmentActivityTransfer(activity).model())}
        target.mainContext.insert(try transfer.model(restoring:true));try target.mainContext.save()
        advance(7*86400);let resumed=service(target);try command(resumed,id,.resume);advance(60);try command(resumed,id,.finish)
        XCTAssertEqual(try op(resumed,id).timer.values.seconds,1560)
        XCTAssertEqual(try op(s,id).timer.values.seconds,1500)
    }
    func testReviewerR4FirstEffectiveSpanAfterZeroSecondPauseUsesActualDay() throws {
        let c=try PersistenceContainerFactory.makeInMemory()
        clock.wall=ImportantCivilDay(identifier:"2026-10-15")!.instant(minutes:1439,timeZone:zone)!
        let (s,_,_,id)=try setup(c);try command(s,id,.pause);advance(120);try command(s,id,.resume);advance(0.125);try command(s,id,.finish)
        let values=try op(s,id).timer.values
        XCTAssertEqual(values.day,"2026-10-16");XCTAssertEqual(values.seconds,0.125);try values.validate(now:clock.wall)
    }
    func testManualDraftPersistsRawInputFailureKeepsOldDraftAndCancelCreatesNoFact() throws {
        let c=try PersistenceContainerFactory.makeInMemory(),(s,a,p,old)=try setup(c);try command(s,old,.discard)
        let id=UUID();var values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:2700,evidence:.dateDuration,source:.manual)
        let revision=try s.storeDraft(id:id,participantID:p,activityID:a,values:values,durationText:"45")
        values.note="Synthetic failed draft update"
        let failing=InvestmentService(context:c.mainContext,clock:{self.clock},commit:{_ in throw CocoaError(.fileWriteOutOfSpace)})
        XCTAssertThrowsError(try failing.storeDraft(id:id,participantID:p,activityID:a,values:values,durationText:"-",expectedRevision:revision))
        XCTAssertEqual(try op(s,id).timer.values.note,"");XCTAssertEqual(values.note,"Synthetic failed draft update")
        let updated=try s.storeDraft(id:id,participantID:p,activityID:a,values:values,durationText:"-",expectedRevision:revision)
        XCTAssertEqual(try op(s,id).timer.durationText,"-")
        try s.command(.discard,id:id,revision:updated);XCTAssertTrue(try sessions(c).isEmpty)
    }
    func testManualAfterCommitRetryAndNoOpDoNotDuplicateOrMoveFactTime() throws {
        let c=try PersistenceContainerFactory.makeInMemory(),(s,a,p,old)=try setup(c);try command(s,old,.discard)
        let id=UUID(),values=InvestmentValues(day:"2026-10-15",timeZoneID:zone.identifier,seconds:2700,evidence:.dateDuration,source:.manual)
        let failing=InvestmentService(context:c.mainContext,clock:{self.clock},commit:{try $0.save();throw CocoaError(.fileWriteUnknown)})
        XCTAssertThrowsError(try failing.saveManual(id:id,participantID:p,activityID:a,values:values))
        let original=try XCTUnwrap(sessions(c).first);let stamp=original.updatedAt
        advance(600);try s.saveManual(id:id,participantID:p,activityID:a,values:values)
        let saved=try XCTUnwrap(sessions(c).first);XCTAssertEqual(saved.updatedAt,stamp);XCTAssertEqual(saved.revision,0);XCTAssertEqual(try sessions(c).count,1)
    }

    func testClockRollbackNoteEditRetainsKnownOccurrenceAndMonotonicTechnicalTime() throws {
        let c=try PersistenceContainerFactory.makeInMemory(),(s,a,p,old)=try setup(c);try command(s,old,.discard)
        let id=UUID();var v=InvestmentValues(day:ImportantCivilDay(clock.wall,timeZone:zone).identifier,timeZoneID:zone.identifier,seconds:45,evidence:.dateDuration,source:.manual)
        try s.saveManual(id:id,participantID:p,activityID:a,values:v)
        let before=try XCTUnwrap(sessions(c).first);let timestamp=before.updatedAt
        clock.wall.addTimeInterval(-86400);v.note="Synthetic note after clock rollback"
        try s.saveManual(id:id,participantID:p,activityID:a,values:v,expectedRevision:before.revision)
        let saved=try XCTUnwrap(sessions(c).first)
        XCTAssertEqual(try saved.values().day,v.day);XCTAssertEqual(saved.updatedAt,timestamp)
        XCTAssertEqual(try saved.values().note,v.note)
        v.seconds += 60
        XCTAssertThrowsError(try s.saveManual(id:id,participantID:p,activityID:a,values:v,expectedRevision:saved.revision))
    }

    func testRevisionAdvancesWithoutOverflowAndNeverProducesInvalidRevision() throws {
        for value in [Int.min,-1,Int.max] {
            XCTAssertFalse(InvestmentRevision.isValid(value))
            XCTAssertThrowsError(try InvestmentRevision.next(value))
        }
        XCTAssertEqual(try InvestmentRevision.next(0),1)
        XCTAssertEqual(try InvestmentRevision.next(Int.max-2),Int.max-1)
        XCTAssertTrue(InvestmentRevision.isValid(Int.max-1))
        XCTAssertThrowsError(try InvestmentRevision.next(Int.max-1))
    }
    func testReviewerR7FutureFormalFactRejectsUsingTechnicalObservationButRetainsClockRollback() throws {
        let c=try PersistenceContainerFactory.makeInMemory(),(s,a,p,old)=try setup(c);try command(s,old,.discard)
        let id=UUID(),v=InvestmentValues(day:ImportantCivilDay(clock.wall,timeZone:zone).identifier,timeZoneID:zone.identifier,seconds:45,evidence:.dateDuration,source:.manual)
        try s.saveManual(id:id,participantID:p,activityID:a,values:v)
        let read=ModelContext(c)
        let participants=try read.fetch(FetchDescriptor<InvestmentParticipant>()).map(InvestmentParticipantTransfer.init)
        let activities=try read.fetch(FetchDescriptor<InvestmentActivity>()).map(InvestmentActivityTransfer.init)
        let sessions=try read.fetch(FetchDescriptor<InvestmentSession>()).map(InvestmentSessionTransfer.init)
        let operations=try read.fetch(FetchDescriptor<InvestmentOperation>()).map {try InvestmentOperationTransfer($0)}
        func data(_ sessions:[InvestmentSessionTransfer],_ operations:[InvestmentOperationTransfer]) -> TransferData {
            .init(entries:[],images:[],tags:[],links:[],habits:[],habitLogs:[],goals:[],goalEvents:[],investmentParticipants:participants,investmentActivities:activities,investmentSessions:sessions,investmentOperations:operations)
        }
        clock.wall.addTimeInterval(-86400)
        XCTAssertNoThrow(try data(sessions,operations).validateInvestment(packageVersion:10))
        var forged=sessions,changedOps=operations;forged[0].values.day="2099-12-31"
        let index=try XCTUnwrap(changedOps.firstIndex {$0.id == id});changedOps[index].timer.values=forged[0].values
        XCTAssertThrowsError(try data(forged,changedOps).validateInvestment(packageVersion:10))
    }

    func testReviewDAdjacentEvaluationDaysExpireWindowMembersWithoutChangingFacts() throws {
        let participant=UUID(),activity=UUID(),before=ImportantCivilDay(identifier:"2026-10-17")!,after=ImportantCivilDay(identifier:"2026-10-18")!
        for (days,start) in [(7,"2026-10-11"),(30,"2026-09-18")] {
            let id=UUID(),date=ImportantCivilDay(identifier:start)!.instant(minutes:720,timeZone:zone)!
            let values=InvestmentValues(day:start,timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual,spans:[])
            let fact=try InvestmentSessionTransfer(InvestmentSession(id:id,participantID:participant,activityID:activity,values:values,now:date))
            let snapshot=try InvestmentReviewSnapshot(sessions:[fact],participantID:participant)
            let previous=snapshot.selection(days:days,today:before,activityID:nil,day:nil)
            let next=snapshot.selection(days:days,today:after,activityID:nil,day:nil)
            XCTAssertEqual(previous.count,1);XCTAssertEqual(previous.seconds,60);XCTAssertEqual(previous.pageIDs(offset:0),[id])
            XCTAssertEqual(next.count,0);XCTAssertEqual(next.seconds,0);XCTAssertEqual(next.pageIDs(offset:0),[])
            XCTAssertEqual(snapshot.selection(days:nil,today:after,activityID:nil,day:nil).pageIDs(offset:0),[id])
            XCTAssertEqual(snapshot.selection(days:days,today:before,activityID:nil,day:nil).pageIDs(offset:0),[id],"The immutable fact snapshot itself did not change")
        }
    }

    func testUsageReviewSnapshotKeepsCrossDayIdentityAndRejectsInvalidFacts() throws {
        let p=UUID(),a=UUID(),foreign=UUID()
        let start=ImportantCivilDay(identifier:"2026-12-31")!.instant(minutes:1430,timeZone:zone)!
        let values=InvestmentValues(day:"2026-12-31",timeZoneID:zone.identifier,seconds:1200,evidence:.intervals,source:.timer,
            spans:[.init(start:start,end:start.addingTimeInterval(300)),.init(start:start.addingTimeInterval(900),end:start.addingTimeInterval(1800))])
        let fact=try InvestmentSessionTransfer(InvestmentSession(id:UUID(),participantID:p,activityID:a,values:values,now:start))
        var other=fact;other.id=UUID();other.participantID=foreign
        let snapshot=try InvestmentReviewSnapshot(sessions:[fact,other],participantID:p)
        XCTAssertEqual(snapshot.activitySeconds[a],1200)
        let today=ImportantCivilDay(identifier:"2027-01-01")!
        let all=snapshot.selection(days:nil,today:today,activityID:nil,day:nil)
        XCTAssertEqual(all.seconds,1200);XCTAssertEqual(all.count,1)
        XCTAssertEqual(all.daySeconds,["2026-12-31":300,"2027-01-01":900])
        XCTAssertEqual(snapshot.selection(days:7,today:today,activityID:a,day:nil).count,1)
        for (day,seconds) in [("2026-12-31",300.0),("2027-01-01",900.0)] {
            let chosen=snapshot.selection(days:nil,today:today,activityID:a,day:day)
            XCTAssertEqual(chosen.seconds,seconds);XCTAssertEqual(chosen.pageIDs(offset:0),[fact.id])
        }
        XCTAssertEqual(snapshot.selection(days:nil,today:today,activityID:a,day:"2020-01-01").count,0)
        var invalid=fact;invalid.values.seconds = .nan
        XCTAssertThrowsError(try InvestmentReviewSnapshot(sessions:[invalid],participantID:p))
        // A foreign participant's unreadable facts do not change this participant's review.
        invalid.participantID=foreign
        XCTAssertNoThrow(try InvestmentReviewSnapshot(sessions:[fact,invalid],participantID:p))
    }

}

// Synthetic clock observations are independent. This is not a hardware sleep test.
struct InvestmentClockTestReadings {
    var wall=Date(timeIntervalSince1970:1792113600)
    var continuousElapsed=1000.0
    var awakeUptime=200.0
    var processID="continuous-v1:synthetic-process"
    func sample() -> InvestmentClock {
        InvestmentClock.sample(wall:wall,continuousElapsed:continuousElapsed,awakeUptime:awakeUptime,processID:processID)
    }
    mutating func advance(wall:Double,continuous:Double,awake:Double) {
        self.wall.addTimeInterval(wall);continuousElapsed += continuous;awakeUptime += awake
    }
}


extension InvestmentFoundationTests {
    func testReviewFixUX1OutsideDateUsesAllTimeAndKeepsActivityAndExactDayContribution() throws {
        let today=ImportantCivilDay(identifier:"2026-10-18")!,chosen=ImportantCivilDay(identifier:"2026-09-01")!,activity=UUID(),other=UUID()
        let rows=[InvestmentContribution(sessionID:UUID(),activityID:activity,day:chosen.identifier,seconds:2700),InvestmentContribution(sessionID:UUID(),activityID:activity,day:today.identifier,seconds:900),InvestmentContribution(sessionID:UUID(),activityID:other,day:chosen.identifier,seconds:600)]
        let snapshot=InvestmentReviewSnapshot(contributions:rows,orderedSessionIDs:rows.map(\.sessionID))
        for period in [7,30] {
            let days=InvestmentReview.periodForInspection(days:period,day:chosen,today:today)
            XCTAssertEqual(days,0)
            let selection=snapshot.selection(days:days == 0 ? nil:days,today:today,activityID:activity,day:chosen.identifier)
            XCTAssertEqual(selection.seconds,2700);XCTAssertEqual(selection.count,1)
            XCTAssertEqual(snapshot.selection(days:nil,today:today,activityID:activity,day:"2026-09-02").count,0)
            XCTAssertEqual(InvestmentReview.periodForInspection(days:period,day:today,today:today),period)
            XCTAssertEqual(snapshot.selection(days:nil,today:today,activityID:activity,day:nil).seconds,3600)
        }
    }
}
