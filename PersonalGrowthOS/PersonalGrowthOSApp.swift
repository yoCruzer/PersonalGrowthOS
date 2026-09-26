import SwiftData
import SwiftUI
import UIKit

@main
struct PersonalGrowthOSApp: App {
    @State private var startup: Result<AppContainer, Error>
    @State private var isRetrying = false
    @State private var copied = false

    init() {
        let configuration = AppConfiguration.current()
        let result = Result<AppContainer, Error> {
            let container = try AppContainer.make(configuration: configuration)
            #if DEBUG
            if configuration.launchMode == .uiTesting,
               ProcessInfo.processInfo.arguments.contains("-PGOSStartupFailureTest") {
                container.modelContainer.mainContext.insert(Entry(body: "Preserved startup retry fixture", createdAt: Date()))
                try container.modelContainer.mainContext.save()
                throw AppDiagnosticFailure(NSError(domain: NSCocoaErrorDomain, code: 134504,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE-STARTUP-TOKEN /private/user.sqlite?secret=1"]), stage: .storeOpen)
            }
            #endif
            return container
        }
        _startup = State(initialValue: result)
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let container):
                AppShell(container: container)
                    .modelContainer(container.modelContainer)
            case .failure(let error):
                let diagnostic = (error as? AppDiagnosticFailure)?.diagnostic
                    ?? FailureDiagnostic(error: error, stage: .startupPaths)
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Unable to Open Your Data",
                        systemImage: "exclamationmark.triangle",
                        description: Text(diagnostic.category.title)
                    )
                    .accessibilityIdentifier("startup-error")
                    Text("Your data is retained. Retry safely, or copy this diagnostic report for support.")
                        .multilineTextAlignment(.center)
                    Text(verbatim: diagnostic.report)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("startup-diagnostic")
                    Button(copied ? "Copied" : "Copy Diagnostic Report") {
                        UIPasteboard.general.string = diagnostic.report
                        copied = true
                    }
                    .accessibilityIdentifier("startup-copy-diagnostic")
                    Button("Retry") { retryStartup() }
                        .accessibilityIdentifier("startup-retry")
                        .disabled(isRetrying)
                    if isRetrying { ProgressView() }
                }
                .padding()
            }
        }
    }

    private func retryStartup() {
        isRetrying = true
        copied = false
        Task { @MainActor in
            await Task.yield()
            let current = AppConfiguration.current()
            let configuration = AppConfiguration(launchMode: current.launchMode, resetDataOnLaunch: false)
            startup = Result { try AppContainer.make(configuration: configuration) }
            isRetrying = false
        }
    }
}
