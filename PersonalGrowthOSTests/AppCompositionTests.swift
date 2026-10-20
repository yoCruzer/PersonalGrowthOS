import XCTest
import SwiftData
import UIKit
import SwiftUI
@testable import PersonalGrowthOS

@MainActor
final class AppCompositionTests: XCTestCase {
    func testGrowthCountsAreReadOnlyAndMatchActiveDaysAndParticipantScopes() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        context.autosaveEnabled = false
        let before = try TransferSnapshot.make(context: ModelContext(container))
        let empty = try GrowthEntryCounts(context: context)
        XCTAssertEqual(empty.habits + empty.goals + empty.weightDays + empty.sleepNights + empty.activities + empty.importantDays, 0)
        XCTAssertEqual(try TransferSnapshot.make(context: ModelContext(container)), before)
        XCTAssertFalse(context.hasChanges)
        let now = Date(timeIntervalSince1970: 1792238400), zone = TimeZone(secondsFromGMT: 0)!
        context.insert(Habit(name: "Active", normalizedName: "active", createdAt: now))
        context.insert(Habit(name: "Paused", normalizedName: "paused", status: .paused, createdAt: now))
        context.insert(Goal(title: "Active", normalizedTitle: "active", createdAt: now))
        context.insert(Goal(title: "Archived", normalizedTitle: "archived", status: .archived, createdAt: now))
        for offset in [-1800.0, -1200, -86400, 86400] {
            context.insert(WeightRecord(weightKilograms: 70, recordedAt: now.addingTimeInterval(offset), createdAt: now))
        }
        let me = InvestmentParticipant(isDefault: true), other = InvestmentParticipant(name: "Other")
        context.insert(me); context.insert(other)
        let active = InvestmentActivity(participantID: me.id, name: "Reading")
        let archived = InvestmentActivity(participantID: me.id, name: "Archived"); archived.isArchived = true
        context.insert(active); context.insert(archived)
        context.insert(InvestmentActivity(participantID: other.id, name: "Other"))
        context.insert(try SleepRecord(wakeDay: "2026-10-17", timeZoneID: "Asia/Shanghai", values: .init(note: "Synthetic"), createdAt: now))
        let day = try ImportantDay(title: "Visible", rule: .init(preset: .anniversary, calendar: .gregorian, year: 2020, month: 1, day: 1))
        let hidden = try ImportantDay(title: "Archived", rule: .init(preset: .anniversary, calendar: .gregorian, year: 2020, month: 1, day: 1)); hidden.isArchived = true
        context.insert(day); context.insert(hidden); try context.save()
        let counts = try GrowthEntryCounts(context: context, now: now, zone: zone)
        XCTAssertEqual(counts.habits, 1); XCTAssertEqual(counts.goals, 1)
        XCTAssertEqual(counts.weightDays, 2); XCTAssertEqual(counts.sleepNights, 1)
        XCTAssertEqual(counts.activities, 1); XCTAssertEqual(counts.importantDays, 1)
        let snapshot = try TransferSnapshot.make(context: ModelContext(container))
        _ = try GrowthEntryCounts(context: context, now: now, zone: zone)
        XCTAssertEqual(try TransferSnapshot.make(context: ModelContext(container)), snapshot)
    }

    func testPhotoInputReverseCompletionCameraAndSaveKeepOwnedBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func photo(_ name: String, _ color: UIColor) throws -> MediaSource {
            let url = root.appendingPathComponent(name + ".png")
            try UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }.write(to: url)
            return MediaSource(url: url, originalFilename: name + ".png", contentType: "image/png")
        }
        let session = PhotoInputSession()
        let draft = CaptureDraftState()
        draft.body = "Keep complete draft"
        let a = session.begin()
        let b = session.begin()
        let bPhoto = try photo("B", .blue)
        let bBytes = try Data(contentsOf: bPhoto.url)
        if session.finish(b, sources: [bPhoto], replacing: true) { draft.finishImageLoad(with: .success([bPhoto])) }
        let aPhoto = try photo("A", .red)
        XCTAssertFalse(session.finish(a, sources: [aPhoto], replacing: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aPhoto.url.path))
        XCTAssertEqual(draft.imageSources.map(\.url), [bPhoto.url])
        XCTAssertEqual(try Data(contentsOf: bPhoto.url), bBytes)

        let slow = session.begin()
        let camera = session.begin()
        let cPhoto = try photo("Camera", .green)
        let cBytes = try Data(contentsOf: cPhoto.url)
        if session.finish(camera, sources: [cPhoto], replacing: false) { draft.appendCameraImage(cPhoto) }
        let late = try photo("Late", .red)
        XCTAssertFalse(session.finish(slow, sources: [late], replacing: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.url.path))
        XCTAssertEqual(draft.body, "Keep complete draft")
        XCTAssertEqual(draft.imageSources.map(\.url), [bPhoto.url, cPhoto.url])
        XCTAssertEqual(try Data(contentsOf: cPhoto.url), cBytes)

        let container = try PersistenceContainerFactory.makeInMemory()
        let media = MediaStore(rootURL: root.appendingPathComponent("Saved"), availableCapacity: { .max })
        let entry = try EntryCreationService(persistence: ModelContextEntryPersistence(context: container.mainContext), mediaStore: media)
            .create(EntryCreationDraft(body: draft.body, images: draft.imageSources))
        let beforeReset = session.begin()
        session.end()
        draft.reset()
        let resetLate = try photo("AfterReset", .red)
        XCTAssertFalse(session.finish(beforeReset, sources: [resetLate], replacing: true))
        XCTAssertFalse(session.finish(camera, sources: [cPhoto], replacing: false), "Duplicate completion cannot reclaim an accepted result")
        XCTAssertTrue(draft.imageSources.isEmpty)
        XCTAssertEqual(draft.body, "")
        XCTAssertFalse(session.isLoading)
        XCTAssertEqual(entry.body, "Keep complete draft")
        XCTAssertEqual(entry.images.count, 2)
        let images = entry.images.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: images[0].relativePath)), bBytes)
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: images[1].relativePath)), cBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resetLate.url.path))
        let editing = PhotoInputSession()
        let editOne = editing.begin()
        let addedOne = try photo("EditOne", .yellow)
        XCTAssertTrue(editing.finish(editOne, sources: [addedOne], replacing: false))
        let editTwo = editing.begin()
        let addedTwo = try photo("EditTwo", .purple)
        XCTAssertTrue(editing.finish(editTwo, sources: [addedTwo], replacing: false))
        let addedBytes = try [addedOne, addedTwo].map { try Data(contentsOf: $0.url) }
        try EntryEditingService(persistence: ModelContextEntryPersistence(context: container.mainContext), mediaStore: media)
            .update(entry, with: EntryEditingDraft(title: entry.title, body: entry.body, occurredAt: entry.occurredAt,
                retainedImageIDs: images.map(\.id), addedImages: [addedOne, addedTwo]))
        editing.end()
        XCTAssertEqual(entry.images.count, 4)
        let allImages = entry.images.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(try allImages.map { try Data(contentsOf: media.fileURL(for: $0.relativePath)) }, [bBytes, cBytes] + addedBytes)
        let cancelledEdit = editing.begin()
        editing.end()
        let cancelledPhoto = try photo("CancelledEdit", .red)
        XCTAssertFalse(editing.finish(cancelledEdit, sources: [cancelledPhoto], replacing: false))
        XCTAssertEqual(try allImages.map { try Data(contentsOf: media.fileURL(for: $0.relativePath)) }, [bBytes, cBytes] + addedBytes)
    }

    func testTrackedPhotoTaskCancellationStillRejectsUncooperativeCompletion() async throws {
        let session = PhotoInputSession()
        let old = session.begin()
        let started = expectation(description: "Old input is suspended")
        var release: CheckedContinuation<Void, Never>?
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task {
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            XCTAssertTrue(Task.isCancelled)
            // Deliberately ignores cancellation, just like a late provider callback can.
            try! Data("old task bytes".utf8).write(to: url)
            XCTAssertFalse(session.finish(old, sources: [MediaSource(url: url, originalFilename: "old", contentType: "image/png")], replacing: true))
        }
        session.track(task, for: old)
        await fulfillment(of: [started], timeout: 5)
        let newer = session.begin()
        release?.resume()
        await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(session.isLoading)
        XCTAssertTrue(session.finish(newer, sources: [], replacing: false))
        XCTAssertFalse(session.isLoading)
    }

    func testPhotoInputCloseReentryAndAppendDoNotClearNewLoadingOrFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func photo(_ name: String) throws -> MediaSource {
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return MediaSource(url: url, originalFilename: name, contentType: "image/png")
        }
        let session = PhotoInputSession()
        let old = session.begin()
        session.end()
        let current = session.begin()
        let rejected = try photo("rejected")
        XCTAssertFalse(session.finish(old, sources: [rejected], replacing: false))
        XCTAssertTrue(session.isLoading, "An old completion cannot clear the new operation's spinner")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.url.path))
        let first = try photo("first")
        XCTAssertTrue(session.finish(current, sources: [first], replacing: false))
        let next = session.begin()
        let second = try photo("second")
        XCTAssertTrue(session.finish(next, sources: [second], replacing: false))
        XCTAssertEqual(try Data(contentsOf: first.url), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second.url), Data("second".utf8))
        let cancelled = session.begin()
        session.cancel(cancelled)
        XCTAssertFalse(session.finish(cancelled, sources: [], replacing: false))
        XCTAssertEqual(try Data(contentsOf: first.url), Data("first".utf8))
        session.end()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.url.path))
    }

    func testCameraCancellationLateDataAndDuplicateCompletionAreOnceOnly() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in }
        var sources: [MediaSource] = []
        var cancellations = 0
        let cancelled = CameraViewController(completion: { result in
            if case .success(let source) = result { sources.append(source) }
        }, cancellation: { cancellations += 1 })
        cancelled.cancel()
        cancelled.cancel()
        cancelled.receivePhotoData(.success(data))
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(sources.isEmpty)
        let reopened = CameraViewController(completion: { result in
            if case .success(let source) = result { sources.append(source) }
        }, cancellation: { cancellations += 1 })
        reopened.receivePhotoData(.success(data))
        let source = try XCTUnwrap(sources.first)
        defer { try? FileManager.default.removeItem(at: source.url) }
        reopened.receivePhotoData(.success(data))
        reopened.cancel()
        cancelled.receivePhotoData(.success(data))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(try Data(contentsOf: source.url), data)
    }

    func testDefaultInputsSelectStandardMode() {
        let configuration = AppConfiguration.resolve(arguments: [], environment: [:])

        XCTAssertEqual(configuration.launchMode, .standard)
        XCTAssertFalse(configuration.resetDataOnLaunch)
    }

    func testLaunchArgumentSelectsUITestingMode() {
        let configuration = AppConfiguration.resolve(
            arguments: [AppConfiguration.uiTestingLaunchArgument],
            environment: [:]
        )

        XCTAssertEqual(configuration.launchMode, .uiTesting)
    }

    func testEnvironmentSelectsUITestingMode() {
        let configuration = AppConfiguration.resolve(
            arguments: [],
            environment: [AppConfiguration.uiTestingEnvironmentKey: "1"]
        )

        XCTAssertEqual(configuration.launchMode, .uiTesting)
    }

    func testUnrecognizedInputsKeepStandardMode() {
        let configuration = AppConfiguration.resolve(
            arguments: ["-UnrelatedArgument"],
            environment: [AppConfiguration.uiTestingEnvironmentKey: "true"]
        )

        XCTAssertEqual(configuration.launchMode, .standard)
    }

    func testResetIsAcceptedOnlyForUITestingLaunch() {
        let standard = AppConfiguration.resolve(
            arguments: [AppConfiguration.resetDataLaunchArgument],
            environment: [:]
        )
        let testing = AppConfiguration.resolve(
            arguments: [
                AppConfiguration.uiTestingLaunchArgument,
                AppConfiguration.resetDataLaunchArgument
            ],
            environment: [:]
        )

        XCTAssertFalse(standard.resetDataOnLaunch)
        XCTAssertTrue(testing.resetDataOnLaunch)
    }

    func testContainerRetainsResolvedConfiguration() {
        let configuration = AppConfiguration.resolve(
            arguments: [AppConfiguration.uiTestingLaunchArgument],
            environment: [:]
        )

        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-Composition-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let container = try! AppContainer(
            configuration: configuration,
            modelContainer: PersistenceContainerFactory.makeInMemory(),
            mediaStore: MediaStore(rootURL: fixtureURL, availableCapacity: { .max })
        )

        XCTAssertEqual(container.configuration, configuration)
    }

    func testCaptureFailurePreservesTextAndExistingSelection() {
        struct InjectedFailure: Error {}

        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-Draft-\(UUID().uuidString).jpg")
        let source = MediaSource(
            url: fixtureURL,
            originalFilename: "memory.jpg",
            contentType: "image/jpeg"
        )
        let draft = CaptureDraftState()
        draft.body = "Keep my words"
        draft.finishImageLoad(with: .success([source]))

        draft.beginImageLoad()
        draft.finishImageLoad(with: .failure(InjectedFailure()))

        XCTAssertEqual(draft.body, "Keep my words")
        XCTAssertEqual(draft.imageSources.first?.url, source.url)
        XCTAssertNotNil(draft.errorMessage)
    }

    func testCriticalEnglishAndSimplifiedChineseLocalizationsAreAvailable() throws {
        let englishPath = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj")
        )
        let chinesePath = try XCTUnwrap(
            Bundle.main.path(forResource: "zh-Hans", ofType: "lproj")
        )
        let english = try XCTUnwrap(Bundle(path: englishPath))
        let chinese = try XCTUnwrap(Bundle(path: chinesePath))
        let expected: [(String, String, String)] = [
            ("Today", "Today", "今天"),
            ("Timeline", "Timeline", "时间线"),
            ("Growth", "Growth", "成长"),
            ("Library", "Library", "资料库"),
            ("Quick Capture", "Quick Capture", "快速记录"),
            ("Settings", "Settings", "设置"),
            ("Once per day", "Once per day", "每天一次"),
            ("Multiple times per day", "Multiple times per day", "每天多次"),
            ("Goal", "Goal", "目标"),
            ("Flag", "Flag", "标记"),
            ("Create Your First Tag", "Create Your First Tag", "创建你的第一个标签")
        ]

        for (key, englishValue, chineseValue) in expected {
            XCTAssertEqual(
                english.localizedString(forKey: key, value: nil, table: nil),
                englishValue
            )
            XCTAssertEqual(
                chinese.localizedString(forKey: key, value: nil, table: nil),
                chineseValue
            )
        }
    }

    func testDailyReminderUsesOnlyClampedLocalHourAndMinute() {
        XCTAssertEqual(
            ReminderScheduleCalculator.dailyComponents(minutesAfterMidnight: 8 * 60 + 35),
            DateComponents(hour: 8, minute: 35)
        )
        XCTAssertEqual(
            ReminderScheduleCalculator.dailyComponents(minutesAfterMidnight: -1),
            DateComponents(hour: 0, minute: 0)
        )
        XCTAssertEqual(
            ReminderScheduleCalculator.dailyComponents(minutesAfterMidnight: 2_000),
            DateComponents(hour: 23, minute: 59)
        )
    }

    func testWeeklyReminderUsesStableWeekdayHourAndMinute() {
        XCTAssertEqual(
            ReminderScheduleCalculator.weeklyComponents(
                weekday: 2,
                minutesAfterMidnight: 19 * 60 + 15
            ),
            DateComponents(hour: 19, minute: 15, weekday: 2)
        )
        XCTAssertEqual(
            ReminderScheduleCalculator.weeklyComponents(
                weekday: 9,
                minutesAfterMidnight: 60
            ).weekday,
            7
        )
        XCTAssertEqual(
            LocalReminderScheduler.dailyIdentifier,
            "com.yocruzer.PersonalGrowthOS.reminder.daily-recording"
        )
        XCTAssertEqual(
            LocalReminderScheduler.weeklyIdentifier,
            "com.yocruzer.PersonalGrowthOS.reminder.weekly-review"
        )
        XCTAssertNotEqual(
            LocalReminderScheduler.dailyIdentifier,
            LocalReminderScheduler.weeklyIdentifier
        )
    }
}

