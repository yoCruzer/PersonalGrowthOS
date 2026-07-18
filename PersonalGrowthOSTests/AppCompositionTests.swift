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
        draft.finishImageLoad(with: .success(source))

        draft.beginImageLoad()
        draft.finishImageLoad(with: .failure(InjectedFailure()))

        XCTAssertEqual(draft.body, "Keep my words")
        XCTAssertEqual(draft.imageSource?.url, source.url)
        XCTAssertNotNil(draft.errorMessage)
    }
}
