import SwiftData
import SwiftUI
import UIKit

@main
struct PersonalGrowthOSApp: App {
    @State private var startup: Result<AppContainer, Error>
    @State private var isRetrying = false
    @State private var copied = false
    @State private var recoveryURL: URL?
    @State private var recoveryError: String?
    @State private var isPreparingRecovery = false

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
            if configuration.launchMode == .uiTesting,
               ProcessInfo.processInfo.arguments.contains("-PGOSTodoIntegrityFailureTest") {
                if configuration.resetDataOnLaunch {
                    container.modelContainer.mainContext.insert(Entry(body: "Retained integrity fixture", createdAt: Date()))
                    let task = try TodoTaskService(context: container.modelContainer.mainContext).create(TodoDraft(title: "Integrity fixture"))
                    task.revision = 99; try container.modelContainer.mainContext.save()
                }
                return try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false))
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSTodoFiltersTest") {
                let service = TodoTaskService(context: container.modelContainer.mainContext)
                let list = try service.createList(name: "Filter List")
                _ = try service.create(TodoDraft(title: "Filter Open", listID: list.id))
                let done = try service.create(TodoDraft(title: "Filter Done", listID: list.id))
                try service.transition(id: done.id, to: .completed)
                let canceled = try service.create(TodoDraft(title: "Filter Canceled", listID: list.id))
                try service.transition(id: canceled.id, to: .canceled)
                let yesterday = try TodoRecurrence.reminderDay(occurrence: TodoDay(date: Date()), offset: -1).description
                _ = try service.create(TodoDraft(title: "Filter Overdue", isImportant: true, deadlineDay: yesterday, listID: list.id))
                _ = try service.create(TodoDraft(title: "Undated unclassified"))
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
                let diagnostic = (error as? StartupRetainedDataFailure)?.diagnostic ?? (error as? AppDiagnosticFailure)?.diagnostic
                    ?? FailureDiagnostic(error: error, stage: .startupPaths)
                ScrollView {
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
                        if let failure = error as? StartupRetainedDataFailure {
                            if let snapshotFailure = failure.snapshotFailure { Text(verbatim: snapshotFailure.report).font(.caption.monospaced()) }
                            if let retained = failure.retained {
                                Text("Normal writes are paused. Export the retained database and original files for recovery. This private archive needs support recovery and cannot be imported as a normal backup.")
                                    .font(.caption).multilineTextAlignment(.center)
                                if let recoveryURL {
                                    ShareLink("Save Retained Data", item: recoveryURL).accessibilityIdentifier("startup-share-retained")
                                } else {
                                    Button("Prepare Retained Data Export") {
                                        isPreparingRecovery = true; recoveryError = nil
                                        Task {
                                            do {
                                                recoveryURL = try await Task.detached { try retained.archive(diagnostic: diagnostic.report) }.value
                                            } catch { recoveryError = error.localizedDescription }
                                            isPreparingRecovery = false
                                        }
                                    }.disabled(isPreparingRecovery).accessibilityIdentifier("startup-export-retained")
                                }
                                if let recoveryError { Text(recoveryError).font(.caption) }
                                if isPreparingRecovery { ProgressView() }
                            }
                        }
                        Button("Retry") { retryStartup() }
                            .accessibilityIdentifier("startup-retry")
                            .disabled(isRetrying || isPreparingRecovery)
                        if isRetrying { ProgressView() }
                    }
                    .padding()
                }
            }
        }
    }

    private func retryStartup() {
        isRetrying = true
        copied = false
        recoveryURL = nil; recoveryError = nil
        Task { @MainActor in
            await Task.yield()
            let current = AppConfiguration.current()
            let configuration = AppConfiguration(launchMode: current.launchMode, resetDataOnLaunch: false)
            startup = Result { try AppContainer.make(configuration: configuration) }
            isRetrying = false
        }
    }
}