extension AppCompositionTests {
    func testBuild9VersionUsesBundleFieldsAndHonestMissingValues() {
        let info = AppVersionInformation(info: ["CFBundleDisplayName": "随心log", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "42"], localizedInfo: [:])
        XCTAssertEqual(info.displayText, "随心log 1.2 (Build 42)")
        let missing = AppVersionInformation(info: [:], localizedInfo: [:])
        XCTAssertEqual(missing.version, String(localized: "Unknown"))
        XCTAssertEqual(missing.build, String(localized: "Unknown"))
    }
}


extension AppCompositionTests {
    func testBuildProvenanceKeepsBundleVersionSeparateAndCopiesFullSHA() {
        let sha = String(repeating: "a1", count: 20)
        let version = AppVersionInformation(info: ["CFBundleName": "App", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"], localizedInfo: [:])
        let value = BuildProvenance(values: ["Commit": sha, "Source": "xcodeCloud", "Tag": "release/1.0", "Dirty": false])
        XCTAssertEqual(value.shortCommit, String(sha.prefix(9)))
        XCTAssertEqual(value.commit, sha)
        XCTAssertEqual(value.tag, "release/1.0")
        XCTAssertTrue(value.copyText(version: version).contains("Build 12"))
        XCTAssertTrue(value.copyText(version: version).contains(sha))
        XCTAssertEqual(BuildProvenance(values: [:]).commit, nil)
        XCTAssertEqual(BuildProvenance(values: ["Commit": "not-a-sha"]).commit, nil)
        XCTAssertNil(BuildProvenance(values: ["Commit": sha, "Source": "localGit", "Tag": "branch"]).tag)
        XCTAssertTrue(BuildProvenance(values: ["Commit": sha, "Source": "localGit", "Dirty": true]).isDirty)
    }
    func testCompiledAppContainsGeneratedProvenanceResource() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BuildProvenance", withExtension: "plist"))
        let bytes = try Data(contentsOf: url)
        let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
        let loaded = BuildProvenance()
        XCTAssertEqual(loaded.commit, values["Commit"] as? String)
        XCTAssertEqual(loaded.commit?.count, 40)
        XCTAssertEqual(loaded.source, "localGit")
    }
}


@MainActor @Observable private final class SystemGrowthTabSelection {var tab=0}
@MainActor private struct SystemGrowthMountedTabs:View {
    @Bindable var selection:SystemGrowthTabSelection
    let media:MediaStore
    let thumbnail:ThumbnailStore
    let now:Date
    let zone:TimeZone
    var body:some View {
        TabView(selection:$selection.tab) {
            NavigationStack {GrowthView(mediaStore:media,thumbnailStore:thumbnail,countClock:{(now,zone)})}.tabItem {Text("Growth")}.tag(0)
            Text("Other tab").tabItem {Text("Other")}.tag(1)
        }
    }
}

@MainActor extension AppCompositionTests {
    func testSystemBV01MountedGrowthActualReadsOnInvestmentSavesVisibleAndHiddenProbe() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let c=try PersistenceContainerFactory.makeOnDisk(at:root.appendingPathComponent("growth.sqlite")),context=c.mainContext
        let zone=TimeZone(identifier:"America/Los_Angeles")!
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let now=calendar.date(from:DateComponents(year:2026,month:10,day:19,hour:0,minute:30))!
        let oldDays=Set((0..<10_000).map {ImportantCivilDay(now.addingTimeInterval(-Double($0)*86400),timeZone:zone).identifier})
        XCTAssertEqual(oldDays.count,9973,"Original absolute-seconds fixture collides across DST")
        let days=(0..<10_000).map {calendar.date(byAdding:.day,value:-$0,to:now)!}
        XCTAssertEqual(Set(days.map {ImportantCivilDay($0,timeZone:zone).identifier}).count,10_000)
        for stamp in days {
            context.insert(WeightRecord(weightKilograms:70,recordedAt:stamp,createdAt:stamp))
            context.insert(try SleepRecord(wakeDay:ImportantCivilDay(stamp,timeZone:zone).identifier,timeZoneID:zone.identifier,values:.init(note:"Synthetic"),createdAt:stamp))
        }
        try context.save()
        var clock=InvestmentClock.current();clock.wall=now
        let service=InvestmentService(context:context,clock:{clock})
        let activity=try service.createActivity(name:"Mounted Growth probe")
        let participant=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentParticipant>()).first).id,timer=UUID()
        try service.start(activityID:activity,participantID:participant,operationID:timer)
        let media=MediaStore(rootURL:root),selection=SystemGrowthTabSelection()
        let thumbnail=ThumbnailStore(rootURL:root.appendingPathComponent("Thumbnails"),mediaStore:media)
        let mounted=expectation(description:"Production Growth onAppear read completed")
        GrowthCountReadProbe.reads=[];GrowthCountReadProbe.didRead={mounted.fulfill()}
        let window=UIWindow(frame:UIScreen.main.bounds)
        let host=UIHostingController(rootView:SystemGrowthMountedTabs(selection:selection,media:media,thumbnail:thumbnail,now:now,zone:zone).modelContainer(c))
        window.rootViewController=host;window.makeKeyAndVisible();host.view.layoutIfNeeded()
        defer {GrowthCountReadProbe.didRead=nil;window.isHidden=true;window.rootViewController=nil}
        await fulfillment(of:[mounted],timeout:5)
        GrowthCountReadProbe.didRead=nil
        func settle() async {let done=expectation(description:"Drain main RunLoop delivery");DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {done.fulfill()};await fulfillment(of:[done],timeout:3)}
        await settle()
        for visible in [true,false] {
            if !visible {selection.tab=1;await settle()}
            GrowthCountReadProbe.reads=[]
            _ = try service.storeDraft(id:UUID(),participantID:participant,activityID:activity,values:.init(day:ImportantCivilDay(now).identifier,timeZoneID:zone.identifier,seconds:60,evidence:.dateDuration,source:.manual),durationText:"1",editingSessionID:nil,editingRevision:nil,expectedRevision:nil,timerConfirmation:false)
            clock.wall=clock.wall.addingTimeInterval(1);clock.uptime += 1
            let workspace=InvestmentWorkspace();workspace.checkpoint(context,clock:{clock})
            var probe=false;Task { @MainActor in probe=true };await settle()
            let actual=GrowthCountReadProbe.reads
            print("PGOS_BV01 visible=\(visible) actualFetches=\(actual.count) weightModels=\(actual.reduce(0){$0+$1.0}) sleepModels=\(actual.reduce(0){$0+$1.1}) mainProbe=\(probe)")
            XCTAssertTrue(probe)
            XCTAssertTrue(actual.isEmpty,"Identified Investment operation writes must not re-fetch Weight or Sleep")
        }
        let weightService=WeightRecordService(context:context)
        let record=try weightService.create(weightKilograms:72.345,recordedAt:calendar.date(byAdding:.day,value:-10010,to:now)!)
        await settle();XCTAssertEqual(GrowthCountReadProbe.last?.weightDays,10001)
        try weightService.delete(record);await settle();XCTAssertEqual(GrowthCountReadProbe.last?.weightDays,10000)
        _ = try service.createActivity(name:"Metadata refresh")
        await settle();XCTAssertEqual(GrowthCountReadProbe.last?.activities,2)
        XCTAssertTrue(GrowthEntryCounts.needsRefresh(Notification(name:ModelContext.didSave)))
        XCTAssertTrue(GrowthEntryCounts.needsRefresh(Notification(name:ModelContext.didSave,userInfo:[ModelContext.NotificationKey.invalidatedAllIdentifiers:true])))
        let op=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<InvestmentOperation>()).first)
        XCTAssertTrue(GrowthEntryCounts.needsRefresh(Notification(name:ModelContext.didSave,userInfo:[ModelContext.NotificationKey.invalidatedAllIdentifiers:[record.persistentModelID],ModelContext.NotificationKey.updatedIdentifiers:[op.persistentModelID]])))
    }
}

