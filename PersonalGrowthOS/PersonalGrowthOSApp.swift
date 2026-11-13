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
            SyncPushBridge.coordinator = container.syncCoordinator
            #if DEBUG
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSAppStoreDemo") {
                try AppStoreDemoFixture.seed(container)
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSSyncStatusLocalizationTest") {
                let dataset = ProductSyncDataset()
                dataset.enabled = true; dataset.initialized = true
                dataset.accountHash = String(repeating: "a", count: 64)
                dataset.lastSuccess = Date(timeIntervalSince1970: 1_700_000_000)
                try ProductSyncStoreSelection.activate(dataset, in: container.modelContainer.mainContext)
                try container.modelContainer.mainContext.save()
                container.syncCoordinator.refreshStatus()
                if ProcessInfo.processInfo.arguments.contains("-PGOSSyncDownloadingTest") {
                    let session = SyncCloudSession(binding: try .init(container: SyncProductCoordinator.containerID,
                        environment: .development, accountHash: dataset.accountHash!, dataset: dataset.id, generation: dataset.generation))
                    try container.syncCoordinator.didChangeActivity(.downloading, session: session)
                }
            }
            if configuration.launchMode == .uiTesting, configuration.resetDataOnLaunch,
               ProcessInfo.processInfo.arguments.contains("-PGOSSyncPausedNavigationTest") {
                let dataset = ProductSyncDataset()
                dataset.enabled = true; dataset.initialized = true
                dataset.accountHash = String(repeating: "a", count: 64)
                dataset.blockedReason = "Sync paused (accountChanged); local data and pending revisions are kept."
                try ProductSyncStoreSelection.activate(dataset, in: container.modelContainer.mainContext)
                try container.modelContainer.mainContext.save()
                container.syncCoordinator.refreshStatus()
            }
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
            startup = Result {
                let container = try AppContainer.make(configuration: configuration)
                SyncPushBridge.coordinator = container.syncCoordinator
                return container
            }
            isRetrying = false
        }
    }
}

#if DEBUG
/// Synthetic content only, in the existing isolated UI-testing store. Sync stays off.
@MainActor private enum AppStoreDemoFixture {
    static func seed(_ container: AppContainer) throws {
        let context = container.modelContainer.mainContext
        let zh = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        func copy(_ chinese: String, _ english: String) -> String { zh ? chinese : english }
        let now = Date(), earlier = now.addingTimeInterval(-7 * 86400)
        let habits = HabitService(context: context, now: { earlier })
        _ = try habits.create(name: copy("读书二十分钟", "Read for twenty minutes"), recordingMode: .oncePerDay)
        _ = try habits.create(name: copy("出门走一走", "Take a walk outside"), recordingMode: .oncePerDay)
        _ = try habits.create(name: copy("喝一杯水", "Drink a glass of water"), recordingMode: .multiplePerDay, dailyTargetCount: 6)
        _ = try GoalService(context: context, now: { earlier }).create(title: copy("读完一本喜欢的书", "Finish a book I enjoy"), kind: .standard)
        let tasks = TodoTaskService(context: context)
        _ = try tasks.create(TodoDraft(title: copy("整理周末散步的照片", "Organize weekend walk photos"), plannedDay: TodoDay(date: now).description))
        _ = try tasks.create(TodoDraft(title: copy("给下周留一点空白", "Leave some room for next week")))
        let imageURL = container.mediaStore.rootURL.appendingPathComponent("app-store-demo-illustration.png")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 650)).pngData { renderer in
            UIColor(red: 0.89, green: 0.94, blue: 0.88, alpha: 1).setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 1000, height: 650))
            UIColor(red: 0.93, green: 0.72, blue: 0.36, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: 680, y: 70, width: 140, height: 140)).fill()
            UIColor(red: 0.40, green: 0.63, blue: 0.49, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: -160, y: 300, width: 900, height: 650)).fill()
            UIColor(red: 0.25, green: 0.48, blue: 0.40, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: 400, y: 340, width: 900, height: 650)).fill()
            (copy("演示插图 · 午后", "Demo illustration · Afternoon") as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: UIColor.darkGray])
        }
        try bytes.write(to: imageURL); defer { try? FileManager.default.removeItem(at: imageURL) }
        let creation = EntryCreationService(persistence: ModelContextEntryPersistence(context: context), mediaStore: container.mediaStore, now: { now.addingTimeInterval(-300) })
        _ = try creation.create(.init(title: copy("午后，慢慢走", "A slower afternoon"), body: copy("演示记录：走过熟悉的小路，发现树叶已经换了颜色。今天没有赶时间。", "Demo entry: Along a familiar path, the leaves have changed color. Today I let myself slow down."), image: .init(url: imageURL, originalFilename: "demo-illustration.png", contentType: "image/png")))
        context.insert(Entry(title: copy("留住一个小想法", "Keep a small thought"), body: copy("演示记录：每天留十分钟，做一点自己喜欢的事。", "Demo entry: Leave ten minutes each day for something I enjoy."), createdAt: now.addingTimeInterval(-86400)))
        context.insert(Entry(title: copy("本周的一点收获", "A small lesson this week"), body: copy("演示记录：比起一次做很多，更想把喜欢的事情慢慢做下去。", "Demo entry: I would rather keep doing what matters than do everything at once."), createdAt: now.addingTimeInterval(-172800)))
        for index in 0..<5 {
            let at = now.addingTimeInterval(-Double(index) * 86400)
            context.insert(WeightRecord(weightKilograms: 68.2 + Double(index) * 0.1, recordedAt: at, createdAt: at))
        }
        try context.save()
    }
}
#endif
