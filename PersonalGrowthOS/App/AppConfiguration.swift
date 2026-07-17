import Foundation

struct AppConfiguration: Equatable {
    enum LaunchMode: Equatable {
        case standard
        case uiTesting
    }

    static let uiTestingLaunchArgument = "-PGOSUITesting"
    static let uiTestingEnvironmentKey = "PGOS_UI_TESTING"

    let launchMode: LaunchMode

    static func current(processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        resolve(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    static func resolve(
        arguments: [String],
        environment: [String: String]
    ) -> AppConfiguration {
        let isUITesting = arguments.contains(uiTestingLaunchArgument)
            || environment[uiTestingEnvironmentKey] == "1"

        return AppConfiguration(launchMode: isUITesting ? .uiTesting : .standard)
    }
}