@MainActor @Observable private final class IntegrationSettingsPresentation {
    var shown=true
    var didOpen:(() -> Void)?
    var didClose:(() -> Void)?
}
@MainActor private struct IntegrationSettingsMountedHost:View {
    @Bindable var presentation:IntegrationSettingsPresentation
    let intents:ReminderSettingsIntents
    let media:MediaStore
    let exporter:ImportExportService
    let scheduler:LocalReminderScheduler
    var body:some View {
        Color.clear.sheet(isPresented:$presentation.shown,onDismiss:{presentation.didClose?()}) {
            MediaStorageView(mediaStore:media,importExportService:exporter,integrityReport:.init(),reminderSettingsIntents:intents,reminderScheduler:scheduler)
                .onAppear {presentation.didOpen?()}
        }
    }
}
@MainActor extension AppCompositionTests {
    func testIntegrationIR03ActualSettingsSheetCloseReopenSameValueIntent() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let c=try PersistenceContainerFactory.makeInMemory(),media=MediaStore(rootURL:root)
        let exporter=ImportExportService(context:c.mainContext,mediaStore:media)
        let keys=["dailyRecordingReminderEnabled","dailyRecordingReminderMinutes","weeklyReviewReminderEnabled"]
        let prior=keys.map {UserDefaults.standard.object(forKey:$0)}
        let defaults=UserDefaults.standard
        defaults.set(false,forKey:keys[0]);defaults.set(480,forKey:keys[1]);defaults.set(false,forKey:keys[2])
        let intents=ReminderSettingsIntents(),presentation=IntegrationSettingsPresentation(),client=SystemSettingsLateClient()
        let entered=expectation(description:"A entered actual settings scheduler");client.entered=entered
        let firstOpen=expectation(description:"Settings A mounted");presentation.didOpen={presentation.didOpen=nil;firstOpen.fulfill()}
        let window=UIWindow(frame:UIScreen.main.bounds)
        let host=UIHostingController(rootView:IntegrationSettingsMountedHost(presentation:presentation,intents:intents,media:media,exporter:exporter,scheduler:LocalReminderScheduler(client:client)))
        window.rootViewController=host;window.makeKeyAndVisible()
        defer {
            ReminderSettingsUpdateProbe.didSubmit=nil
            presentation.didOpen=nil;presentation.didClose=nil
            window.isHidden=true;window.rootViewController=nil
            client.continuation?.resume(throwing:CancellationError());client.continuation=nil
            for (key,value) in zip(keys,prior) {if let value {defaults.set(value,forKey:key)} else {defaults.removeObject(forKey:key)}}
        }
        await fulfillment(of:[firstOpen],timeout:4)
        defaults.set(true,forKey:keys[0])
        await fulfillment(of:[entered],timeout:4)
        let old=try XCTUnwrap(intents.daily.task)
        let closed=expectation(description:"A sheet actually dismissed");presentation.didClose={presentation.didClose=nil;closed.fulfill()}
        presentation.shown=false
        await fulfillment(of:[closed],timeout:4)
        let secondOpen=expectation(description:"Settings B recreated");presentation.didOpen={presentation.didOpen=nil;secondOpen.fulfill()};presentation.shown=true
        await fulfillment(of:[secondOpen],timeout:4)
        let off=expectation(description:"B off submitted through actual onChange")
        ReminderSettingsUpdateProbe.didSubmit={scope in if scope === intents.daily {off.fulfill()}}
        defaults.set(false,forKey:keys[0]);await fulfillment(of:[off],timeout:4)
        let on=expectation(description:"B same-value on submitted")
        ReminderSettingsUpdateProbe.didSubmit={scope in if scope === intents.daily {on.fulfill()}}
        defaults.set(true,forKey:keys[0]);await fulfillment(of:[on],timeout:4)
        ReminderSettingsUpdateProbe.didSubmit=nil
        let latest=try XCTUnwrap(intents.daily.task)
        let continuation=try XCTUnwrap(client.continuation);client.continuation=nil
        continuation.resume(throwing:CocoaError(.fileWriteUnknown))
        await old.value;await latest.value
        XCTAssertTrue(defaults.bool(forKey:keys[0]))
        XCTAssertEqual(client.pending[LocalReminderScheduler.dailyIdentifier]?.hour,8)
        print("PGOS_IR03 actualSheetClosed=true recreated=true sameValueIntent=true oldErrorRejected=true")
    }
}

