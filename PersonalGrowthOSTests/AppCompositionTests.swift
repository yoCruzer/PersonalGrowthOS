import XCTest
@testable import PersonalGrowthOS

@MainActor
final class AppCompositionTests: XCTestCase {
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
}
