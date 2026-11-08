import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class SyncDomainInstallerTests: XCTestCase {
    private let instant=Date(timeIntervalSince1970:1_700_000_000)
    private func container() throws -> ModelContainer {
        let c=try PersistenceContainerFactory.makeInMemory();c.mainContext.autosaveEnabled=false;return c
    }
    private func projection(_ context:ModelContext) throws -> SyncDomainProjection {
        try SyncDomainCodec.reconstruct(completeDocuments:SyncDomainCodec.capture(context:context))
    }
    private func key(_ kind:SyncDomainKind,_ id:UUID)->SyncDomainKey {.init(kind:kind,id:id)}
    private func entry(_ id:UUID=UUID(),body:String="Synthetic") -> Entry {Entry(id:id,body:body,createdAt:instant)}

    func testAffectedEntryUpdatesInPlaceDoesNotSaveAndRollbackRestoresOriginal() throws {
        let target=try container(),source=try container(),id=UUID(),untouchedID=UUID()
        let old=entry(id,body:"before"),untouched=entry(untouchedID,body:"local only")
        target.mainContext.insert(old);target.mainContext.insert(untouched);try target.mainContext.save()
        source.mainContext.insert(entry(id,body:"after"));source.mainContext.insert(entry(untouchedID,body:"remote unselected"))
        let p=try projection(source.mainContext)
        try SyncDomainInstaller.install(p,affectedKeys:[key(.entry,id)],in:target.mainContext)
        let current=try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Entry>()).first{$0.id==id})
        XCTAssertTrue(current === old);XCTAssertEqual(old.body,"after");XCTAssertEqual(untouched.body,"local only")
        XCTAssertTrue(target.mainContext.hasChanges)
        XCTAssertEqual(try ModelContext(target).fetch(FetchDescriptor<Entry>()).first{$0.id==id}?.body,"before")
        target.mainContext.rollback();XCTAssertEqual(old.body,"before")
    }

    func testEntryImagesRetainInstancesAndDeleteOnlySelectedAggregateChildren() throws {
        let target=try container(),source=try container(),id=UUID(),otherID=UUID(),imageID=UUID()
        let old=entry(id),other=entry(otherID),remote=entry(id,body:"remote")
        let image=ImageMetadata(id:imageID,relativePath:"Media/Originals/a.png",originalFilename:"synthetic.png",contentType:"image/png",byteCount:1,checksum:String(repeating:"a",count:64),createdAt:instant)
        image.entry=old;target.mainContext.insert(old);target.mainContext.insert(image);target.mainContext.insert(other);try target.mainContext.save()
        source.mainContext.insert(remote)
        try SyncDomainInstaller.install(try projection(source.mainContext),affectedKeys:[key(.entry,id)],in:target.mainContext)
        try target.mainContext.save()
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<ImageMetadata>()),0)
        XCTAssertTrue(try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Entry>()).first{$0.id==id}) === old)
        XCTAssertEqual(other.body,"Synthetic")
        let emptyContainer=try container()
        let empty=try projection(emptyContainer.mainContext)
        try SyncDomainInstaller.install(empty,affectedKeys:[key(.entry,id)],in:target.mainContext);try target.mainContext.save()
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id),[otherID])
    }

    func testSupplementPreservesOriginalConfigurationAndDayMetadataUUIDs() throws {
        let source=try container(),target=try container(),habitID=UUID(),logID=UUID(),configurationID=UUID(),metadataID=UUID()
        source.mainContext.insert(Habit(id:habitID,name:"Walk",normalizedName:"walk",createdAt:instant))
        source.mainContext.insert(HabitConfiguration(id:configurationID,habitID:habitID,recordingMode:.multiplePerDay,updatedAt:instant))
        source.mainContext.insert(HabitLog(id:logID,habitID:habitID,occurredAt:instant,isCompleted:true,createdAt:instant))
        source.mainContext.insert(HabitLogDayMetadata(id:metadataID,habitLogID:logID,localDayIdentifier:"2023-11-14",localTimeZoneIdentifier:"UTC",provenance:.legacyBootstrap))
        try SyncDomainInstaller.install(try projection(source.mainContext),affectedKeys:[key(.habit,habitID),key(.habitLog,logID)],in:target.mainContext)
        try target.mainContext.save()
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<HabitConfiguration>()).map(\.id),[configurationID])
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>()).map(\.id),[metadataID])
        XCTAssertEqual(try SyncDomainCodec.capture(context:source.mainContext),try SyncDomainCodec.capture(context:target.mainContext))
    }

    func testCrossAggregateChildIdentityCollisionRejectsBeforeAnyWrite() throws {
        let target=try container(),source=try container(),a=UUID(),b=UUID(),pinID=UUID()
        let first=entry(a,body:"before"),second=entry(b)
        target.mainContext.insert(first);target.mainContext.insert(second)
        target.mainContext.insert(EntryPin(id:pinID,entryID:a,pinnedAt:instant));try target.mainContext.save()
        source.mainContext.insert(entry(a));source.mainContext.insert(entry(b,body:"must not apply"))
        source.mainContext.insert(EntryPin(id:pinID,entryID:b,pinnedAt:instant))
        XCTAssertThrowsError(try SyncDomainInstaller.install(projection(source.mainContext),affectedKeys:[key(.entry,b)],in:target.mainContext)) {
            XCTAssertEqual($0 as? SyncDomainInstallError,.scopeViolation)
        }
        XCTAssertFalse(target.mainContext.hasChanges);XCTAssertEqual(second.body,"Synthetic")
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<EntryPin>()).first?.entryID,a)
        XCTAssertThrowsError(try SyncDomainInstaller.install(projection(source.mainContext),affectedKeys:[key(.entry,a)],in:target.mainContext)) {
            XCTAssertEqual($0 as? SyncDomainInstallError,.scopeViolation)
        }
        XCTAssertFalse(target.mainContext.hasChanges)
        try SyncDomainInstaller.install(try projection(source.mainContext),affectedKeys:[key(.entry,a),key(.entry,b)],in:target.mainContext)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<EntryPin>()).first?.entryID,b)
    }

    func testUniqueNaturalKeyCannotUpsertAnUnselectedUUID() throws {
        let target=try container(),source=try container(),originalID=UUID(),incomingID=UUID()
        let original=Tag(id:originalID,displayName:"Same",normalizedName:"same",createdAt:instant)
        target.mainContext.insert(original);try target.mainContext.save()
        source.mainContext.insert(Tag(id:incomingID,displayName:"Same",normalizedName:"same",createdAt:instant))
        XCTAssertThrowsError(try SyncDomainInstaller.install(projection(source.mainContext),affectedKeys:[key(.tag,incomingID)],in:target.mainContext)) {
            XCTAssertEqual($0 as? SyncDomainInstallError,.uniqueConstraint)
        }
        XCTAssertFalse(target.mainContext.hasChanges)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<Tag>()).map(\.id),[originalID])
    }

    func testDesktopAuthorizationAndDeviceReminderJournalStayLocal() throws {
        let target=try container(),source=try container(),id=UUID(),newID=UUID()
        var preferences=ImportantDayPreferences();preferences.desktopVisible=true
        let local=try ImportantDay(id:id,title:"Local",rule:.init(),preferences:preferences,createdAt:instant)
        let journal=TodoReminderDeviceRecord(taskID:UUID(),intentGeneration:UUID(),channel:.notification,fireAt:instant,phase:.accepted)
        target.mainContext.insert(local);target.mainContext.insert(journal);try target.mainContext.save()
        source.mainContext.insert(try ImportantDay(id:id,title:"Remote",rule:.init(),createdAt:instant))
        source.mainContext.insert(try ImportantDay(id:newID,title:"New remote",rule:.init(),preferences:preferences,createdAt:instant))
        try SyncDomainInstaller.install(try projection(source.mainContext),affectedKeys:[key(.importantDay,id),key(.importantDay,newID)],in:target.mainContext)
        try target.mainContext.save()
        XCTAssertTrue(try local.preferences().desktopVisible);XCTAssertEqual(local.title,"Remote")
        let added=try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<ImportantDay>()).first{$0.id==newID})
        XCTAssertFalse(try added.preferences().desktopVisible)
        XCTAssertTrue(try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first) === journal)
        XCTAssertEqual(journal.phaseRawValue,TodoReminderDevicePhase.accepted.rawValue)
    }

    func testUnchangedLocalTimerRetainsAnchorButChangedRemoteTimerRequiresRecovery() throws {
        let target=try container(),source=try container(),participant=InvestmentParticipant(name:"Synthetic",isDefault:true)
        let activity=InvestmentActivity(participantID:participant.id,name:"Study")
        var timer=InvestmentTimer(state:.paused,values:.init(day:"2023-11-14",timeZoneID:"UTC",seconds:0,evidence:.intervals,source:.timer),target:nil,checkpointAt:instant)
        try timer.resume(at:.init(wall:instant,uptime:10,processID:"synthetic-process"))
        let op=try InvestmentOperation(id:UUID(),participantID:participant.id,activityID:activity.id,timer:timer,now:instant,recorderID:participant.id)
        target.mainContext.insert(participant);target.mainContext.insert(activity);target.mainContext.insert(op);try target.mainContext.save()
        let bytes=op.payload,p=try projection(target.mainContext)
        try SyncDomainInstaller.install(p,affectedKeys:[key(.investmentRecord,op.id)],in:target.mainContext)
        XCTAssertEqual(op.payload,bytes);XCTAssertEqual(try op.timer().state,.running)
        let docs=try SyncDomainCodec.capture(context:target.mainContext)
        try SyncDomainInstaller.install(p,affectedKeys:Set(docs.map(\.key)),in:source.mainContext);try source.mainContext.save()
        let remote=try XCTUnwrap(source.mainContext.fetch(FetchDescriptor<InvestmentOperation>()).first)
        var next=try remote.timer();next.values.note="remote edit";remote.payload=try JSONEncoder().encode(next);remote.revision += 1
        try SyncDomainInstaller.install(try projection(source.mainContext),affectedKeys:[key(.investmentRecord,op.id)],in:target.mainContext)
        XCTAssertEqual(try op.timer().state,.recoveryRequired);XCTAssertNil(try op.timer().anchor)
        XCTAssertNil(try op.timer().processID);XCTAssertEqual(try op.timer().values.note,"remote edit")
    }
    func testAllThirtyEightSyncEntitiesRoundTripThroughFreshContext() throws {
        let source=try SyncDomainTestFixture.make(),target=try container()
        let documents=try SyncDomainCodec.capture(context:source.mainContext)
        let decoded=try SyncDomainCodec.reconstruct(completeDocuments:documents)
        try SyncDomainInstaller.install(decoded,affectedKeys:Set(documents.map(\.key)),in:target.mainContext)
        XCTAssertTrue(target.mainContext.hasChanges)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<Entry>()),0)
        try target.mainContext.save()
        let reopened=ModelContext(target);reopened.autosaveEnabled=false
        XCTAssertEqual(try SyncDomainCodec.capture(context:reopened),documents)
        let actual=try SyncDomainSupplement.capture(context:reopened)
        XCTAssertEqual(actual.habitConfigurations.sorted{$0.id.uuidString<$1.id.uuidString},decoded.supplement.habitConfigurations)
        XCTAssertEqual(actual.habitLogMetadata.sorted{$0.id.uuidString<$1.id.uuidString},decoded.supplement.habitLogMetadata)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<TodoReminderDeviceRecord>()),0)
    }

}
