import Foundation
import SwiftData

/// Created in a detached task: fetch and value mapping stay off the UI executor.
/// No save, insert, bootstrap, migration, notification or network operation belongs here.
@ModelActor
actor QuietWinsReader {
    func read(window: QuietWinsWindow) throws -> QuietWinsProjection {
        modelContext.autosaveEnabled = false
        try Task.checkCancellation()
        let start = window.start, end = window.asOf, fallback = Date.distantPast
        let completed = "completed", ordinary = "quickNote"
        let goals = try modelContext.fetch(FetchDescriptor<Goal>(predicate: #Predicate {
            $0.statusRawValue == completed && ($0.completedAt ?? fallback) >= start && ($0.completedAt ?? fallback) <= end
        }))
        let goalIDs = goals.map(\.id)
        let events = try modelContext.fetch(FetchDescriptor<GoalLifecycleEvent>(predicate: #Predicate { goalIDs.contains($0.goalID) }))
        let eventsByGoal = Dictionary(grouping: events, by: \.goalID)
        var input = QuietWinsInput()
        input.goals = goals.map { goal in
            // At equal timestamps, contradictory status events cannot prove completion.
            let history = eventsByGoal[goal.id] ?? []
            let latestDate = history.map(\.occurredAt).max()
            let latest = history.filter { $0.occurredAt == latestDate }
            let kinds = Set(latest.map(\.kindRawValue))
            return .init(id: goal.id, title: goal.title, isCompleted: goal.status == .completed,
                completedAt: goal.completedAt, latestLifecycleKind: kinds.count == 1 ? kinds.first : (latest.isEmpty ? nil : "ambiguous"),
                latestLifecycleDate: latestDate)
        }
        input.todos = try modelContext.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate {
            $0.stateRawValue == completed && ($0.completedAt ?? fallback) >= start && ($0.completedAt ?? fallback) <= end
        })).map { .init(id: $0.id, title: $0.title, isCompleted: $0.state == .completed, completedAt: $0.completedAt) }
        try Task.checkCancellation()

        let first = window.firstDay.description, last = window.lastDay.description
        let dayMetadata = try modelContext.fetch(FetchDescriptor<HabitLogDayMetadata>(predicate: #Predicate {
            $0.localDayIdentifier >= first && $0.localDayIdentifier <= last
        }))
        let dayLogIDs = dayMetadata.map(\.habitLogID)
        let civilLogs = try modelContext.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate {
            dayLogIDs.contains($0.id) && $0.isCompleted && $0.occurredAt <= end
        }))
        let logsByID = Dictionary(civilLogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let daysByLog = Dictionary(dayMetadata.map { ($0.habitLogID, $0.localDayIdentifier) }, uniquingKeysWith: { first, _ in first })
        let habitIDs = Array(Set(logsByID.values.map(\.habitID)))
        input.habits = try modelContext.fetch(FetchDescriptor<Habit>(predicate: #Predicate { habitIDs.contains($0.id) }))
            .map { .init(id: $0.id, title: $0.name) }
        input.logs = logsByID.values.map {
            .init(id: $0.id, habitID: $0.habitID, occurredAt: $0.occurredAt, isCompleted: $0.isCompleted, localDay: daysByLog[$0.id])
        }
        try Task.checkCancellation()

        let entries = try modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate {
            $0.kindRawValue == ordinary && $0.occurredAt >= start && $0.occurredAt <= end
        }))
        let entryIDs = entries.map(\.id)
        var externalIDs = Set(try modelContext.fetch(FetchDescriptor<EntryExternalSource>(predicate: #Predicate {
            entryIDs.contains($0.entryID)
        })).map(\.entryID))
        // A URL-less text/photo share has no EntryExternalSource, but its receipt
        // proves the import route. Join current Entries by ID, never by import time.
        externalIDs.formUnion(try modelContext.fetch(FetchDescriptor<CaptureImportReceipt>(predicate: #Predicate {
            entryIDs.contains($0.id)
        })).map(\.id))
        input.entries = entries.map {
            .init(id: $0.id, title: $0.title?.isEmpty == false ? $0.title! : String(localized: "Life record"),
                occurredAt: $0.occurredAt, isOrdinary: $0.kind == .quickNote,
                hasContent: $0.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !$0.images.isEmpty,
                isExternal: externalIDs.contains($0.id))
        }
        // Weekly identities are civil strings. Fetch only overlapping canonical weeks;
        // periodStart was stored in a possibly different zone and isn't completion time.
        let firstWeek = try WeeklyReviewPeriod(containing: start, timeZone: window.timeZone).identifier
        let lastWeek = try WeeklyReviewPeriod(containing: end, timeZone: window.timeZone).identifier
        input.reviews = try modelContext.fetch(FetchDescriptor<WeeklyReview>(predicate: #Predicate {
            $0.isCompleted && $0.weekIdentifier >= firstWeek && $0.weekIdentifier <= lastWeek
        })).map { .init(id: $0.id, weekIdentifier: $0.weekIdentifier, isCompleted: $0.isCompleted) }
        try Task.checkCancellation()
        return QuietWinsEngine.build(input, window: window)
    }
}

