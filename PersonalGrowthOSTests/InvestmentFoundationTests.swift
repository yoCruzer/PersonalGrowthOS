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
        try s.start(activityID:a2,participantID:p2.id,operationID:UUID(),zone:zone)
        XCTAssertEqual(try s.operations().filter { $0.timer.state.unfinished }.count,2)
        XCTAssertThrowsError(try s.start(activityID:a2,participantID:p,operationID:UUID(),zone:zone))
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
}