@MainActor extension AppCompositionTests {
    func testTerminalIC02ActualClosedSettingsCurrentFailureRemovesOldRequest() async throws {
        for weekly in [false,true] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let c=try PersistenceContainerFactory.makeInMemory(),media=MediaStore(rootURL:root)
            let keys=["dailyRecordingReminderEnabled","dailyRecordingReminderMinutes","weeklyReviewReminderEnabled","weeklyReviewReminderMinutes","weeklyReviewReminderWeekday"]
            let defaults=UserDefaults.standard,prior=keys.map {UserDefaults.standard.object(forKey:$0)}
            defaults.set(!weekly,forKey:keys[0]);defaults.set(480,forKey:keys[1]);defaults.set(weekly,forKey:keys[2]);defaults.set(480,forKey:keys[3]);defaults.set(2,forKey:keys[4])
            let client=SystemSettingsLateClient();client.suspendFirst=false
            let scheduler=LocalReminderScheduler(client:client)
            if weekly {_ = try await scheduler.updateWeekly(enabled:true,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
            else {_ = try await scheduler.updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)}
            let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
            XCTAssertEqual(client.pending[id]?.hour,8,"Legal old native request really exists before modification")
            client.suspendFirst=true
            let intents=ReminderSettingsIntents(),presentation=IntegrationSettingsPresentation()
            let entered=expectation(description:"Changed setting entered real scheduler");client.entered=entered
            let opened=expectation(description:"Actual settings opened");presentation.didOpen={presentation.didOpen=nil;opened.fulfill()}
            let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
            let window=UIWindow(windowScene:scene);window.frame=UIScreen.main.bounds
            window.windowLevel = .normal + 1
            let host=UIHostingController(rootView:IntegrationSettingsMountedHost(presentation:presentation,intents:intents,media:media,exporter:ImportExportService(context:c.mainContext,mediaStore:media),scheduler:scheduler))
            window.rootViewController=host;window.makeKeyAndVisible()
            defer {
                presentation.didOpen=nil;presentation.didClose=nil;window.isHidden=true;window.rootViewController=nil
                client.continuation?.resume(throwing:CancellationError());client.continuation=nil
                for (key,value) in zip(keys,prior) {if let value {defaults.set(value,forKey:key)} else {defaults.removeObject(forKey:key)}}
            }
            await fulfillment(of:[opened],timeout:4)
            defaults.set(540,forKey:weekly ? keys[3]:keys[1]);await fulfillment(of:[entered],timeout:4)
            let scope=weekly ? intents.weekly:intents.daily,old=try XCTUnwrap((weekly ? intents.weekly:intents.daily).task)
            let closed=expectation(description:"Actual settings fully removed");presentation.didClose={presentation.didClose=nil;closed.fulfill()};presentation.shown=false
            await fulfillment(of:[closed],timeout:4)
            XCTAssertTrue(scope.task == nil || !old.isCancelled,"Closing alone must not cancel a legal command")
            let release=try XCTUnwrap(client.continuation);client.continuation=nil;release.resume(throwing:CocoaError(.fileWriteUnknown))
            await old.value
            try await Task.sleep(for:.milliseconds(150))
            XCTAssertFalse(defaults.bool(forKey:weekly ? keys[2]:keys[0]))
            XCTAssertNil(client.pending[id],"Current failure after actual removal must finish system cleanup without removed View.onChange")
            let reopened=expectation(description:"Reopen failed setting");presentation.didOpen={presentation.didOpen=nil;reopened.fulfill()};presentation.shown=true
            await fulfillment(of:[reopened],timeout:4)
            try await Task.sleep(for:.milliseconds(150))
            XCTAssertFalse(defaults.bool(forKey:weekly ? keys[2]:keys[0]));XCTAssertNil(client.pending[id])
            XCTAssertEqual(scope.failureMessage,String(localized:"The reminder could not be updated. Please try again."))
            XCTAssertFalse(scope.cleanupPending)
            window.layoutIfNeeded()
            let shot=UIGraphicsImageRenderer(bounds:window.bounds).image {renderer in window.layer.render(in:renderer.cgContext)}
            let attachment=XCTAttachment(image:shot);attachment.name="Terminal-IC02-reopened-\(weekly ? "weekly":"daily")-failure";attachment.lifetime = .keepAlways;add(attachment)
            print("PGOS_IC02 weekly=\(weekly) old08=true changed09=true actualClosed=true noB=true errorSettled=true pending=\(client.pending.count)")
        }
    }
}

