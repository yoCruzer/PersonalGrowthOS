import SwiftUI

@main
struct PersonalGrowthOSApp: App {
    private let container: AppContainer

    init() {
        let configuration = AppConfiguration.current()
        container = AppContainer(configuration: configuration)
    }

    var body: some Scene {
        WindowGroup {
            RootPlaceholderView(container: container)
        }
    }
}