#if DEBUG
/// Public synthetic data only, reachable exclusively through the existing UI-test launch mode.
@MainActor
enum QuietWinsUITestFixture {
    static var integrationEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-PGOSUITesting") && arguments.contains("-PGOSQuietWinsIntegrationTest")
    }

    static func seed(context: ModelContext, mediaStore: MediaStore? = nil) throws {
        let now = Date()
        let created = now.addingTimeInterval(-60), completed = now.addingTimeInterval(-30)
        let goalService = GoalService(context: context, now: { created })
        let goal = try goalService.create(title: "Quiet goal", kind: .standard)
        try GoalService(context: context, now: { completed }).transition(goal, to: .completed)
        let todo = try TodoTaskService(context: context, now: { created }).create(TodoDraft(title: "Quiet task"))
        try TodoTaskService(context: context, now: { completed }).transition(id: todo.id, to: .completed)
        let ranking = ProcessInfo.processInfo.arguments.contains("-PGOSQuietWinsRankingTest")
        let usageDays = ProcessInfo.processInfo.arguments.contains("-PGOSUsageHabitDaysTest")
        let habit = try HabitService(context: context, now: { created }).create(name: "Quiet reading", recordingMode: ranking || usageDays ? .multiplePerDay : .oncePerDay)
        if ProcessInfo.processInfo.arguments.contains("-PGOSUsageHabitVariantsTest") {
            _ = try HabitService(context:context,now:{created}).create(name:"Synthetic daily multiple long habit",recordingMode:.multiplePerDay,dailyTargetCount:3)
            _ = try HabitService(context:context,now:{created}).create(name:"Synthetic weekly long habit",plan:.init(recordingMode:.oncePerDay,period:.week,goal:.count,targetCount:3,weekdays:[]))
            _ = try HabitService(context:context,now:{created}).create(name:"Synthetic monthly long habit",plan:.init(recordingMode:.oncePerDay,period:.month,goal:.count,targetCount:10,weekdays:[]))
        }
        if ProcessInfo.processInfo.arguments.contains("-PGOSUIReadabilityTest") {
            let service = HabitService(context: context, now: { created })
            _ = try service.create(name: "每天喝水几次", recordingMode: .multiplePerDay, dailyTargetCount: 8)
            for (name, period, target) in [("每周锻炼几次", HabitPlanPeriod.week, 3), ("深度阅读几篇文章", .month, 10), ("这是一个真正很长需要合理换行的每周习惯名称", .week, 4)] {
                let earlier = now.addingTimeInterval(-40 * 86400)
                let seeded = try HabitService(context: context, now: { earlier }).create(name: name, plan: .init(recordingMode: .multiplePerDay, period: period, goal: .count, targetCount: target, weekdays: []))
                if name != "这是一个真正很长需要合理换行的每周习惯名称" {
                    let yesterday = WeeklyReviewCalendarPolicy.calendar().date(byAdding: .day, value: -1, to: now)!
                    for _ in 0..<2 {
                        let fact = HabitLog(habitID: seeded.id, occurredAt: yesterday, isCompleted: true, createdAt: yesterday)
                        context.insert(fact)
                        context.insert(HabitLogDayMetadata(habitLogID: fact.id, localDayIdentifier: HabitLocalDay(date: yesterday).description, localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
                    }
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-PGOSUIReadabilityTest"), let mediaStore {
            let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")!
            try png.write(to: imageURL); defer { try? FileManager.default.removeItem(at: imageURL) }
            let imageEntry = try EntryCreationService(persistence: ModelContextEntryPersistence(context: context), mediaStore: mediaStore).create(.init(image: .init(url: imageURL, originalFilename: "synthetic.png", contentType: "image/png")))
            let activeGoal = try goalService.create(title: "本地化验证目标", kind: .standard)
            let userEntry = Entry(title: "Entry", body: "Today", createdAt: created)
            context.insert(userEntry)
            for entry in [imageEntry, userEntry] {
                context.insert(ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .goal, targetID: activeGoal.id, kind: .entryRelatesGoal, createdAt: created))
            }
        }
        let log = HabitLog(habitID: habit.id, occurredAt: completed, isCompleted: true, quantity: ProcessInfo.processInfo.arguments.contains("-PGOSUIReadabilityTest") ? 2 : nil, createdAt: completed)
        if usageDays { log.result = "Synthetic check-in 1" }
        context.insert(log)
        context.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: HabitLocalDay(date: completed).description,
            localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
        if usageDays {
            for index in 1..<6 {
                let stamp = index < 4 ? completed.addingTimeInterval(-Double(index)) : WeeklyReviewCalendarPolicy.calendar().date(byAdding: .day, value: -1, to: completed)!
                let record = HabitLog(habitID: habit.id, occurredAt: stamp, isCompleted: true, result: "Synthetic check-in \(index + 1)", createdAt: stamp)
                context.insert(record)
                context.insert(HabitLogDayMetadata(habitLogID: record.id, localDayIdentifier: HabitLocalDay(date: stamp).description,
                    localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
            }
        }
        if ranking {
            let yesterday = WeeklyReviewCalendarPolicy.calendar().date(byAdding: .day, value: -1, to: completed)!
            let previous = HabitLog(habitID: habit.id, occurredAt: yesterday, isCompleted: true, createdAt: yesterday)
            context.insert(previous)
            context.insert(HabitLogDayMetadata(habitLogID: previous.id, localDayIdentifier: HabitLocalDay(date: yesterday).description,
                localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
            let other = try HabitService(context: context, now: { created }).create(name: "Quiet walking", recordingMode: .oncePerDay)
            let otherLog = HabitLog(habitID: other.id, occurredAt: completed, isCompleted: true, createdAt: completed)
            context.insert(otherLog)
            context.insert(HabitLogDayMetadata(habitLogID: otherLog.id, localDayIdentifier: HabitLocalDay(date: completed).description,
                localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
        }
        context.insert(Entry(title: "Quiet life record", body: "A real synthetic record for source navigation.", createdAt: created, occurredAt: completed))
        let period = try WeeklyReviewPeriod(containing: now)
        context.insert(WeeklyReview(weekIdentifier: period.identifier, periodStart: period.start, periodEnd: period.end,
            rememberedText: "Quiet week evidence", isCompleted: true, createdAt: created))
        try context.save()
    }

    static func importPublicFixture(container: ModelContainer, mediaStore: MediaStore) async throws {
        let inbox = ShareInbox(root: mediaStore.rootURL.appendingPathComponent("QuietWinsUITestInbox"))
        let payload = ShareImportPayload(createdAt: Date().addingTimeInterval(-10), text: "Public background share without URL")
        try inbox.publish(payload, files: [:])
        let failures = try await ExternalCaptureImporter(container: container, mediaStore: mediaStore, inbox: inbox).scan()
        guard failures == 0 else { throw CaptureError.invalidPayload }
    }
}
#endif