@MainActor extension AppCompositionTests {
    func testRecheckTC02EntireAppRootDestroyedColdStartReconcilesOffRequests() async throws {
        for weekly in [false,true] {
          for coldBranch in 0..<3 { // native still present / already absent / first cold cleanup fails
            let suite="TC02-root-\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
            defer {defaults.removePersistentDomain(forName:suite)}
            let enabledKey=weekly ? "weeklyReviewReminderEnabled":"dailyRecordingReminderEnabled"
            let timeKey=weekly ? "weeklyReviewReminderMinutes":"dailyRecordingReminderMinutes"
            defaults.set(true,forKey:enabledKey);defaults.set(480,forKey:timeKey);defaults.set(2,forKey:"weeklyReviewReminderWeekday")
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let c=try PersistenceContainerFactory.makeInMemory()
            let container=AppContainer(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),modelContainer:c,mediaStore:MediaStore(rootURL:root))
            let client=SystemSettingsLateClient();client.suspendFirst=false
            let scheduler=LocalReminderScheduler(client:client)
            if weekly {_ = try await scheduler.updateWeekly(enabled:true,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
            else {_ = try await scheduler.updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)}
            let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
            XCTAssertNotNil(client.pending[id]);client.failedRemoval=true;client.suspendFirst=true
            let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
            weak var oldDaily:ReminderSettingsUpdate.Scope?,oldWeekly:ReminderSettingsUpdate.Scope?
            var window:UIWindow?=UIWindow(windowScene:scene);window!.frame=UIScreen.main.bounds;window!.windowLevel = .normal + 1
            var host:UIHostingController<AnyView>?
            let mounted=expectation(description:"First actual AppShell root mounted")
            ReminderSettingsUpdateProbe.didMountRoot={intents,open in oldDaily=intents.daily;oldWeekly=intents.weekly;open();mounted.fulfill()}
            host=UIHostingController(rootView:AnyView(AppShell(container:container,settingsReminderScheduler:scheduler).modelContainer(c).defaultAppStorage(defaults)))
            window!.rootViewController=host;window!.makeKeyAndVisible()
            defer {ReminderSettingsUpdateProbe.didMountSettings=nil;ReminderSettingsUpdateProbe.didMountRoot=nil;window?.isHidden=true;window?.rootViewController=nil;host=nil;window=nil}
            await fulfillment(of:[mounted],timeout:4);ReminderSettingsUpdateProbe.didMountRoot=nil
            try await Task.sleep(for:.milliseconds(400))
            let entered=expectation(description:"Actual settings changed08to09 enters client");client.entered=entered
            defaults.set(540,forKey:timeKey);await fulfillment(of:[entered],timeout:4)
            let release=try XCTUnwrap(client.continuation);client.continuation=nil;release.resume(throwing:CocoaError(.fileWriteUnknown))
            await (weekly ? oldWeekly:oldDaily)?.task?.value
            try await Task.sleep(for:.milliseconds(300))
            await (weekly ? oldWeekly:oldDaily)?.task?.value
            XCTAssertFalse(defaults.bool(forKey:enabledKey));XCTAssertNotNil(client.pending[id])
            XCTAssertTrue((weekly ? oldWeekly:oldDaily)?.cleanupPending == true)
            window?.isHidden=true;window?.rootViewController=nil;host=nil;window=nil
            for _ in 0..<50 {if oldDaily == nil && oldWeekly == nil {break};try await Task.sleep(for:.milliseconds(20))}
            XCTAssertNil(oldDaily,"Entire original root daily Scope must really deallocate")
            XCTAssertNil(oldWeekly,"Entire original root weekly Scope must really deallocate")
            if coldBranch == 1 {client.pending.removeValue(forKey:id)}
            client.failedRemoval=coldBranch == 2
            client.status=coldBranch == 1 ? .notDetermined:.denied
            var retry:(@MainActor () -> Void)?
            ReminderSettingsUpdateProbe.didMountSettings={daily,week in retry=weekly ? week:daily}
            let coldMounted=expectation(description:"Brand new AppShell root mounted")
            weak var coldScope:ReminderSettingsUpdate.Scope?
            ReminderSettingsUpdateProbe.didMountRoot={intents,open in coldScope=weekly ? intents.weekly:intents.daily;if coldBranch == 2 {open()};coldMounted.fulfill()}
            window=UIWindow(windowScene:scene);window!.frame=UIScreen.main.bounds;window!.windowLevel = .normal + 1
            host=UIHostingController(rootView:AnyView(AppShell(container:container,settingsReminderScheduler:scheduler).modelContainer(c).defaultAppStorage(defaults)))
            window!.rootViewController=host;window!.makeKeyAndVisible()
            await fulfillment(of:[coldMounted],timeout:4);ReminderSettingsUpdateProbe.didMountRoot=nil
            for _ in 0..<100 {if coldScope?.task != nil {break};try await Task.sleep(for:.milliseconds(20))}
            await coldScope?.task?.value
            if coldBranch == 2 {
                XCTAssertNotNil(client.pending[id]);XCTAssertTrue(coldScope?.cleanupPending ?? false)
                XCTAssertEqual(coldScope?.failureMessage,String(localized:"Reminder removal is not confirmed. Please try again."))
                for _ in 0..<100 {if retry != nil {break};try await Task.sleep(for:.milliseconds(20))}
                window!.layoutIfNeeded()
                let before=UIGraphicsImageRenderer(bounds:window!.bounds).image {window!.layer.render(in:$0.cgContext)}
                let failed=XCTAttachment(image:before);failed.name="TC02-cold-\(weekly ? "weekly":"daily")-unconfirmed";failed.lifetime = .keepAlways;add(failed)
                client.failedRemoval=false
                try XCTUnwrap(retry)()
                await coldScope?.task?.value
                try await Task.sleep(for:.milliseconds(150))
                window!.layoutIfNeeded()
                let after=UIGraphicsImageRenderer(bounds:window!.bounds).image {window!.layer.render(in:$0.cgContext)}
                let confirmed=XCTAttachment(image:after);confirmed.name="TC03-cold-\(weekly ? "weekly":"daily")-confirmed";confirmed.lifetime = .keepAlways;add(confirmed)
            }
            retry=nil;ReminderSettingsUpdateProbe.didMountSettings=nil
            XCTAssertEqual(client.authorizationRequests,0,"Off reconciliation never requests permission")
            XCTAssertNil(client.pending[id],"TC-02: persistent off must recover cleanup after all original owners have died")
            XCTAssertFalse(defaults.bool(forKey:enabledKey));XCTAssertFalse(coldScope?.cleanupPending ?? true)
            XCTAssertNil(coldScope?.failureMessage)
            print("PGOS_TC02 weekly=\(weekly) wholeRootDestroyed=\(oldDaily == nil && oldWeekly == nil) coldBranch=\(coldBranch) newRoot=true persistentOff=\(!defaults.bool(forKey:enabledKey)) native=\(client.pending.count)")
          }
        }
    }
}

