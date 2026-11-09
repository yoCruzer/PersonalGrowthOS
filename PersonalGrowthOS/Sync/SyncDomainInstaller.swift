import Foundation
import SwiftData

enum SyncDomainInstallError: Error, Equatable {
    case duplicateIdentity, scopeViolation, missingOwner, uniqueConstraint
}

/// Applies validated business aggregates in the caller's existing transaction.
/// No save, rollback, lock, filesystem operation, permission prompt, or publication side effect.
/// Caller owns rollback on any failure and saves business rows together with inbox/head metadata.
enum SyncDomainInstaller {
    private static func enumValue<T:RawRepresentable>(_ type:T.Type,_ raw:T.RawValue?) throws -> T {
        guard let raw,let value=T(rawValue:raw) else {throw SyncDomainCodecError.malformed};return value
    }
    private static func key(_ kind:SyncDomainKind,_ id:UUID)->SyncDomainKey { .init(kind:kind,id:id) }
    private static func taskKey(_ id:UUID,_ series:UUID?)->SyncDomainKey {
        series.map { key(.todoSeries,$0) } ?? key(.todoTask,id)
    }
    static func install(_ projection:SyncDomainProjection, affectedKeys:Set<SyncDomainKey>, in context:ModelContext) throws {
        guard !affectedKeys.isEmpty else {return}
        // Do not accept a forged projection or rely on callers invoking reconstruct first.
        _ = try SyncDomainCodec.documents(from:projection.transfer,supplement:projection.supplement)
        let d=projection.transfer, supplement=projection.supplement
        let oldTasks=try context.fetch(FetchDescriptor<TodoTask>())
        var oldTaskOwners:[UUID:SyncDomainKey]=[:], newTaskOwners:[UUID:SyncDomainKey]=[:]
        for t in oldTasks {guard oldTaskOwners.updateValue(taskKey(t.id,t.seriesID),forKey:t.id)==nil else {throw SyncDomainInstallError.duplicateIdentity}}
        for t in d.todoTasks {guard newTaskOwners.updateValue(taskKey(t.id,t.seriesID),forKey:t.id)==nil else {throw SyncDomainInstallError.duplicateIdentity}}
        func require(_ owner:SyncDomainKey?) throws -> SyncDomainKey {guard let owner else {throw SyncDomainInstallError.missingOwner};return owner}
        let imageOwners=Dictionary(uniqueKeysWithValues:d.images.map{($0.id,key(.entry,$0.entryID))})
        var updates:[() throws -> Void]=[], removals:[() -> Void]=[]
        let installedEntries = try prepare(d.entries.map { r in Entry(id:r.id, kind:try enumValue(EntryKind.self,r.kind), status:try enumValue(EntryStatus.self,r.status), title:r.title, body:r.body, createdAt:r.createdAt, occurredAt:r.occurredAt, updatedAt:r.updatedAt, periodStart:r.periodStart, periodEnd:r.periodEnd) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.entry,$0.id) }, newOwner:{ key(.entry,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        let installedImages = try prepare(d.images.map { r in ImageMetadata(id:r.id, relativePath:r.relativePath, originalFilename:r.originalFilename, contentType:r.contentType, byteCount:r.byteCount, pixelWidth:r.pixelWidth, pixelHeight:r.pixelHeight, checksum:r.checksum, sortOrder:r.sortOrder, createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ try require($0.entry.map{key(.entry,$0.id)}) }, newOwner:{ try require(imageOwners[$0.id]) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.tags.map { r in Tag(id:r.id, displayName:r.displayName, normalizedName:r.normalizedName, createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.tag,$0.id) }, newOwner:{ key(.tag,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.links.map { r in ObjectLink(id:r.id, sourceType:try enumValue(LinkObjectType.self,r.sourceType), sourceID:r.sourceID, targetType:try enumValue(LinkObjectType.self,r.targetType), targetID:r.targetID, kind:try enumValue(ObjectLinkKind.self,r.kind), createdAt:r.createdAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.objectLink,$0.id) }, newOwner:{ key(.objectLink,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.habits.map { r in Habit(id:r.id, name:r.name, normalizedName:r.normalizedName, status:try enumValue(HabitStatus.self,r.status), createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habit,$0.id) }, newOwner:{ key(.habit,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.habitLogs.map { r in HabitLog(id:r.id, habitID:r.habitID, occurredAt:r.occurredAt, isCompleted:r.isCompleted, quantity:r.quantity, unit:r.unit, result:r.result, linkedEntryID:r.linkedEntryID, createdAt:r.createdAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habitLog,$0.id) }, newOwner:{ key(.habitLog,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(supplement.habitConfigurations.map { r in HabitConfiguration(id:r.id, habitID:r.habitID, recordingMode:try enumValue(HabitRecordingMode.self,r.recordingModeRawValue), dailyTargetCount:r.dailyTargetCount, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habit,$0.habitID) }, newOwner:{ key(.habit,$0.habitID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(supplement.habitLogMetadata.map { r in HabitLogDayMetadata(id:r.id, habitLogID:r.habitLogID, localDayIdentifier:r.localDayIdentifier, localTimeZoneIdentifier:r.localTimeZoneIdentifier, provenance:try enumValue(HabitLogDayProvenance.self,r.provenanceRawValue)) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habitLog,$0.habitLogID) }, newOwner:{ key(.habitLog,$0.habitLogID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.habitPlanRevisions.map { r in HabitPlanRevision(id:r.id, habitID:r.habitID, effectiveLocalDay:r.effectiveLocalDay, plan:HabitPlan(recordingMode:try enumValue(HabitRecordingMode.self,r.recordingMode), period:try enumValue(HabitPlanPeriod.self,r.period), goal:try enumValue(HabitPlanGoal.self,r.goal), targetCount:r.targetCount, weekdays:Set(r.weekdays.split(separator:",").compactMap{Int($0)})), trustCoverageStartLocalDay:r.trustCoverageStartLocalDay, createdAt:r.createdAt, origin:r.origin.flatMap(HabitPlanRevisionOrigin.init(rawValue:)) ?? .user) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habit,$0.habitID) }, newOwner:{ key(.habit,$0.habitID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.habitLifecycleEvents.map { r in HabitLifecycleEvent(id:r.id, habitID:r.habitID, kind:try enumValue(HabitLifecycleEventKind.self,r.kind), occurredLocalDay:r.occurredLocalDay, occurredAt:r.occurredAt, createdAt:r.createdAt, knownStatus:r.knownStatus.flatMap(HabitStatus.init(rawValue:))) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.habit,$0.habitID) }, newOwner:{ key(.habit,$0.habitID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.goals.map { r in Goal(id:r.id, kind:try enumValue(GoalKind.self,r.kind), title:r.title, normalizedTitle:r.normalizedTitle, status:try enumValue(GoalStatus.self,r.status), createdAt:r.createdAt, updatedAt:r.updatedAt, completedAt:r.completedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.goal,$0.id) }, newOwner:{ key(.goal,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.goalEvents.map { r in GoalLifecycleEvent(id:r.id, goalID:r.goalID, kind:try enumValue(GoalLifecycleEventKind.self,r.kind), occurredAt:r.occurredAt, createdAt:r.createdAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.goal,$0.goalID) }, newOwner:{ key(.goal,$0.goalID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.weightRecords.map { r in WeightRecord(id:r.id, weightKilograms:r.weightKilograms, recordedAt:r.recordedAt, createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.weight,$0.id) }, newOwner:{ key(.weight,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.weeklyReviews.map { r in WeeklyReview(id:r.id, weekIdentifier:r.weekIdentifier, periodStart:r.periodStart, periodEnd:r.periodEnd, rememberedText:r.rememberedText, improvementText:r.improvementText, nextStepText:r.nextStepText, focusText:r.focusText, isCompleted:r.isCompleted, createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.weeklyReview,$0.id) }, newOwner:{ key(.weeklyReview,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.entrySources.map { r in try EntryExternalSource(entryID:r.entryID, source:r.source) }, in:context, affected:affectedKeys,
            id: \.entryID, oldOwner:{ key(.entry,$0.entryID) }, newOwner:{ key(.entry,$0.entryID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.entryPins.map { r in EntryPin(id:r.id, entryID:r.entryID, pinnedAt:r.pinnedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.entry,$0.entryID) }, newOwner:{ key(.entry,$0.entryID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.entryFollowUps.map { r in EntryFollowUp(id:r.id, entryID:r.entryID, body:r.body, createdAt:r.createdAt, updatedAt:r.updatedAt) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.entry,$0.entryID) }, newOwner:{ key(.entry,$0.entryID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoTasks.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ taskKey($0.id,$0.seriesID) }, newOwner:{ taskKey($0.id,$0.seriesID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoEvents.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ try require(oldTaskOwners[$0.taskID]) }, newOwner:{ try require(newTaskOwners[$0.taskID]) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoLists.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.todoList,$0.id) }, newOwner:{ key(.todoList,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoSeries.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.todoSeries,$0.id) }, newOwner:{ key(.todoSeries,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoSources.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ try require(oldTaskOwners[$0.taskID]) }, newOwner:{ try require(newTaskOwners[$0.taskID]) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.importantDays.map { r in let model=try r.model();var p=try model.preferences();p.desktopVisible=false;model.preferencesData=try JSONEncoder().encode(p);return model }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.importantDay,$0.id) }, newOwner:{ key(.importantDay,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.importantDayEntryLinks.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.importantDayEntryLink,$0.id) }, newOwner:{ key(.importantDayEntryLink,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.importantDayTodoLinks.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.importantDayTodoLink,$0.id) }, newOwner:{ key(.importantDayTodoLink,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.importantDayCovers.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.importantDay,$0.dayID) }, newOwner:{ key(.importantDay,$0.dayID) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.sleepRecords.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.sleepRecord,$0.id) }, newOwner:{ key(.sleepRecord,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.sleepGoals.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.sleepGoal,$0.id) }, newOwner:{ key(.sleepGoal,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.captureReceipts.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.captureReceipt,$0.id) }, newOwner:{ key(.captureReceipt,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.investmentParticipants.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.investmentParticipant,$0.id) }, newOwner:{ key(.investmentParticipant,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.investmentActivities.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.investmentActivity,$0.id) }, newOwner:{ key(.investmentActivity,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.investmentSessions.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.investmentRecord,$0.id) }, newOwner:{ key(.investmentRecord,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoSeriesPreferences.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.todoSeries,$0.id) }, newOwner:{ key(.todoSeries,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.todoReminderIntents.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ try require(oldTaskOwners[$0.id]) }, newOwner:{ try require(newTaskOwners[$0.id]) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.bodyReferenceSettings.map { r in try r.model() }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.bodyReference,$0.id) }, newOwner:{ key(.bodyReference,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.investmentOperations.map { r in try r.model(restoring:true) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.investmentRecord,$0.id) }, newOwner:{ key(.investmentRecord,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.netWorthItems.map { r in try NetWorthItem(r) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.netWorthItem,$0.id) }, newOwner:{ key(.netWorthItem,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        _ = try prepare(d.netWorthSnapshots.map { r in try NetWorthSnapshot(r) }, in:context, affected:affectedKeys,
            id: \.id, oldOwner:{ key(.netWorthSnapshot,$0.id) }, newOwner:{ key(.netWorthSnapshot,$0.id) }, copy:copy,
            unique:unique, updates:&updates, removals:&removals)
        // Relationship installation uses the actual retained target instances, never detached copies.
        for image in d.images where affectedKeys.contains(key(.entry,image.entryID)) {
            guard let row=installedImages[image.id],let entry=installedEntries[image.entryID] else {throw SyncDomainInstallError.missingOwner}
            updates.append {row.entry=entry}
        }
        try Task.checkCancellation()
        for update in updates {try update()}
        // Children are removed before parents. Cascade cannot discard a child moved to a surviving parent.
        for remove in removals.reversed() {remove()}
        // A valid remote projection alone does not prove its selected rows compose with local rows.
        // Validate the actual combined graph before the caller can commit it.
        _ = try SyncDomainCodec.capture(context:context)
    }

    private static func prepare<T:PersistentModel>(_ desired:[T], in context:ModelContext,
        affected:Set<SyncDomainKey>, id:KeyPath<T,UUID>, oldOwner:(T)throws->SyncDomainKey,
        newOwner:(T)throws->SyncDomainKey, copy:@escaping(T,T)throws->Void,
        unique:(T)->[String:AnyHashable], updates:inout[()throws->Void], removals:inout[()->Void]) throws -> [UUID:T] {
        let existing=try context.fetch(FetchDescriptor<T>())
        var byID:[UUID:T]=[:], selected:[UUID:T]=[:]
        for row in existing {guard byID.updateValue(row,forKey:row[keyPath:id])==nil else {throw SyncDomainInstallError.duplicateIdentity}}
        for row in desired {
            let incomingOwner=try newOwner(row)
            if let old=byID[row[keyPath:id]],affected.contains(try oldOwner(old)),!affected.contains(incomingOwner) {
                throw SyncDomainInstallError.scopeViolation
            }
            guard affected.contains(incomingOwner) else {continue}
            let identity=row[keyPath:id]
            guard selected.updateValue(row,forKey:identity)==nil else {throw SyncDomainInstallError.duplicateIdentity}
            if let old=byID[identity],!affected.contains(try oldOwner(old)) {throw SyncDomainInstallError.scopeViolation}
        }
        let removed=try existing.filter{affected.contains(try oldOwner($0)) && selected[$0[keyPath:id]]==nil}
        let removedIDs=Set(removed.map{$0[keyPath:id]})
        // SwiftData unique constraints can upsert a different UUID. Reject those collisions before save.
        var constraints:[String:[AnyHashable:UUID]]=[:]
        for row in existing.filter({!removedIDs.contains($0[keyPath:id]) && selected[$0[keyPath:id]]==nil}) + Array(selected.values) {
            for (name,value) in unique(row) {
                if let previous=constraints[name]?[value],previous != row[keyPath:id] {throw SyncDomainInstallError.uniqueConstraint}
                constraints[name,default:[:]][value]=row[keyPath:id]
            }
        }
        for (identity,row) in selected {
            if let old=byID[identity] {updates.append{try copy(old,row)}}
            else {byID[identity]=row;updates.append{context.insert(row)}}
        }
        for row in removed {removals.append{context.delete(row)};byID.removeValue(forKey:row[keyPath:id])}
        return byID
    }

    private static func copy(_ a:Entry,_ b:Entry) throws {
        a.kindRawValue=b.kindRawValue
        a.statusRawValue=b.statusRawValue
        a.title=b.title
        a.body=b.body
        a.createdAt=b.createdAt
        a.occurredAt=b.occurredAt
        a.updatedAt=b.updatedAt
        a.periodStart=b.periodStart
        a.periodEnd=b.periodEnd
    }
    private static func unique(_ row:Entry)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:ImageMetadata,_ b:ImageMetadata) throws {
        a.relativePath=b.relativePath
        a.originalFilename=b.originalFilename
        a.contentType=b.contentType
        a.byteCount=b.byteCount
        a.pixelWidth=b.pixelWidth
        a.pixelHeight=b.pixelHeight
        a.checksum=b.checksum
        a.sortOrder=b.sortOrder
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:ImageMetadata)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:Tag,_ b:Tag) throws {
        a.displayName=b.displayName
        a.normalizedName=b.normalizedName
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:Tag)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["normalizedName"]=AnyHashable(row.normalizedName)
        return result
    }

    private static func copy(_ a:ObjectLink,_ b:ObjectLink) throws {
        a.sourceTypeRawValue=b.sourceTypeRawValue
        a.sourceID=b.sourceID
        a.targetTypeRawValue=b.targetTypeRawValue
        a.targetID=b.targetID
        a.kindRawValue=b.kindRawValue
        a.deduplicationKey=b.deduplicationKey
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:ObjectLink)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["deduplicationKey"]=AnyHashable(row.deduplicationKey)
        return result
    }

    private static func copy(_ a:Habit,_ b:Habit) throws {
        a.name=b.name
        a.normalizedName=b.normalizedName
        a.statusRawValue=b.statusRawValue
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:Habit)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:HabitLog,_ b:HabitLog) throws {
        a.habitID=b.habitID
        a.occurredAt=b.occurredAt
        a.isCompleted=b.isCompleted
        a.quantity=b.quantity
        a.unit=b.unit
        a.result=b.result
        a.linkedEntryID=b.linkedEntryID
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:HabitLog)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:HabitConfiguration,_ b:HabitConfiguration) throws {
        a.habitID=b.habitID
        a.recordingModeRawValue=b.recordingModeRawValue
        a.dailyTargetCount=b.dailyTargetCount
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:HabitConfiguration)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["habitID"]=AnyHashable(row.habitID)
        return result
    }

    private static func copy(_ a:HabitLogDayMetadata,_ b:HabitLogDayMetadata) throws {
        a.habitLogID=b.habitLogID
        a.localDayIdentifier=b.localDayIdentifier
        a.localTimeZoneIdentifier=b.localTimeZoneIdentifier
        a.provenanceRawValue=b.provenanceRawValue
    }
    private static func unique(_ row:HabitLogDayMetadata)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["habitLogID"]=AnyHashable(row.habitLogID)
        return result
    }

    private static func copy(_ a:HabitPlanRevision,_ b:HabitPlanRevision) throws {
        a.habitID=b.habitID
        a.effectiveLocalDay=b.effectiveLocalDay
        a.recordingModeRawValue=b.recordingModeRawValue
        a.periodRawValue=b.periodRawValue
        a.goalRawValue=b.goalRawValue
        a.targetCount=b.targetCount
        a.weekdaysRawValue=b.weekdaysRawValue
        a.trustCoverageStartLocalDay=b.trustCoverageStartLocalDay
        a.createdAt=b.createdAt
        a.originRawValue=b.originRawValue
    }
    private static func unique(_ row:HabitPlanRevision)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:HabitLifecycleEvent,_ b:HabitLifecycleEvent) throws {
        a.habitID=b.habitID
        a.kindRawValue=b.kindRawValue
        a.occurredLocalDay=b.occurredLocalDay
        a.occurredAt=b.occurredAt
        a.createdAt=b.createdAt
        a.knownStatusRawValue=b.knownStatusRawValue
    }
    private static func unique(_ row:HabitLifecycleEvent)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:Goal,_ b:Goal) throws {
        a.kindRawValue=b.kindRawValue
        a.title=b.title
        a.normalizedTitle=b.normalizedTitle
        a.statusRawValue=b.statusRawValue
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
        a.completedAt=b.completedAt
    }
    private static func unique(_ row:Goal)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:GoalLifecycleEvent,_ b:GoalLifecycleEvent) throws {
        a.goalID=b.goalID
        a.kindRawValue=b.kindRawValue
        a.occurredAt=b.occurredAt
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:GoalLifecycleEvent)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:WeightRecord,_ b:WeightRecord) throws {
        a.weightKilograms=b.weightKilograms
        a.recordedAt=b.recordedAt
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:WeightRecord)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:WeeklyReview,_ b:WeeklyReview) throws {
        a.weekIdentifier=b.weekIdentifier
        a.periodStart=b.periodStart
        a.periodEnd=b.periodEnd
        a.rememberedText=b.rememberedText
        a.improvementText=b.improvementText
        a.nextStepText=b.nextStepText
        a.focusText=b.focusText
        a.isCompleted=b.isCompleted
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:WeeklyReview)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["weekIdentifier"]=AnyHashable(row.weekIdentifier)
        return result
    }

    private static func copy(_ a:EntryExternalSource,_ b:EntryExternalSource) throws {
        a.encodedSource=b.encodedSource
    }
    private static func unique(_ row:EntryExternalSource)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:EntryPin,_ b:EntryPin) throws {
        a.entryID=b.entryID
        a.pinnedAt=b.pinnedAt
    }
    private static func unique(_ row:EntryPin)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["entryID"]=AnyHashable(row.entryID)
        return result
    }

    private static func copy(_ a:EntryFollowUp,_ b:EntryFollowUp) throws {
        a.entryID=b.entryID
        a.body=b.body
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:EntryFollowUp)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoTask,_ b:TodoTask) throws {
        a.title=b.title
        a.notes=b.notes
        a.stateRawValue=b.stateRawValue
        a.isImportant=b.isImportant
        a.plannedDay=b.plannedDay
        a.deadlineDay=b.deadlineDay
        a.remindAt=b.remindAt
        a.reminderTimeZoneID=b.reminderTimeZoneID
        a.reminderLocalDay=b.reminderLocalDay
        a.reminderMinutes=b.reminderMinutes
        a.completedAt=b.completedAt
        a.canceledAt=b.canceledAt
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
        a.listID=b.listID
        a.seriesID=b.seriesID
        a.occurrenceIndex=b.occurrenceIndex
        a.occurrenceKey=b.occurrenceKey
        a.revision=b.revision
    }
    private static func unique(_ row:TodoTask)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        if let value=row.occurrenceKey {result["occurrenceKey"]=AnyHashable(value)}
        return result
    }

    private static func copy(_ a:TodoTaskEvent,_ b:TodoTaskEvent) throws {
        a.taskID=b.taskID
        a.sequence=b.sequence
        a.kindRawValue=b.kindRawValue
        a.occurredAt=b.occurredAt
        a.createdAt=b.createdAt
        a.beforeValue=b.beforeValue
        a.afterValue=b.afterValue
    }
    private static func unique(_ row:TodoTaskEvent)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoList,_ b:TodoList) throws {
        a.name=b.name
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:TodoList)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoSeries,_ b:TodoSeries) throws {
        a.frequencyRawValue=b.frequencyRawValue
        a.anchorDay=b.anchorDay
        a.plannedAnchorDay=b.plannedAnchorDay
        a.deadlineAnchorDay=b.deadlineAnchorDay
        a.title=b.title
        a.notes=b.notes
        a.isImportant=b.isImportant
        a.listID=b.listID
        a.reminderMinutes=b.reminderMinutes
        a.reminderDayOffset=b.reminderDayOffset
        a.isStopped=b.isStopped
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:TodoSeries)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoTaskSource,_ b:TodoTaskSource) throws {
        a.taskID=b.taskID
        a.entryID=b.entryID
    }
    private static func unique(_ row:TodoTaskSource)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["taskID"]=AnyHashable(row.taskID)
        return result
    }

    private static func copy(_ a:ImportantDay,_ b:ImportantDay) throws {
        var preferences=try b.preferences();preferences.desktopVisible=try a.preferences().desktopVisible
        let preferencesData=try JSONEncoder().encode(preferences)
        a.title=b.title
        a.notes=b.notes
        a.ruleData=b.ruleData
        a.preferencesData=preferencesData
        a.isArchived=b.isArchived
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
        a.revision=b.revision
    }
    private static func unique(_ row:ImportantDay)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:ImportantDayEntryLink,_ b:ImportantDayEntryLink) throws {
        a.pairKey=b.pairKey
        a.dayID=b.dayID
        a.entryID=b.entryID
        a.occurrenceIdentifier=b.occurrenceIdentifier
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:ImportantDayEntryLink)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["pairKey"]=AnyHashable(row.pairKey)
        return result
    }

    private static func copy(_ a:ImportantDayTodoLink,_ b:ImportantDayTodoLink) throws {
        a.pairKey=b.pairKey
        a.dayID=b.dayID
        a.taskID=b.taskID
        a.occurrenceIdentifier=b.occurrenceIdentifier
        a.dayRevisionAtLink=b.dayRevisionAtLink
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:ImportantDayTodoLink)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["pairKey"]=AnyHashable(row.pairKey)
        return result
    }

    private static func copy(_ a:ImportantDayCover,_ b:ImportantDayCover) throws {
        a.dayID=b.dayID
        a.relativePath=b.relativePath
        a.originalFilename=b.originalFilename
        a.contentType=b.contentType
        a.byteCount=b.byteCount
        a.pixelWidth=b.pixelWidth
        a.pixelHeight=b.pixelHeight
        a.checksum=b.checksum
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:ImportantDayCover)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["dayID"]=AnyHashable(row.dayID)
        return result
    }

    private static func copy(_ a:SleepRecord,_ b:SleepRecord) throws {
        a.wakeDay=b.wakeDay
        a.timeZoneID=b.timeZoneID
        a.valueData=b.valueData
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
        a.revision=b.revision
        a.observedAt=b.observedAt
    }
    private static func unique(_ row:SleepRecord)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["wakeDay"]=AnyHashable(row.wakeDay)
        return result
    }

    private static func copy(_ a:SleepGoalRule,_ b:SleepGoalRule) throws {
        a.effectiveDay=b.effectiveDay
        a.observedAt=b.observedAt
        a.observationTimeZoneID=b.observationTimeZoneID
        a.hasTakenEffect=b.hasTakenEffect
        a.cutoffMinute=b.cutoffMinute
        a.createdAt=b.createdAt
    }
    private static func unique(_ row:SleepGoalRule)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        result["effectiveDay"]=AnyHashable(row.effectiveDay)
        return result
    }

    private static func copy(_ a:CaptureImportReceipt,_ b:CaptureImportReceipt) throws {
        a.importedAt=b.importedAt
    }
    private static func unique(_ row:CaptureImportReceipt)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:InvestmentParticipant,_ b:InvestmentParticipant) throws {
        a.name=b.name
        a.isDefault=b.isDefault
        a.isArchived=b.isArchived
        a.sortOrder=b.sortOrder
    }
    private static func unique(_ row:InvestmentParticipant)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:InvestmentActivity,_ b:InvestmentActivity) throws {
        a.participantID=b.participantID
        a.name=b.name
        a.isArchived=b.isArchived
    }
    private static func unique(_ row:InvestmentActivity)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:InvestmentSession,_ b:InvestmentSession) throws {
        a.participantID=b.participantID
        a.activityID=b.activityID
        a.recorderID=b.recorderID
        a.valueData=b.valueData
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
        a.revision=b.revision
    }
    private static func unique(_ row:InvestmentSession)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoSeriesPreferences,_ b:TodoSeriesPreferences) throws {
        a.weekdaysMask=b.weekdaysMask
        a.reminderChannelRawValue=b.reminderChannelRawValue
    }
    private static func unique(_ row:TodoSeriesPreferences)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:TodoReminderIntent,_ b:TodoReminderIntent) throws {
        a.generation=b.generation
        a.revision=b.revision
        a.channelRawValue=b.channelRawValue
        a.isInstanceOverride=b.isInstanceOverride
    }
    private static func unique(_ row:TodoReminderIntent)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:BodyReferenceSettings,_ b:BodyReferenceSettings) throws {
        a.heightCentimeters=b.heightCentimeters
        a.referenceRawValue=b.referenceRawValue
    }
    private static func unique(_ row:BodyReferenceSettings)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:InvestmentOperation,_ b:InvestmentOperation) throws {
        var local=try InvestmentOperationTransfer(a);local.timer=local.timer.forRestore()
        if local == (try InvestmentOperationTransfer(b)) {return}
        a.participantID=b.participantID
        a.activityID=b.activityID
        a.recorderID=b.recorderID
        a.payload=b.payload
        a.revision=b.revision
        a.createdAt=b.createdAt
        a.updatedAt=b.updatedAt
    }
    private static func unique(_ row:InvestmentOperation)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:NetWorthItem,_ b:NetWorthItem) throws {
        a.payload=b.payload
    }
    private static func unique(_ row:NetWorthItem)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }

    private static func copy(_ a:NetWorthSnapshot,_ b:NetWorthSnapshot) throws {
        a.payload=b.payload
    }
    private static func unique(_ row:NetWorthSnapshot)->[String:AnyHashable] {
        var result:[String:AnyHashable]=[:]
        return result
    }
}
