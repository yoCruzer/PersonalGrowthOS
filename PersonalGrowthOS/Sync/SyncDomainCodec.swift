import Foundation
import SwiftData

// Business aggregates, not SwiftData row IDs or a whole-workspace document.
enum SyncDomainKind: String, Codable, CaseIterable {
    case entry, tag, objectLink, habit, habitLog, goal, weight, weeklyReview
    case todoList, todoSeries, todoTask, importantDay, importantDayEntryLink, importantDayTodoLink
    case sleepRecord, sleepGoal, captureReceipt, investmentParticipant, investmentActivity, investmentRecord
    case bodyReference, netWorthItem, netWorthSnapshot
}
struct SyncDomainKey: Codable, Hashable, Comparable {
    let kind: SyncDomainKind
    let id: UUID
    static func < (a: Self, b: Self) -> Bool {
        a.kind.rawValue == b.kind.rawValue ? a.id.uuidString < b.id.uuidString : a.kind.rawValue < b.kind.rawValue
    }
}
struct SyncOriginalDescriptor: Codable, Equatable {
    let id: UUID
    let sha256: String
    let byteCount: Int64
    let contentType: String
}
struct SyncDomainDocument: Codable, Equatable {
    let version: Int
    let key: SyncDomainKey
    let payload: Data
    let dependencies: [SyncDomainKey]
    let media: [SyncOriginalDescriptor]
}
struct SyncHabitConfiguration: Codable, Equatable {
    let id: UUID
    let habitID: UUID
    let recordingModeRawValue: String
    let dailyTargetCount: Int?
    let updatedAt: Date
}
struct SyncHabitLogMetadata: Codable, Equatable {
    let id: UUID
    let habitLogID: UUID
    let localDayIdentifier: String
    let localTimeZoneIdentifier: String
    let provenanceRawValue: String
}
// v12 TransferData deliberately flattens these rows; sync retains their original identities.
struct SyncDomainSupplement: Codable, Equatable {
    let habitConfigurations: [SyncHabitConfiguration]
    let habitLogMetadata: [SyncHabitLogMetadata]
    static func capture(context: ModelContext, kinds: Set<SyncDomainKind>? = nil) throws -> Self {
        let configs = kinds == nil || kinds!.contains(.habit) ? try context.fetch(FetchDescriptor<HabitConfiguration>()) : []
        let metadata = kinds == nil || kinds!.contains(.habitLog) ? try context.fetch(FetchDescriptor<HabitLogDayMetadata>()) : []
        return Self(habitConfigurations: configs.map {
            SyncHabitConfiguration(id: $0.id, habitID: $0.habitID, recordingModeRawValue: $0.recordingModeRawValue,
                dailyTargetCount: $0.dailyTargetCount, updatedAt: $0.updatedAt)
        }, habitLogMetadata: metadata.map {
            SyncHabitLogMetadata(id: $0.id, habitLogID: $0.habitLogID, localDayIdentifier: $0.localDayIdentifier,
                localTimeZoneIdentifier: $0.localTimeZoneIdentifier, provenanceRawValue: $0.provenanceRawValue)
        })
    }
}
struct SyncDomainProjection {
    let transfer: TransferData
    let supplement: SyncDomainSupplement
}
enum SyncDomainCodecError: Error { case malformed, unsupportedVersion, identity, duplicate, dependency, missingSupplement, resourceLimit }