@MainActor extension AppCompositionTests {
    func testRecheckTC02ActualColdRootQueryProtectsSettingsNewIntent() async throws {
        for weekly in [false,true] {
            for newer in 0..<3 {
                let suite="TC02-B-\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
                defer {defaults.removePersistentDomain(forName:suite)}
                let key=weekly ? "weeklyReviewReminderEnabled":"dailyRecordingReminderEnabled"
                let time=weekly ? "weeklyReviewReminderMinutes":"dailyRecordingReminderMinutes"
                let otherKey=weekly ? "dailyRecordingReminderEnabled":"weeklyReviewReminderEnabled"
                defaults.set(false,forKey:key);defaults.set(true,forKey:otherKey);defaults.set(480,forKey:time)
                let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                defer {try? FileManager.default.removeItem(at:root)}
                let c=try PersistenceContainerFactory.makeInMemory()
                let container=AppContainer(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),modelContainer:c,mediaStore:MediaStore(rootURL:root))
                let client=SystemSettingsLateClient();client.suspendFirst=false
                let scheduler=LocalReminderScheduler(client:client)
                if weekly {_ = try await scheduler.updateWeekly(enabled:true,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
                else {_ = try await scheduler.updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)}
                let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                let other=weekly ? LocalReminderScheduler.dailyIdentifier:LocalReminderScheduler.weeklyIdentifier
                for key in [other,"unknown.synthetic","sleep.synthetic","important-day.synthetic","todo.synthetic"] {client.pending[key]=DateComponents(hour:7)}
                let preserved=client.pending.filter {$0.key != id}
                let queried=expectation(description:"Actual cold AppShell cleanup held in native query")
                var release:CheckedContinuation<Void,Never>?
                client.pendingHook={client.pendingHook=nil;await withCheckedContinuation {release=$0;queried.fulfill()}}
                var scope:ReminderSettingsUpdate.Scope?
                ReminderSettingsUpdateProbe.didMountRoot={intents,open in scope=weekly ? intents.weekly:intents.daily;open()}
                let settingsMounted=expectation(description:"Actual root settings mounted during startup query")
                ReminderSettingsUpdateProbe.didMountSettings={_,_ in ReminderSettingsUpdateProbe.didMountSettings=nil;settingsMounted.fulfill()}
                let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
                let window=UIWindow(windowScene:scene);window.frame=UIScreen.main.bounds;window.windowLevel = .normal + 1
                window.rootViewController=UIHostingController(rootView:AppShell(container:container,settingsReminderScheduler:scheduler).modelContainer(c).defaultAppStorage(defaults));window.makeKeyAndVisible()
                defer {ReminderSettingsUpdateProbe.didMountRoot=nil;ReminderSettingsUpdateProbe.didMountSettings=nil;ReminderSettingsUpdateProbe.didSubmit=nil;window.isHidden=true;window.rootViewController=nil;release?.resume();release=nil}
                await fulfillment(of:[queried,settingsMounted],timeout:4);ReminderSettingsUpdateProbe.didMountRoot=nil
                let a=try XCTUnwrap(scope?.task)
                if newer == 1 {defaults.set(660,forKey:time);try await Task.sleep(for:.milliseconds(50))}
                let on=expectation(description:"Actual settings new B on")
                ReminderSettingsUpdateProbe.didSubmit={value in if value === scope {on.fulfill()}}
                defaults.set(true,forKey:key);await fulfillment(of:[on],timeout:4)
                if newer == 2 {
                    let off=expectation(description:"Actual settings explicit B off")
                    ReminderSettingsUpdateProbe.didSubmit={value in if value === scope {off.fulfill()}}
                    defaults.set(false,forKey:key);await fulfillment(of:[off],timeout:4)
                }
                ReminderSettingsUpdateProbe.didSubmit=nil
                let b=try XCTUnwrap(scope?.task),removeCount=client.removedIdentifiers.filter {$0 == id}.count
                let continuation=try XCTUnwrap(release);release=nil;continuation.resume()
                await a.value;await b.value
                XCTAssertEqual(client.removedIdentifiers.filter {$0 == id}.count-removeCount,newer == 2 ? 1:0)
                XCTAssertEqual(client.pending[id] != nil,newer != 2)
                if newer != 2 {XCTAssertEqual(client.pending[id]?.hour,newer == 1 ? 11:8)}
                XCTAssertEqual(client.pending.filter {$0.key != id},preserved)
                XCTAssertEqual(defaults.bool(forKey:key),newer != 2)
                XCTAssertFalse(scope?.cleanupPending ?? true);XCTAssertNil(scope?.failureMessage)
                XCTAssertEqual(client.authorizationRequests,0)
                print("PGOS_TC02 actualColdRootQuery=true actualSettingsB=true weekly=\(weekly) newer=\(newer) native=\(client.pending[id] != nil)")
            }
        }
    }
}

