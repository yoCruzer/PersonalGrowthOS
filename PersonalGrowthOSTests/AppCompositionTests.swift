import XCTest
import SwiftData
import UIKit
@testable import PersonalGrowthOS

@MainActor
final class AppCompositionTests: XCTestCase {
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