// No device filesystem path is encoded. Original identity is UUID + exact bytes/hash.
private struct SyncMedia: Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let originalFilename: String
    let contentType: String
    let byteCount: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let checksum: String
    let sortOrder: Int?
    let createdAt: Date
    let updatedAt: Date?
    init(_ v: ImageTransfer) {
        id=v.id; ownerID=v.entryID; originalFilename=v.originalFilename; contentType=v.contentType
        byteCount=v.byteCount; pixelWidth=v.pixelWidth; pixelHeight=v.pixelHeight; checksum=v.checksum
        sortOrder=v.sortOrder; createdAt=v.createdAt; updatedAt=v.updatedAt
    }
    init(_ v: ImportantDayCoverTransfer) {
        id=v.id; ownerID=v.dayID; originalFilename=v.originalFilename; contentType=v.contentType
        byteCount=v.byteCount; pixelWidth=v.pixelWidth; pixelHeight=v.pixelHeight; checksum=v.checksum
        sortOrder=nil; createdAt=v.createdAt; updatedAt=nil
    }
    var descriptor: SyncOriginalDescriptor { .init(id:id,sha256:checksum,byteCount:byteCount,contentType:contentType) }
    func path() throws -> String { try MediaStore(rootURL: URL(fileURLWithPath:"/")).originalRelativePath(id:id,contentType:contentType) }
    func image() throws -> ImageTransfer {
        guard let sortOrder, let updatedAt else { throw SyncDomainCodecError.malformed }
        let path = try path()
        return ImageTransfer(id:id,entryID:ownerID,relativePath:path,
            mediaPath:"media/image-\(id.uuidString.lowercased()).\(URL(fileURLWithPath:path).pathExtension)",
            originalFilename:originalFilename,contentType:contentType,byteCount:byteCount,pixelWidth:pixelWidth,
            pixelHeight:pixelHeight,checksum:checksum,sortOrder:sortOrder,createdAt:createdAt,updatedAt:updatedAt)
    }
    func cover() throws -> ImportantDayCoverTransfer {
        guard sortOrder == nil, updatedAt == nil else { throw SyncDomainCodecError.malformed }
        return ImportantDayCoverTransfer(ImportantDayCover(dayID:ownerID,
            stored:StoredMediaFile(id:id,relativePath:try path(),byteCount:byteCount,checksum:checksum,pixelWidth:pixelWidth,pixelHeight:pixelHeight),
            source:MediaSource(url:URL(fileURLWithPath:"/"),originalFilename:originalFilename,contentType:contentType),createdAt:createdAt))
    }
}
private struct SyncDayPreferences: Codable, Equatable {
    let today: ImportantDayTodayPolicy
    let favoriteOrder: Int?
    let reminderOffsets: [Int]
    let reminderMinutes: Int
    let genericNotification: Bool
    let photoStyle: Bool
    let cropX: Double
    let cropY: Double
    init(_ v:ImportantDayPreferences) {
        today=v.today; favoriteOrder=v.favoriteOrder; reminderOffsets=v.reminderOffsets; reminderMinutes=v.reminderMinutes
        genericNotification=v.genericNotification; photoStyle=v.photoStyle; cropX=v.cropX; cropY=v.cropY
    }
    var value:ImportantDayPreferences { .init(today:today,favoriteOrder:favoriteOrder,reminderOffsets:reminderOffsets,
        reminderMinutes:reminderMinutes,genericNotification:genericNotification,desktopVisible:false,photoStyle:photoStyle,cropX:cropX,cropY:cropY) }
}
private struct SyncDay: Codable, Equatable {
    let id:UUID; let title:String; let notes:String; let rule:ImportantDayDateRule; let preferences:SyncDayPreferences
    let isArchived:Bool; let createdAt:Date; let updatedAt:Date; let revision:Int
    init(_ v:ImportantDayTransfer) {
        id=v.id;title=v.title;notes=v.notes;rule=v.rule;preferences=SyncDayPreferences(v.preferences)
        isArchived=v.isArchived;createdAt=v.createdAt;updatedAt=v.updatedAt;revision=v.revision
    }
    func transfer() throws -> ImportantDayTransfer {
        let m=try ImportantDay(id:id,title:title,notes:notes,rule:rule,preferences:preferences.value,createdAt:createdAt)
        m.isArchived=isArchived;m.updatedAt=updatedAt;m.revision=revision
        return try ImportantDayTransfer(m)
    }
}
private struct SyncTimer: Codable, Equatable {
    let state:InvestmentTimerState;let values:InvestmentValues;let target:Double?;let checkpointAt:Date
    let restoredState:InvestmentTimerState?;let editingSessionID:UUID?;let editingRevision:Int?;let durationText:String?
    init(_ original:InvestmentTimer) {
        let v=original.forRestore();state=v.state;values=v.values;target=v.target;checkpointAt=v.checkpointAt
        restoredState=v.restoredState;editingSessionID=v.editingSessionID;editingRevision=v.editingRevision;durationText=v.durationText
    }
    func value() throws -> InvestmentTimer {
        guard state != .running else {throw SyncDomainCodecError.malformed}
        let v=InvestmentTimer(state:state,values:values,target:target,checkpointAt:checkpointAt,restoredState:restoredState,
            editingSessionID:editingSessionID,editingRevision:editingRevision,durationText:durationText)
        try v.validate();return v
    }
}
private struct SyncOperation: Codable, Equatable {
    let id:UUID;let participantID:UUID;let recorderID:UUID;let activityID:UUID;let timer:SyncTimer;let revision:Int
    let createdAt:Date;let updatedAt:Date
    init(_ v:InvestmentOperationTransfer) {
        id=v.id;participantID=v.participantID;recorderID=v.recorderID;activityID=v.activityID;timer=SyncTimer(v.timer)
        revision=v.revision;createdAt=v.createdAt;updatedAt=v.updatedAt
    }
    func transfer() throws -> InvestmentOperationTransfer {
        let m=try InvestmentOperation(id:id,participantID:participantID,activityID:activityID,timer:timer.value(),now:createdAt,recorderID:recorderID)
        m.revision=revision;m.updatedAt=updatedAt;return try InvestmentOperationTransfer(m)
    }
}
private struct SyncEntryAggregate:Codable,Equatable {
    let entry:EntryTransfer;let images:[SyncMedia];let sources:[EntrySourceTransfer];let pins:[EntryPinTransfer];let followUps:[EntryFollowUpTransfer]
}
private struct SyncHabitAggregate:Codable,Equatable {
    let habit:HabitTransfer;let configuration:SyncHabitConfiguration?;let plans:[HabitPlanRevisionTransfer];let events:[HabitLifecycleEventTransfer]
}
private struct SyncLogAggregate:Codable,Equatable {let log:HabitLogTransfer;let metadata:SyncHabitLogMetadata?}
private struct SyncGoalAggregate:Codable,Equatable {let goal:GoalTransfer;let events:[GoalEventTransfer]}
private struct SyncTodoAggregate:Codable,Equatable {
    let series:TodoSeriesTransfer?;let tasks:[TodoTaskTransfer];let events:[TodoTaskEventTransfer]
    let sources:[TodoTaskSourceTransfer];let preferences:[TodoSeriesPreferencesTransfer];let intents:[TodoReminderIntentTransfer]
}
private struct SyncDayAggregate:Codable,Equatable {let day:SyncDay;let covers:[SyncMedia]}
private struct SyncInvestmentAggregate:Codable,Equatable {let id:UUID;let session:InvestmentSessionTransfer?;let operation:SyncOperation?}
private enum SyncDomainValue:Codable,Equatable {
    case entry(SyncEntryAggregate),tag(TagTransfer),objectLink(LinkTransfer),habit(SyncHabitAggregate),habitLog(SyncLogAggregate)
    case goal(SyncGoalAggregate),weight(WeightRecordTransfer),weeklyReview(WeeklyReviewTransfer)
    case todoList(TodoListTransfer),todoSeries(SyncTodoAggregate),todoTask(SyncTodoAggregate)
    case importantDay(SyncDayAggregate),importantDayEntryLink(ImportantDayEntryLinkTransfer),importantDayTodoLink(ImportantDayTodoLinkTransfer)
    case sleepRecord(SleepRecordTransfer),sleepGoal(SleepGoalTransfer),captureReceipt(CaptureReceiptTransfer)
    case investmentParticipant(InvestmentParticipantTransfer),investmentActivity(InvestmentActivityTransfer),investmentRecord(SyncInvestmentAggregate)
    case bodyReference(BodyReferenceSettingsTransfer),netWorthItem(NetWorthItemValue),netWorthSnapshot(NetWorthSnapshotValue)
}

