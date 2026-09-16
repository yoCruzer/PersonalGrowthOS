import Foundation

struct AppConfiguration: Equatable {
    enum LaunchMode: Equatable {
        case standard
        case uiTesting
    }

    static let uiTestingLaunchArgument = "-PGOSUITesting"
    static let resetDataLaunchArgument = "-PGOSResetData"
    static let uiTestingEnvironmentKey = "PGOS_UI_TESTING"

    let launchMode: LaunchMode
    let resetDataOnLaunch: Bool

    static func current(processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        resolve(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    static func resolve(
        arguments: [String],
        environment: [String: String]
    ) -> AppConfiguration {
        let isUITesting = arguments.contains(uiTestingLaunchArgument)
            || environment[uiTestingEnvironmentKey] == "1"

        return AppConfiguration(
            launchMode: isUITesting ? .uiTesting : .standard,
            resetDataOnLaunch: isUITesting && arguments.contains(resetDataLaunchArgument)
        )
    }
}

struct AppVersionInformation: Equatable {
    let name: String
    let version: String
    let build: String

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:], localizedInfo: [String: Any] = Bundle.main.localizedInfoDictionary ?? [:]) {
        func value(_ key: String) -> String? {
            guard let text = (localizedInfo[key] ?? info[key]) as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? String(localized: "Unknown")
        version = value("CFBundleShortVersionString") ?? String(localized: "Unknown")
        build = value("CFBundleVersion") ?? String(localized: "Unknown")
    }

    var displayText: String { "\(name) \(version) (Build \(build))" }
}
