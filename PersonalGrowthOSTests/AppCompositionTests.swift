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