enum SyncDomainCodec {
    static let maximumPayloadBytes = 128 * 1_024 * 1_024
    private static func bytes<T:Encodable>(_ v:T) throws -> Data {
        let e=JSONEncoder(); e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        // Native Date reference epoch preserves the exact persisted Double. No decimal/epoch conversion.
        return try e.encode(v)
    }
    static func encode(_ document:SyncDomainDocument) throws -> Data { _=try unpack(document);return try bytes(document) }
    static func decode(_ data:Data) throws -> SyncDomainDocument {
        guard data.count <= maximumPayloadBytes * 2 else {throw SyncDomainCodecError.resourceLimit}
        let v=try JSONDecoder().decode(SyncDomainDocument.self,from:data)
        guard try bytes(v)==data else {throw SyncDomainCodecError.malformed}
        _=try unpack(v);return v
    }
    static func capture(context:ModelContext, kinds:Set<SyncDomainKind>? = nil) throws -> [SyncDomainDocument] {
        // Caller holds its existing StorePublication/transaction lease; no second context or save.
        let data=try TransferSnapshot.make(context:context, includedSyncKinds:kinds)
        let supplement=try SyncDomainSupplement.capture(context:context,kinds:kinds)
        if kinds == nil { return try documents(from:data,supplement:supplement) }
        // Existing domain transaction validation remains the writer's responsibility.
        // This partial capture cannot assert global dependency closure or install itself.
        return try makeDocuments(from:data,supplement:supplement,selectedKinds:kinds)
    }
    private static func sorted<T>(_ values:[T],_ id:(T)->UUID)->[T] {values.sorted{id($0).uuidString<id($1).uuidString}}
    private static func key(_ kind:SyncDomainKind,_ id:UUID)->SyncDomainKey {.init(kind:kind,id:id)}
    private static func unique(_ ids:[UUID]) throws {guard Set(ids).count==ids.count else {throw SyncDomainCodecError.duplicate}}
    private static func validateSupplement(_ s:SyncDomainSupplement,_ d:TransferData) throws {
        try unique(s.habitConfigurations.map(\.id));try unique(s.habitConfigurations.map(\.habitID))
        try unique(s.habitLogMetadata.map(\.id));try unique(s.habitLogMetadata.map(\.habitLogID))
        let habits=Dictionary(uniqueKeysWithValues:d.habits.map{($0.id,$0)})
        let logs=Dictionary(uniqueKeysWithValues:d.habitLogs.map{($0.id,$0)})
        for c in s.habitConfigurations {
            // Backup transfer exposes effective settings; the supplement preserves raw row
            // identity and values. Once-per-day plans legitimately persist target=1 while
            // HabitSettingsResolver omits that inactive field from the flattened transfer.
            guard let h=habits[c.habitID],let mode=HabitRecordingMode(rawValue:c.recordingModeRawValue),
                  c.recordingModeRawValue==h.recordingMode,
                  (mode == .multiplePerDay ? c.dailyTargetCount : nil)==h.dailyTargetCount,
                  c.updatedAt.timeIntervalSinceReferenceDate.isFinite else {throw SyncDomainCodecError.missingSupplement}
        }
        for m in s.habitLogMetadata {
            guard let l=logs[m.habitLogID],l.localDayIdentifier==m.localDayIdentifier,
                  l.localTimeZoneIdentifier==m.localTimeZoneIdentifier,l.localDayProvenance==m.provenanceRawValue else {throw SyncDomainCodecError.missingSupplement}
        }
        let metadataIDs=Set(s.habitLogMetadata.map(\.habitLogID))
        guard d.habitLogs.allSatisfy({($0.localDayIdentifier == nil) == !metadataIDs.contains($0.id)}) else {throw SyncDomainCodecError.missingSupplement}
    }
    private static func validateTransfer(_ d:TransferData) throws {
        // A structural manifest only: this does NOT claim original files were read/hash-verified.
        let manifest=ExportManifest(formatIdentifier:ExportManifest.formatIdentifier,packageSchemaVersion:12,
            appVersion:"sync-domain-v1",appBuild:"0",exportID:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!,
            exportedAt:Date(timeIntervalSinceReferenceDate:0),objectCounts:d.objectCounts,
            dataFile:ExportFileRecord(path:"data.json",byteCount:0,sha256:String(repeating:"0",count:64)),
            mediaFiles:d.mediaAssets.map{ExportMediaFileRecord(imageID:$0.id,path:$0.mediaPath,byteCount:$0.byteCount,sha256:$0.checksum)})
        try TransferValidator.validate(manifest:manifest,data:d,limits:.production)
    }
    static func documents(from d:TransferData,supplement:SyncDomainSupplement) throws -> [SyncDomainDocument] {
        try validateTransfer(d)
        return try makeDocuments(from:d,supplement:supplement,selectedKinds:nil)
    }
    private static func makeDocuments(from d:TransferData,supplement:SyncDomainSupplement,selectedKinds:Set<SyncDomainKind>?) throws -> [SyncDomainDocument] {
        try unique(d.habits.map(\.id));try unique(d.habitLogs.map(\.id));try unique(d.todoTasks.map(\.id))
        try unique(d.investmentSessions.map(\.id));try unique(d.investmentOperations.map(\.id))
        try validateSupplement(supplement,d)
        for ids in [d.images.map(\.id),d.entrySources.map(\.entryID),d.entryPins.map(\.id),d.entryFollowUps.map(\.id),
                    d.habitPlanRevisions.map(\.id),d.habitLifecycleEvents.map(\.id),d.goalEvents.map(\.id),
                    d.todoEvents.map(\.id),d.todoSources.map(\.id),d.todoSeriesPreferences.map(\.id),d.todoReminderIntents.map(\.id),
                    d.importantDayCovers.map(\.id),d.importantDayCovers.map(\.dayID)] {try unique(ids)}
        var values:[SyncDomainValue]=[]
        let configs=Dictionary(uniqueKeysWithValues:supplement.habitConfigurations.map{($0.habitID,$0)})
        let metadata=Dictionary(uniqueKeysWithValues:supplement.habitLogMetadata.map{($0.habitLogID,$0)})
        let images=Dictionary(grouping:d.images,by: \.entryID), sources=Dictionary(grouping:d.entrySources,by: \.entryID)
        let pins=Dictionary(grouping:d.entryPins,by: \.entryID), followUps=Dictionary(grouping:d.entryFollowUps,by: \.entryID)
        let plans=Dictionary(grouping:d.habitPlanRevisions,by: \.habitID), habitEvents=Dictionary(grouping:d.habitLifecycleEvents,by: \.habitID)
        let goalEvents=Dictionary(grouping:d.goalEvents,by: \.goalID), covers=Dictionary(grouping:d.importantDayCovers,by: \.dayID)
        let tasksBySeries=Dictionary(grouping:d.todoTasks,by: \.seriesID)
        let todoEvents=Dictionary(grouping:d.todoEvents,by: \.taskID), todoSources=Dictionary(grouping:d.todoSources,by: \.taskID)
        let intents=Dictionary(grouping:d.todoReminderIntents,by: \.id), preferences=Dictionary(grouping:d.todoSeriesPreferences,by: \.id)
        // Every captured child must have its aggregate owner. Partial captures never
        // silently drop an orphan just because global validation is deferred.
        func owned(_ childIDs:[UUID],by ownerIDs:[UUID]) throws {
            guard Set(childIDs).isSubset(of:Set(ownerIDs)) else {throw SyncDomainCodecError.dependency}
        }
        try owned(d.images.map(\.entryID)+d.entrySources.map(\.entryID)+d.entryPins.map(\.entryID)+d.entryFollowUps.map(\.entryID),by:d.entries.map(\.id))
        try owned(d.habitPlanRevisions.map(\.habitID)+d.habitLifecycleEvents.map(\.habitID),by:d.habits.map(\.id))
        try owned(d.goalEvents.map(\.goalID),by:d.goals.map(\.id))
        try owned(d.importantDayCovers.map(\.dayID),by:d.importantDays.map(\.id))
        try owned(d.todoEvents.map(\.taskID)+d.todoSources.map(\.taskID)+d.todoReminderIntents.map(\.id),by:d.todoTasks.map(\.id))
        if selectedKinds == nil || selectedKinds!.contains(.todoSeries) {
            try owned(d.todoTasks.compactMap(\.seriesID)+d.todoSeriesPreferences.map(\.id),by:d.todoSeries.map(\.id))
        }
        for e in d.entries {values.append(.entry(.init(entry:e,images:sorted(images[e.id,default:[]],{$0.id}).map(SyncMedia.init),
            sources:sources[e.id,default:[]],pins:sorted(pins[e.id,default:[]],{$0.id}),
            followUps:sorted(followUps[e.id,default:[]],{$0.id}))))}
        values += d.tags.map(SyncDomainValue.tag);values += d.links.map(SyncDomainValue.objectLink)
        for h in d.habits {values.append(.habit(.init(habit:h,configuration:configs[h.id],plans:sorted(plans[h.id,default:[]],{$0.id}),events:sorted(habitEvents[h.id,default:[]],{$0.id}))))}
        for l in d.habitLogs {values.append(.habitLog(.init(log:l,metadata:metadata[l.id])))}
        for g in d.goals {values.append(.goal(.init(goal:g,events:sorted(goalEvents[g.id,default:[]],{$0.id}))))}
        values += d.weightRecords.map(SyncDomainValue.weight);values += d.weeklyReviews.map(SyncDomainValue.weeklyReview)
        values += d.todoLists.map(SyncDomainValue.todoList)
        func todo(_ series:TodoSeriesTransfer?,_ tasks:[TodoTaskTransfer])->SyncTodoAggregate {
            let ids=tasks.map(\.id)
            return .init(series:series,tasks:sorted(tasks,{$0.id}),events:sorted(ids.flatMap{todoEvents[$0,default:[]]},{$0.id}),
                sources:sorted(ids.flatMap{todoSources[$0,default:[]]},{$0.id}),preferences:series.map{preferences[$0.id,default:[]]} ?? [],
                intents:sorted(ids.flatMap{intents[$0,default:[]]},{$0.id}))
        }
        for series in d.todoSeries {values.append(.todoSeries(todo(series,tasksBySeries[series.id,default:[]])))}
        for task in d.todoTasks where task.seriesID==nil {values.append(.todoTask(todo(nil,[task])))}
        for day in d.importantDays {values.append(.importantDay(.init(day:SyncDay(day),covers:sorted(covers[day.id,default:[]],{$0.id}).map(SyncMedia.init))))}
        values += d.importantDayEntryLinks.map(SyncDomainValue.importantDayEntryLink)
        values += d.importantDayTodoLinks.map(SyncDomainValue.importantDayTodoLink)
        values += d.sleepRecords.map(SyncDomainValue.sleepRecord);values += d.sleepGoals.map(SyncDomainValue.sleepGoal)
        values += d.captureReceipts.map(SyncDomainValue.captureReceipt)
        values += d.investmentParticipants.map(SyncDomainValue.investmentParticipant);values += d.investmentActivities.map(SyncDomainValue.investmentActivity)
        let sessions=Dictionary(uniqueKeysWithValues:d.investmentSessions.map{($0.id,$0)})
        let operations=Dictionary(uniqueKeysWithValues:d.investmentOperations.map{($0.id,$0)})
        for id in Set(sessions.keys).union(operations.keys) {values.append(.investmentRecord(.init(id:id,session:sessions[id],operation:operations[id].map(SyncOperation.init))))}
        values += d.bodyReferenceSettings.map(SyncDomainValue.bodyReference)
        values += d.netWorthItems.map(SyncDomainValue.netWorthItem);values += d.netWorthSnapshots.map(SyncDomainValue.netWorthSnapshot)
        let taskKeys=Dictionary(uniqueKeysWithValues:d.todoTasks.map{($0.id,key($0.seriesID == nil ? .todoTask:.todoSeries,$0.seriesID ?? $0.id))})
        let selected = try values.filter { value in
            guard let selectedKinds else {return true}
            return selectedKinds.contains(try identity(value).kind)
        }
        let docs=try selected.map {value -> SyncDomainDocument in
            try Task.checkCancellation();let payload=try bytes(value)
            guard payload.count<=maximumPayloadBytes else {throw SyncDomainCodecError.resourceLimit}
            return .init(version:1,key:try identity(value),payload:payload,dependencies:try dependencies(value,taskKeys:taskKeys),media:media(value))
        }.sorted{$0.key<$1.key}
        guard Set(docs.map(\.key)).count==docs.count else {throw SyncDomainCodecError.duplicate}
        return docs
    }
    private static func identity(_ v:SyncDomainValue)throws->SyncDomainKey {
        switch v {
        case .entry(let a):return key(.entry,a.entry.id)
        case .tag(let a):return key(.tag,a.id)
        case .objectLink(let a):return key(.objectLink,a.id)
        case .habit(let a):return key(.habit,a.habit.id)
        case .habitLog(let a):return key(.habitLog,a.log.id)
        case .goal(let a):return key(.goal,a.goal.id)
        case .weight(let a):return key(.weight,a.id)
        case .weeklyReview(let a):return key(.weeklyReview,a.id)
        case .todoList(let a):return key(.todoList,a.id)
        case .todoSeries(let a):guard let s=a.series else {throw SyncDomainCodecError.identity};return key(.todoSeries,s.id)
        case .todoTask(let a):guard a.series==nil,a.tasks.count==1,a.tasks[0].seriesID==nil else {throw SyncDomainCodecError.identity};return key(.todoTask,a.tasks[0].id)
        case .importantDay(let a):return key(.importantDay,a.day.id)
        case .importantDayEntryLink(let a):return key(.importantDayEntryLink,a.id)
        case .importantDayTodoLink(let a):return key(.importantDayTodoLink,a.id)
        case .sleepRecord(let a):return key(.sleepRecord,a.id)
        case .sleepGoal(let a):return key(.sleepGoal,a.id)
        case .captureReceipt(let a):return key(.captureReceipt,a.id)
        case .investmentParticipant(let a):return key(.investmentParticipant,a.id)
        case .investmentActivity(let a):return key(.investmentActivity,a.id)
        case .investmentRecord(let a):guard a.session != nil || a.operation != nil else {throw SyncDomainCodecError.identity};return key(.investmentRecord,a.id)
        case .bodyReference(let a):return key(.bodyReference,a.id)
        case .netWorthItem(let a):return key(.netWorthItem,a.id)
        case .netWorthSnapshot(let a):return key(.netWorthSnapshot,a.id)
        }
    }
    private static func media(_ value:SyncDomainValue)->[SyncOriginalDescriptor] {
        let assets:[SyncMedia]
        switch value {case .entry(let a):assets=a.images;case .importantDay(let a):assets=a.covers;default:assets=[]}
        return assets.map(\.descriptor).sorted{$0.id.uuidString<$1.id.uuidString}
    }
    private static func dependencies(_ v:SyncDomainValue,taskKeys:[UUID:SyncDomainKey])throws->[SyncDomainKey] {
        var result:[SyncDomainKey]=[]
        func endpoint(_ type:String,_ id:UUID)throws->SyncDomainKey {
            guard let t=LinkObjectType(rawValue:type) else {throw SyncDomainCodecError.dependency}
            switch t {case .entry:return key(.entry,id);case .tag:return key(.tag,id);case .habit:return key(.habit,id);case .goal:return key(.goal,id)}
        }
        switch v {
        case .objectLink(let l):result=[try endpoint(l.sourceType,l.sourceID),try endpoint(l.targetType,l.targetID)]
        case .habitLog(let a):result=[key(.habit,a.log.habitID)];if let id=a.log.linkedEntryID {result.append(key(.entry,id))}
        case .todoSeries(let a),.todoTask(let a):
            result += a.tasks.compactMap(\.listID).map{key(.todoList,$0)}
            if let id=a.series?.listID {result.append(key(.todoList,id))}
            result += a.sources.map{key(.entry,$0.entryID)}
        case .importantDayEntryLink(let l):result=[key(.importantDay,l.dayID),key(.entry,l.entryID)]
        case .importantDayTodoLink(let l):
            guard let task=taskKeys[l.taskID] else {throw SyncDomainCodecError.dependency}
            result=[key(.importantDay,l.dayID),task]
        case .investmentActivity(let a):result=[key(.investmentParticipant,a.participantID)]
        case .investmentRecord(let a):
            if let s=a.session {result += [key(.investmentParticipant,s.participantID),key(.investmentParticipant,s.recorderID),key(.investmentActivity,s.activityID)]}
            if let o=a.operation {result += [key(.investmentParticipant,o.participantID),key(.investmentParticipant,o.recorderID),key(.investmentActivity,o.activityID)]
                if let id=o.timer.editingSessionID {result.append(key(.investmentRecord,id))}}
        case .netWorthSnapshot(let a):result=a.items.map{key(.netWorthItem,$0.id)};if let id=a.editingID {result.append(key(.netWorthSnapshot,id))}
        default:break
        }
        return Set(result).sorted()
    }
    private static func unpack(_ document:SyncDomainDocument)throws->SyncDomainValue {
        guard document.version==1 else {throw SyncDomainCodecError.unsupportedVersion}
        guard document.payload.count<=maximumPayloadBytes else {throw SyncDomainCodecError.resourceLimit}
        let value=try JSONDecoder().decode(SyncDomainValue.self,from:document.payload)
        guard try bytes(value)==document.payload,try identity(value)==document.key,media(value)==document.media,
              Set(document.dependencies).count==document.dependencies.count,document.dependencies==document.dependencies.sorted() else {throw SyncDomainCodecError.malformed}
        return value
    }
    /// A readable comparison of immutable business values. The original document is
    /// retained intact; identifiers, transport hashes and device internals are not UI.
    static func conflictPreview(_ document: SyncDomainDocument) throws -> String {
        let value = try unpack(document)
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append(label + ": " + value)
        }
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...8))) }
        func date(_ value: Date) -> String { value.formatted(date: .numeric, time: .standard) }
        func yes(_ value: Bool) -> String { value ? String(localized: "Yes") : String(localized: "No") }
        func state(_ raw: String) -> String {
            switch raw {
            case "inbox": return String(localized: "Inbox")
            case "organized": return String(localized: "Organized")
            case "archived": return String(localized: "Archived")
            case "open", "active": return String(localized: "Active")
            case "completed", "saved": return String(localized: "Completed")
            case "canceled", "discarded": return String(localized: "Canceled")
            case "paused": return String(localized: "Paused")
            case "recoveryRequired": return String(localized: "Needs review before resuming")
            case "running": return String(localized: "Running")
            case "targetReached": return String(localized: "Target reached")
            case "pendingSave": return String(localized: "Waiting to save")
            case "draft": return String(localized: "Draft")
            case "deleted": return String(localized: "Deleted")
            case "created": return String(localized: "Created")
            case "edited": return String(localized: "Edited")
            case "resumed", "reopened", "restored", "restarted": return String(localized: "Reopened")
            case "skipped": return String(localized: "Skipped")
            case "seriesStopped": return String(localized: "Repeating series stopped")
            case "successorWithdrawn": return String(localized: "Next occurrence withdrawn")
            case "convertedToSeries": return String(localized: "Changed to repeating")
            case "migrationBaseline": return String(localized: "Historical baseline")
            default: return String(localized: "Unknown")
            }
        }
        func frequency(_ raw: String) -> String {
            switch raw {
            case "day", "daily": return String(localized: "Daily")
            case "week", "weekly": return String(localized: "Weekly")
            case "month", "monthly": return String(localized: "Monthly")
            case "yearly": return String(localized: "Yearly")
            case "weekdays": return String(localized: "Weekdays")
            case "weekends": return String(localized: "Weekends")
            case "customWeekdays": return String(localized: "Selected weekdays")
            case "trackingOnly": return String(localized: "Tracking only")
            default: return String(localized: "Unknown")
            }
        }
        func recording(_ raw: String?) -> String {
            switch raw {
            case "oncePerDay": return String(localized: "Once per day")
            case "multiplePerDay": return String(localized: "Multiple times per day")
            default: return String(localized: "Unknown")
            }
        }
        func channel(_ raw: String) -> String {
            switch raw {
            case "alarm": return String(localized: "Alarm")
            case "notification": return String(localized: "Notification")
            default: return String(localized: "Unknown")
            }
        }
        func task(_ t: TodoTaskTransfer) {
            lines.append(t.title); add(String(localized: "Notes"), t.notes)
            add(String(localized: "Status"), state(t.stateRawValue)); add(String(localized: "Important"), yes(t.isImportant))
            add(String(localized: "Planned day"), t.plannedDay); add(String(localized: "Deadline"), t.deadlineDay)
            add(String(localized: "Reminder"), t.remindAt.map(date)); add(String(localized: "Time zone"), t.reminderTimeZoneID)
            add(String(localized: "Completed"), t.completedAt.map(date)); add(String(localized: "Canceled"), t.canceledAt.map(date))
            add(String(localized: "Updated"), date(t.updatedAt))
        }
        func photos(_ images: [SyncMedia]) {
            add(String(localized: "Photos"), String(images.count))
            for image in images {
                lines.append(image.originalFilename + " · " + String(image.pixelWidth) + " × " + String(image.pixelHeight))
            }
        }
        func sleepTime(_ value: SleepRange?) -> String? {
            value.map { $0.day + " " + String(format: "%02d:%02d", $0.minute / 60, $0.minute % 60)
                + ($0.precision == 0 ? "" : "–" + String(format: "%02d:%02d", (($0.minute + $0.precision) / 60) % 24, ($0.minute + $0.precision) % 60)) }
        }
        switch value {
        case .entry(let a):
            lines.append(a.entry.title ?? String(localized: "Entry")); add(String(localized: "Content"), a.entry.body)
            add(String(localized: "Status"), state(a.entry.status)); add(String(localized: "Occurred"), date(a.entry.occurredAt))
            add(String(localized: "Period start"), a.entry.periodStart.map(date)); add(String(localized: "Period end"), a.entry.periodEnd.map(date))
            photos(a.images)
            for source in a.sources {
                add(String(localized: "Source"), source.source.title); add(String(localized: "URL"), source.source.url)
                add(String(localized: "Canonical URL"), source.source.canonicalURL); add(String(localized: "Site"), source.source.siteName)
                add(String(localized: "Captured"), date(source.source.capturedAt))
            }
            for pin in a.pins { add(String(localized: "Pinned"), date(pin.pinnedAt)) }
            for followUp in a.followUps { add(String(localized: "Follow-up"), followUp.body); add(String(localized: "Updated"), date(followUp.updatedAt)) }
            add(String(localized: "Updated"), date(a.entry.updatedAt))
        case .tag(let a): lines.append(a.displayName); add(String(localized: "Updated"), date(a.updatedAt))
        case .objectLink(let a):
            let relations: [String: String] = ["entryUsesTag": String(localized: "Entry tag"), "entryRelatesHabit": String(localized: "Entry linked to habit"),
                "entryRelatesGoal": String(localized: "Entry linked to goal"), "habitSupportsGoal": String(localized: "Habit supporting goal"),
                "reviewsEntry": String(localized: "Entry included in review"), "reviewsHabit": String(localized: "Habit included in review"), "reviewsGoal": String(localized: "Goal included in review")]
            lines.append(relations[a.kind] ?? String(localized: "Related item")); add(String(localized: "Created"), date(a.createdAt))
        case .habit(let a):
            lines.append(a.habit.name); add(String(localized: "Status"), state(a.habit.status))
            add(String(localized: "Recording"), recording(a.habit.recordingMode))
            add(String(localized: "Daily target"), a.habit.dailyTargetCount.map(String.init))
            for plan in a.plans {
                add(String(localized: "Plan begins"), plan.effectiveLocalDay); add(String(localized: "Period"), frequency(plan.period))
                let goals = ["none": String(localized: "No target"), "everyDay": String(localized: "Every day"), "selectedWeekdays": String(localized: "Selected weekdays"), "count": String(localized: "Count target")]
                add(String(localized: "Goal"), goals[plan.goal]); add(String(localized: "Recording"), recording(plan.recordingMode))
                add(String(localized: "Target count"), plan.targetCount.map(String.init)); add(String(localized: "Weekdays (Monday = 1)"), plan.weekdays)
            }
            for event in a.events { add(String(localized: "History"), state(event.kind) + " · " + event.occurredLocalDay) }
            add(String(localized: "Updated"), date(a.habit.updatedAt))
        case .habitLog(let a):
            lines.append(String(localized: "Habit check-in")); add(String(localized: "Day"), a.log.localDayIdentifier)
            add(String(localized: "Occurred"), date(a.log.occurredAt)); add(String(localized: "Completed"), yes(a.log.isCompleted))
            add(String(localized: "Quantity"), a.log.quantity.map(number)); add(String(localized: "Unit"), a.log.unit); add(String(localized: "Result"), a.log.result)
            add(String(localized: "Time zone"), a.log.localTimeZoneIdentifier)
        case .goal(let a):
            lines.append(a.goal.title); add(String(localized: "Status"), state(a.goal.status)); add(String(localized: "Completed"), a.goal.completedAt.map(date))
            for event in a.events { add(String(localized: "History"), state(event.kind) + " · " + date(event.occurredAt)) }
            add(String(localized: "Updated"), date(a.goal.updatedAt))
        case .weight(let a):
            lines.append(number(a.weightKilograms) + " kg"); add(String(localized: "Recorded"), date(a.recordedAt)); add(String(localized: "Updated"), date(a.updatedAt))
        case .weeklyReview(let a):
            lines.append(String(localized: "Weekly review") + " · " + a.weekIdentifier)
            add(String(localized: "Remembered"), a.rememberedText); add(String(localized: "Improvement"), a.improvementText)
            add(String(localized: "Next step"), a.nextStepText); add(String(localized: "Focus"), a.focusText); add(String(localized: "Completed"), yes(a.isCompleted))
        case .todoList(let a): lines.append(a.name); add(String(localized: "Updated"), date(a.updatedAt))
        case .todoTask(let a), .todoSeries(let a):
            if let series = a.series {
                lines.append(series.title); add(String(localized: "Notes"), series.notes); add(String(localized: "Repeats"), frequency(series.frequencyRawValue))
                add(String(localized: "Anchor day"), series.anchorDay); add(String(localized: "Stopped"), yes(series.isStopped))
                add(String(localized: "Important"), yes(series.isImportant)); add(String(localized: "Planned day"), series.plannedAnchorDay); add(String(localized: "Deadline"), series.deadlineAnchorDay)
                add(String(localized: "Reminder minute of day"), series.reminderMinutes.map(String.init)); add(String(localized: "Reminder day offset"), series.reminderDayOffset.map(String.init))
            }
            for t in a.tasks { task(t) }
            for p in a.preferences { add(String(localized: "Reminder channel"), channel(p.reminderChannelRawValue)); add(String(localized: "Selected weekdays"), try p.weekdaysMask.map { try TodoWeekdayRule.weekdays($0).sorted().map(String.init).joined(separator: ", ") }) }
            for intent in a.intents {
                add(String(localized: "Reminder for"), a.tasks.first { $0.id == intent.id }?.title)
                add(String(localized: "Reminder channel"), channel(intent.channelRawValue))
                add(String(localized: "Occurrence override"), yes(intent.isInstanceOverride))
            }
            for event in a.events { add(String(localized: "History"), state(event.kindRawValue) + " · " + date(event.occurredAt)) }
        case .importantDay(let a):
            lines.append(a.day.title); add(String(localized: "Notes"), a.day.notes)
            let rule = a.day.rule
            add(String(localized: "Date"), (rule.year.map(String.init) ?? String(localized: "Year unknown")) + "-" + String(rule.month) + "-" + String(rule.day))
            add(String(localized: "Calendar"), rule.calendar == .chinese ? String(localized: "Chinese lunar") : String(localized: "Gregorian"))
            add(String(localized: "Leap month"), yes(rule.isLeapMonth)); add(String(localized: "Archived"), yes(a.day.isArchived))
            let presets: [ImportantDayPreset: String] = [.anticipated: String(localized: "Looking forward"), .beginning: String(localized: "Since a beginning"), .anniversary: String(localized: "Anniversary")]
            add(String(localized: "Kind"), presets[rule.preset]); add(String(localized: "Perspective"), rule.perspective == .next ? String(localized: "Next occurrence") : String(localized: "Elapsed time"))
            if let leap = rule.leapDayRule { add(String(localized: "February 29 rule"), leap == .february28 ? String(localized: "February 28") : leap == .march1 ? String(localized: "March 1") : String(localized: "Leap years only")) }
            if let leap = rule.leapMonthRule { add(String(localized: "Leap month rule"), leap == .regularFallback ? String(localized: "Use regular month when absent") : String(localized: "Leap years only")) }
            if let short = rule.shortMonthRule { add(String(localized: "Short month rule"), short == .lastDay ? String(localized: "Last day") : String(localized: "Skip")) }
            add(String(localized: "Today visibility"), a.day.preferences.today == .always ? String(localized: "Always") : a.day.preferences.today == .hidden ? String(localized: "Hidden") : String(localized: "Automatic"))
            add(String(localized: "Favorite order"), a.day.preferences.favoriteOrder.map(String.init))
            add(String(localized: "Private reminder wording"), yes(a.day.preferences.genericNotification))
            add(String(localized: "Photo style"), yes(a.day.preferences.photoStyle)); add(String(localized: "Photo crop"), number(a.day.preferences.cropX) + ", " + number(a.day.preferences.cropY))
            add(String(localized: "Reminder days before"), a.day.preferences.reminderOffsets.map(String.init).joined(separator: ", "))
            add(String(localized: "Reminder time"), String(format: "%02d:%02d", a.day.preferences.reminderMinutes / 60, a.day.preferences.reminderMinutes % 60))
            photos(a.covers); add(String(localized: "Updated"), date(a.day.updatedAt))
        case .importantDayEntryLink(let a):
            lines.append(String(localized: "Important day linked to entry")); add(String(localized: "Occurrence"), a.occurrenceIdentifier); add(String(localized: "Created"), date(a.createdAt))
        case .importantDayTodoLink(let a):
            lines.append(String(localized: "Important day linked to task")); add(String(localized: "Occurrence"), a.occurrenceIdentifier); add(String(localized: "Created"), date(a.createdAt))
        case .sleepRecord(let a):
            lines.append(String(localized: "Sleep") + " · " + a.wakeDay); add(String(localized: "Bedtime"), sleepTime(a.values.bedtime)); add(String(localized: "Wake time"), sleepTime(a.values.wake))
            add(String(localized: "Feeling (1–5)"), a.values.feeling.map(String.init)); add(String(localized: "Notes"), a.values.note); add(String(localized: "Time zone"), a.timeZoneID)
            add(String(localized: "Bedtime UTC offset (seconds)"), a.values.bedtime?.utcOffset.map(String.init)); add(String(localized: "Wake UTC offset (seconds)"), a.values.wake?.utcOffset.map(String.init))
        case .sleepGoal(let a):
            lines.append(String(localized: "Bedtime goal")); add(String(localized: "Effective day"), a.effectiveDay)
            add(String(localized: "Cutoff"), a.cutoffMinute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? String(localized: "Disabled"))
            add(String(localized: "Has taken effect"), yes(a.hasTakenEffect)); add(String(localized: "Time zone"), a.observationTimeZoneID)
        case .captureReceipt(let a): lines.append(String(localized: "Shared content import")); add(String(localized: "Imported"), date(a.importedAt))
        case .investmentParticipant(let a):
            lines.append(a.name); add(String(localized: "Default participant"), yes(a.isDefault)); add(String(localized: "Archived"), yes(a.isArchived)); add(String(localized: "Order"), String(a.sortOrder))
        case .investmentActivity(let a): lines.append(a.name); add(String(localized: "Archived"), yes(a.isArchived))
        case .investmentRecord(let a):
            lines.append(String(localized: "Time investment"))
            if let v = a.session?.values ?? a.operation?.timer.values {
                add(String(localized: "Day"), v.day); add(String(localized: "Duration (seconds)"), number(v.seconds)); add(String(localized: "Notes"), v.note)
                add(String(localized: "Feeling (1–5)"), v.feeling.map(String.init)); add(String(localized: "Time zone"), v.timeZoneID); add(String(localized: "Duration corrected"), yes(v.corrected))
                for span in v.spans { add(String(localized: "Recorded interval"), date(span.start) + " – " + date(span.end)) }
            }
            if let op = a.operation {
                add(String(localized: "Status"), state(op.timer.state.rawValue)); add(String(localized: "Prior timer status"), op.timer.restoredState.map { state($0.rawValue) })
                add(String(localized: "Target (seconds)"), op.timer.target.map(number)); add(String(localized: "Draft duration"), op.timer.durationText)
            }
        case .bodyReference(let a):
            lines.append(String(localized: "Body reference")); add(String(localized: "Height (cm)"), a.heightCentimeters.map(number)); add(String(localized: "BMI reference"), a.referenceRawValue == "who" ? "WHO" : a.referenceRawValue == "china" ? String(localized: "China") : String(localized: "Unknown"))
        case .netWorthItem(let a):
            lines.append(a.name); add(String(localized: "Type"), a.side.title + " · " + a.category.title); add(String(localized: "Ownership"), a.ownership)
            add(String(localized: "Notes"), a.note); add(String(localized: "Archived"), yes(a.archived))
        case .netWorthSnapshot(let a):
            lines.append(String(localized: "Net worth snapshot") + " · " + a.day); add(String(localized: "Confirmed"), yes(a.confirmed))
            add(String(localized: "Notes"), a.note); add(String(localized: "Scope adjusted"), yes(a.scopeAdjusted))
            add(String(localized: "Assets confirmed"), yes(a.assetsConfirmed)); add(String(localized: "Liabilities confirmed"), yes(a.liabilitiesConfirmed))
            add(String(localized: "Time zone"), a.timeZoneID)
            for row in a.items {
                lines.append(row.name + " · " + row.side.title + " · " + row.category.title)
                add(String(localized: "Included"), yes(row.included)); add(String(localized: "Ownership"), row.ownership)
                add(String(localized: "Amount"), row.cents.map(NetWorthMoney.decimal) ?? String(localized: "Unknown"))
                add(String(localized: "Amount date"), row.amountDay); add(String(localized: "Amount status"), row.state.title)
                add(String(localized: "Draft input"), row.inputText); add(String(localized: "Pending confirmation"), yes(row.pending)); add(String(localized: "Notes"), row.note)
            }
            let total = try a.totals()
            add(String(localized: "Net worth"), total.net.map(NetWorthMoney.decimal) ?? String(localized: "Unknown"))
        }
        return lines.joined(separator: "\n")
    }

    static func reconstruct(completeDocuments documents:[SyncDomainDocument]) throws -> SyncDomainProjection {
        guard documents.count<=ZIPImportLimits.production.maximumObjectCount else {throw SyncDomainCodecError.resourceLimit}
        guard Set(documents.map(\.key)).count==documents.count else {throw SyncDomainCodecError.duplicate}
        let keys=Set(documents.map(\.key))
        guard documents.allSatisfy({Set($0.dependencies).isSubset(of:keys)}) else {throw SyncDomainCodecError.dependency}
        var entries:[EntryTransfer]=[]
        var images:[ImageTransfer]=[]
        var tags:[TagTransfer]=[]
        var links:[LinkTransfer]=[]
        var habits:[HabitTransfer]=[]
        var habitLogs:[HabitLogTransfer]=[]
        var goals:[GoalTransfer]=[]
        var goalEvents:[GoalEventTransfer]=[]
        var weightRecords:[WeightRecordTransfer]=[]
        var weeklyReviews:[WeeklyReviewTransfer]=[]
        var habitPlanRevisions:[HabitPlanRevisionTransfer]=[]
        var habitLifecycleEvents:[HabitLifecycleEventTransfer]=[]
        var entrySources:[EntrySourceTransfer]=[]
        var entryPins:[EntryPinTransfer]=[]
        var entryFollowUps:[EntryFollowUpTransfer]=[]
        var todoTasks:[TodoTaskTransfer]=[]
        var todoEvents:[TodoTaskEventTransfer]=[]
        var todoLists:[TodoListTransfer]=[]
        var todoSeries:[TodoSeriesTransfer]=[]
        var todoSources:[TodoTaskSourceTransfer]=[]
        var importantDays:[ImportantDayTransfer]=[]
        var importantDayEntryLinks:[ImportantDayEntryLinkTransfer]=[]
        var importantDayTodoLinks:[ImportantDayTodoLinkTransfer]=[]
        var importantDayCovers:[ImportantDayCoverTransfer]=[]
        var sleepRecords:[SleepRecordTransfer]=[]
        var sleepGoals:[SleepGoalTransfer]=[]
        var captureReceipts:[CaptureReceiptTransfer]=[]
        var investmentParticipants:[InvestmentParticipantTransfer]=[]
        var investmentActivities:[InvestmentActivityTransfer]=[]
        var investmentSessions:[InvestmentSessionTransfer]=[]
        var investmentOperations:[InvestmentOperationTransfer]=[]
        var todoSeriesPreferences:[TodoSeriesPreferencesTransfer]=[]
        var todoReminderIntents:[TodoReminderIntentTransfer]=[]
        var bodyReferenceSettings:[BodyReferenceSettingsTransfer]=[]
        var netWorthItems:[NetWorthItemValue]=[]
        var netWorthSnapshots:[NetWorthSnapshotValue]=[]
        var configurations:[SyncHabitConfiguration]=[],metadata:[SyncHabitLogMetadata]=[]
        for document in documents {
            try Task.checkCancellation()
            switch try unpack(document) {
            case .entry(let a):entries.append(a.entry);images += try a.images.map{try $0.image()};entrySources += a.sources;entryPins += a.pins;entryFollowUps += a.followUps
            case .habit(let a):habits.append(a.habit);habitPlanRevisions += a.plans;habitLifecycleEvents += a.events;if let c=a.configuration {configurations.append(c)}
            case .habitLog(let a):habitLogs.append(a.log);if let m=a.metadata {metadata.append(m)}
            case .goal(let a):goals.append(a.goal);goalEvents += a.events
            case .todoSeries(let a),.todoTask(let a):
                if let series=a.series {todoSeries.append(series)}
                todoTasks += a.tasks;todoEvents += a.events;todoSources += a.sources;todoSeriesPreferences += a.preferences;todoReminderIntents += a.intents
            case .importantDay(let a):importantDays.append(try a.day.transfer());importantDayCovers += try a.covers.map{try $0.cover()}
            case .investmentRecord(let a):
                guard a.session.map({$0.id==a.id}) ?? true,a.operation.map({$0.id==a.id}) ?? true else {throw SyncDomainCodecError.identity}
                if let session=a.session {investmentSessions.append(session)}
                if let operation=a.operation {investmentOperations.append(try operation.transfer())}
            case .tag(let a):tags.append(a)
            case .objectLink(let a):links.append(a)
            case .weight(let a):weightRecords.append(a)
            case .weeklyReview(let a):weeklyReviews.append(a)
            case .todoList(let a):todoLists.append(a)
            case .importantDayEntryLink(let a):importantDayEntryLinks.append(a)
            case .importantDayTodoLink(let a):importantDayTodoLinks.append(a)
            case .sleepRecord(let a):sleepRecords.append(a)
            case .sleepGoal(let a):sleepGoals.append(a)
            case .captureReceipt(let a):captureReceipts.append(a)
            case .investmentParticipant(let a):investmentParticipants.append(a)
            case .investmentActivity(let a):investmentActivities.append(a)
            case .bodyReference(let a):bodyReferenceSettings.append(a)
            case .netWorthItem(let a):netWorthItems.append(a)
            case .netWorthSnapshot(let a):netWorthSnapshots.append(a)
            }
        }
        let data=TransferData(
            entries:sorted(entries,{$0.id}),
            images:sorted(images,{$0.id}),
            tags:sorted(tags,{$0.id}),
            links:sorted(links,{$0.id}),
            habits:sorted(habits,{$0.id}),
            habitLogs:sorted(habitLogs,{$0.id}),
            goals:sorted(goals,{$0.id}),
            goalEvents:sorted(goalEvents,{$0.id}),
            weightRecords:sorted(weightRecords,{$0.id}),
            weeklyReviews:sorted(weeklyReviews,{$0.id}),
            habitPlanRevisions:sorted(habitPlanRevisions,{$0.id}),
            habitLifecycleEvents:sorted(habitLifecycleEvents,{$0.id}),
            entrySources:sorted(entrySources,{$0.entryID}),
            entryPins:sorted(entryPins,{$0.id}),
            entryFollowUps:sorted(entryFollowUps,{$0.id}),
            todoTasks:sorted(todoTasks,{$0.id}),
            todoEvents:sorted(todoEvents,{$0.id}),
            todoLists:sorted(todoLists,{$0.id}),
            todoSeries:sorted(todoSeries,{$0.id}),
            todoSources:sorted(todoSources,{$0.id}),
            importantDays:sorted(importantDays,{$0.id}),
            importantDayEntryLinks:sorted(importantDayEntryLinks,{$0.id}),
            importantDayTodoLinks:sorted(importantDayTodoLinks,{$0.id}),
            importantDayCovers:sorted(importantDayCovers,{$0.id}),
            sleepRecords:sorted(sleepRecords,{$0.id}),
            sleepGoals:sorted(sleepGoals,{$0.id}),
            captureReceipts:sorted(captureReceipts,{$0.id}),
            investmentParticipants:sorted(investmentParticipants,{$0.id}),
            investmentActivities:sorted(investmentActivities,{$0.id}),
            investmentSessions:sorted(investmentSessions,{$0.id}),
            investmentOperations:sorted(investmentOperations,{$0.id}),
            todoSeriesPreferences:sorted(todoSeriesPreferences,{$0.id}),
            todoReminderIntents:sorted(todoReminderIntents,{$0.id}),
            bodyReferenceSettings:sorted(bodyReferenceSettings,{$0.id}),
            netWorthItems:sorted(netWorthItems,{$0.id}),
            netWorthSnapshots:sorted(netWorthSnapshots,{$0.id})
        )
        let supplement=SyncDomainSupplement(habitConfigurations:sorted(configurations,{$0.id}),habitLogMetadata:sorted(metadata,{$0.id}))
        // Repartitioning proves child ownership, full typed dependencies, media metadata,
        // and per-aggregate canonical ordering. No invalid child is silently dropped.
        let regenerated=try Self.documents(from:data,supplement:supplement)
        guard regenerated==documents.sorted(by:{$0.key<$1.key}) else {throw SyncDomainCodecError.malformed}
        return SyncDomainProjection(transfer:data,supplement:supplement)
    }
}