// 原生 List 渲染对照：原结构与局部候选，附件需要实际查看。
extension AppCompositionTests {
    func testUIReadabilityNativeListLabelComparison() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds; window.windowLevel = .normal + 1
        defer { window.isHidden = true; window.rootViewController = nil }
        for dark in [false, true] {
            for page in 0..<2 {
                window.overrideUserInterfaceStyle = dark ? .dark : .light
                window.rootViewController = UIHostingController(rootView: List {
                    if page == 0 {
                        Section("Original List structure") {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Button {} label: { Label("Start timing", systemImage: "play.fill").frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                                    Button {} label: { Label("Record activity", systemImage: "square.and.pencil").frame(minHeight: 44) }.buttonStyle(.bordered)
                                }
                            }
                        }
                        Section("Explicit titleAndIcon") {
                            Button {} label: { Label("Start timing", systemImage: "play.fill").labelStyle(.titleAndIcon).frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                        }
                        Section("Unified white foreground") {
                            Button {} label: { Label("Start timing", systemImage: "play.fill").foregroundStyle(.white).frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        Section("Original goal / empty-state label") {
                            Button {} label: { Label(String(localized: "Add Goal"), systemImage: "plus") }.buttonStyle(.borderedProminent)
                            Button {} label: { Label("Add Habit", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).controlSize(.large)
                        }
                        Section("Fixed shared empty-state") {
                            GrowthEmptyStateAddButton(title: "Add Habit", systemImage: "plus") {}
                            GrowthEmptyStateAddButton(title: "Add Weight", systemImage: "plus") {}
                            GrowthEmptyStateAddButton(title: "Start Weekly Review", systemImage: "square.and.pencil") {}
                        }
                        Section("Disabled explicit titleAndIcon") {
                            Button {} label: { Label("Start timing", systemImage: "play.fill").labelStyle(.titleAndIcon).frame(minHeight: 44) }.buttonStyle(.borderedProminent).disabled(true)
                        }
                    }
                }.id(page))
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
                let shot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: shot); attachment.name = "List-label-\(dark ? "dark" : "light")-page\(page)"; attachment.lifetime = .keepAlways; add(attachment)
                window.rootViewController = nil
            }
        }
        print("UIReadability native List OS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    func testUIReadabilityCompiledLocalizationAndWeekdayPolicy() throws {
        let translations = ["Archive activity": "归档活动", "Restore activity": "恢复活动", "Previous month": "上个月", "Next month": "下个月", "Try Again": "重试", "No data": "暂无数据", "Quantity": "数量", "This todo changed. Reload its reminder settings before trying again.": "此待办已更改。请重新载入提醒设置后再试。"]
        for language in ["en", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, chinese) in translations {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: "Localizable"), language == "en" ? key : chinese)
            }
            XCTAssertEqual(bundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"), language == "en" ? "Capture photos you choose to save in your private entries." : "拍摄你选择保存在私人记录中的照片。")
        }
        // Run this method with -testLanguage zh-Hans; this invokes the actual error producer.
        XCTAssertEqual(TodoFailure.staleTask.localizedDescription, Bundle.main.preferredLocalizations.first == "zh-Hans" ? "此待办已更改。请重新载入提醒设置后再试。" : "This todo changed. Reload its reminder settings before trying again.")
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let business = WeeklyReviewCalendarPolicy.calendar(timeZone: zone)
        let chinese = HabitDisplayCalendar.calendar(locale: Locale(identifier: "zh_CN"), timeZone: zone)
        let english = HabitDisplayCalendar.calendar(locale: Locale(identifier: "en_US"), timeZone: zone)
        XCTAssertEqual(chinese.identifier, .gregorian); XCTAssertEqual(chinese.firstWeekday, business.firstWeekday)
        XCTAssertEqual(chinese.minimumDaysInFirstWeek, business.minimumDaysInFirstWeek); XCTAssertEqual(chinese.timeZone, zone)
        XCTAssertEqual(HabitMonthCalendarPresentation.veryShortWeekdaySymbols(calendar: chinese), ["一", "二", "三", "四", "五", "六", "日"])
        XCTAssertEqual(HabitMonthCalendarPresentation.veryShortWeekdaySymbols(calendar: english), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(business.locale?.identifier, "en_US_POSIX")
    }
}
