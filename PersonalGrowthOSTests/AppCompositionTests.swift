import XCTest
@testable import PersonalGrowthOS

final class AppCompositionTests: XCTestCase {
    func testDefaultInputsSelectStandardMode() {
        let configuration = AppConfiguration.resolve(arguments: [], environment: [:])

        XCTAssertEqual(configuration.launchMode, .standard)
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

    func testContainerRetainsResolvedConfiguration() {
        let configuration = AppConfiguration.resolve(
            arguments: [AppConfiguration.uiTestingLaunchArgument],
            environment: [:]
        )

        let container = AppContainer(configuration: configuration)

        XCTAssertEqual(container.configuration, configuration)
    }
}
