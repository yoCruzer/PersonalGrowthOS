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


struct BuildProvenance: Equatable {
    let commit: String?
    let source: String
    let isDirty: Bool
    let tag: String?

    init(values: [String: Any]) {
        let raw = values["Commit"] as? String ?? ""
        let valid = raw.count == 40 && raw.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        commit = valid ? raw.lowercased() : nil
        let origin = values["Source"] as? String ?? "unknown"
        source = valid && ["localGit", "xcodeCloud"].contains(origin) ? origin : "unknown"
        isDirty = source == "localGit" && values["Dirty"] as? Bool == true
        let label = values["Tag"] as? String ?? ""
        let safe = label.count <= 256 && label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 47, 43, 95].contains($0) }
        tag = source == "xcodeCloud" && safe && !label.isEmpty ? label : nil
    }
    init(bundle: Bundle = .main) {
        let values = bundle.url(forResource: "BuildProvenance", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        self.init(values: values)
    }
    var shortCommit: String { commit.map { String($0.prefix(9)) } ?? String(localized: "Unknown") }
    var sourceLabel: String {
        switch source {
        case "xcodeCloud": return String(localized: "Xcode Cloud")
        case "localGit": return isDirty ? String(localized: "Local build · uncommitted changes") : String(localized: "Local Git build")
        default: return String(localized: "Unknown")
        }
    }
    func copyText(version: AppVersionInformation) -> String {
        var lines = [version.displayText, "Commit: \(commit ?? String(localized: "Unknown"))", sourceLabel]
        if let tag { lines.append("Tag: \(tag)") }
        return lines.joined(separator: "\n")
    }
}
