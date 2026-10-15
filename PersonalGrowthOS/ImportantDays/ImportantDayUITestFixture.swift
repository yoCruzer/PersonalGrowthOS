#if DEBUG
import SwiftData
import UIKit

@MainActor
enum ImportantDayUITestFixture {
    static var referenceDateOverride: Date?
    static var isReviewTest: Bool { ProcessInfo.processInfo.arguments.contains("-PGOSUITesting") && ProcessInfo.processInfo.arguments.contains("-PGOSImportantDaysReviewTest") }
    static let routeID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    static func seed(context: ModelContext, mediaStore: MediaStore) throws {
        if isReviewTest { try seedReview(context: context, mediaStore: mediaStore); return }
        let today = ImportantCivilDay(Date()), trip = today.adding(days: 3)!
        let service = ImportantDayService(context: context, mediaStore: mediaStore)
        var draft = ImportantDayDraft(); draft.title = "Synthetic trip · 合成旅行"
        draft.rule = .init(year: trip.year, month: trip.month, day: trip.day); draft.preferences.desktopVisible = true
        _ = try service.save(draft, id: routeID)
        draft.title = "Synthetic beginning · 合成起点"; draft.rule = .init(preset: .beginning, year: 2000, month: 1, day: 1, perspective: .elapsed)
        draft.preferences.today = .always; draft.preferences.photoStyle = true
        let photo = mediaStore.rootURL.appendingPathComponent("synthetic-cover.png")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).pngData { renderer in
            UIColor.systemTeal.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            UIColor.systemOrange.setFill(); renderer.fill(CGRect(x: 320, y: 0, width: 320, height: 480))
        }; try bytes.write(to: photo)
        _ = try service.save(draft, coverSource: .init(url: photo, originalFilename: "synthetic-cover.png", contentType: "image/png"))
        try FileManager.default.removeItem(at: photo)
        draft.title = "Synthetic lunar birthday · 合成农历生日"; draft.rule = .init(preset: .anniversary, calendar: .chinese, year: nil, month: 1, day: 1)
        draft.preferences.photoStyle = false; draft.preferences.today = .automatic
        _ = try service.save(draft)
        let entry = Entry(title: "Synthetic memory", body: "Old memory for explicit date confirmation", createdAt: Date(), occurredAt: ImportantCivilDay(year: 2021, month: 6, day: 20).date!)
        context.insert(entry); try context.save()
    }
    private static func seedReview(context: ModelContext, mediaStore: MediaStore) throws {
        referenceDateOverride = ImportantCivilDay(year: 2026, month: 10, day: 15).date!
        let service = ImportantDayService(context: context, mediaStore: mediaStore)
        var draft = ImportantDayDraft(); draft.title = "Review annual"
        draft.rule = .init(preset: .anniversary, year: 2020, month: 10, day: 15); draft.preferences.favoriteOrder = 0
        let day = try service.save(draft)
        for (title, period) in [("General A", nil as ImportantCivilDay?), ("General B", nil), ("Period 2026", ImportantCivilDay(year: 2026, month: 10, day: 15))] {
            let entry = Entry(title: title, body: title, createdAt: Date()); context.insert(entry); try context.save()
            try service.linkEntry(dayID: day.id, entryID: entry.id, occurrence: period)
        }
        draft.title = "Review lunar leap"; draft.rule = .init(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1, isLeapMonth: true, leapMonthRule: .regularFallback, perspective: .elapsed)
        draft.preferences.favoriteOrder = 1; _ = try service.save(draft)
        for (index, title) in ["Review C", "Review D"].enumerated() {
            draft.title = title; draft.notes = "pair"; draft.rule = .init(year: 2026, month: 10, day: 20); draft.preferences.favoriteOrder = index + 2
            _ = try service.save(draft)
        }
        context.insert(Entry(title: "Existing review memory", body: "Existing review memory", createdAt: Date(), occurredAt: ImportantCivilDay(year: 2001, month: 1, day: 1).date!)); try context.save()
    }
}
#endif
