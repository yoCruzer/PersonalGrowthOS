import SwiftData
import SwiftUI
import UIKit

@main
struct PersonalGrowthOSApp: App {
    @UIApplicationDelegateAdaptor(ImportantDayNotificationDelegate.self) private var notificationDelegate
    @State private var startup: Result<AppContainer, Error>
    @State private var isRetrying = false
    @State private var copied = false
    @State private var recoveryURL: URL?
    @State private var recoveryError: String?
    @State private var isPreparingRecovery = false

    init() {
        let configuration = AppConfiguration.current()
        #if DEBUG
        if configuration.launchMode == .uiTesting, ProcessInfo.processInfo.arguments.contains("-PGOSSleepColdRouteTest") {
            SleepExternalRouter.shared.receive(day: "2026-01-01")
        }
        #endif
        let result = Result<AppContainer, Error> {
            let container = try AppContainer.make(configuration: configuration)
            #if DEBUG
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch {
                for key in ["sleep.showToday", "sleep.introductionDismissed", "sleep.morningReminder.plannedFires", SleepReminderPreferences.enabledKey, SleepReminderPreferences.minuteKey] { UserDefaults.standard.removeObject(forKey: key) }
            }
            if configuration.launchMode == .uiTesting,configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSSettingsPreferenceTest") {
                for (key,value) in [("dailyRecordingReminderEnabled",true),("weeklyReviewReminderEnabled",true)] {UserDefaults.standard.set(value,forKey:key)}
                UserDefaults.standard.set(480,forKey:"dailyRecordingReminderMinutes")
                UserDefaults.standard.set(690,forKey:"weeklyReviewReminderMinutes")
                UserDefaults.standard.set(6,forKey:"weeklyReviewReminderWeekday")
            }
            if configuration.launchMode == .uiTesting,configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSUsageElapsedTodoTest") {
                let zone=TimeZone.current,then=TodoDay("2020-01-01")!.date(timeZone:TimeZone.current)!.addingTimeInterval(12*3600)
                let service=TodoTaskService(context:container.modelContainer.mainContext,now:{then},timeZone:{zone})
                _ = try service.create(.init(title:"Synthetic long elapsed reminder",plannedDay:"2020-01-01",deadlineDay:"2020-01-02",remindAt:then.addingTimeInterval(3600),frequency:.daily),id:UUID(uuidString:"40000000-1111-4222-8333-444444444444")!)
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSUsageWeightTest") {
                let now = Date(), calendar = Calendar(identifier: .gregorian)
                let today = calendar.startOfDay(for: now)
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
                let values: [(Double, Date)] = [(70, yesterday.addingTimeInterval(8 * 3600)), (72, yesterday.addingTimeInterval(18 * 3600)),
                    (75, today), (65, calendar.date(byAdding: .day, value: -60, to: today)!)]
                for (kilograms, at) in values {
                    container.modelContainer.mainContext.insert(WeightRecord(weightKilograms: kilograms, recordedAt: at, createdAt: at))
                }
                try container.modelContainer.mainContext.save()
            }
            if configuration.launchMode == .uiTesting,configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSWeightLosslessTest") {
                let service=WeightRecordService(context:container.modelContainer.mainContext)
                for (value,day) in [(72.345,"2026-10-10"),(1000.0,"2026-10-09")] {
                    _ = try service.create(weightKilograms:value,recordedAt:ImportantCivilDay(identifier:day)!.instant(minutes:720,timeZone:.current)!)
                }
            }
            if configuration.launchMode == .uiTesting,configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSWeeklyCutoffTest") {
                try WeeklyReviewClock.seed(context:container.modelContainer.mainContext,mediaStore:container.mediaStore)
            }
            if configuration.launchMode == .uiTesting,configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSWeightReviewFixDates") {
                let today=ImportantCivilDay(WeightReviewClock.current()),zone=TimeZone.current
                let day=ImportantCivilDay(year:today.year,month:today.month,day:1).instant(minutes:0,timeZone:zone)!
                for index in 0..<60 {
                    let at=day.addingTimeInterval(Double(index)*60)
                    container.modelContainer.mainContext.insert(WeightRecord(weightKilograms:70+Double(index)/100,recordedAt:at,createdAt:at))
                }
                let later=ImportantCivilDay(year:today.year,month:today.month,day:17).instant(minutes:600,timeZone:zone)!
                container.modelContainer.mainContext.insert(WeightRecord(weightKilograms:77,recordedAt:later,createdAt:later))
                try container.modelContainer.mainContext.save()
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSImportantDaysTest") {
                try ImportantDayUITestFixture.seed(context: container.modelContainer.mainContext, mediaStore: container.mediaStore)
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSQuietWinsTest") {
                try QuietWinsUITestFixture.seed(context: container.modelContainer.mainContext, mediaStore: container.mediaStore)
            }
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
            Group {
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
            }.onOpenURL { url in
                if let id = ImportantDayRoute.parse(url) { ImportantDayExternalRouter.shared.receive(id: id, source: .widget) }
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
