import SwiftUI

@main
struct PersonalGrowthOSApp: App {
    private let startup: Result<AppContainer, Error>

    init() {
        let configuration = AppConfiguration.current()
        startup = Result { try AppContainer.make(configuration: configuration) }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let container):
                AppShell(container: container)
                    .modelContainer(container.modelContainer)
            case .failure:
                ContentUnavailableView(
                    "Unable to Open Your Data",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Personal Growth OS could not open its local store. Please restart the app.")
                )
                .accessibilityIdentifier("startup-error")
            }
        }
    }
}
