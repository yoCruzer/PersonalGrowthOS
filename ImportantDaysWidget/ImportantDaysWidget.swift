import AppIntents
import SwiftUI
import WidgetKit

struct DayEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Important Day"
    static var defaultQuery = DayEntityQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct DayEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [DayEntity] {
        let records = (try? ImportantDayWidgetSnapshotStore.shared().read().records) ?? []
        // An invalid selection remains unresolved; never substitute a different private day.
        return identifiers.compactMap { id in records.first { $0.id == id }.map { DayEntity(id: $0.id, name: $0.title) } }
    }
    func suggestedEntities() async throws -> [DayEntity] {
        ((try? ImportantDayWidgetSnapshotStore.shared().read().records) ?? []).map { DayEntity(id: $0.id, name: $0.title) }
    }
}
struct SingleDayIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Important Day"
    static var description = IntentDescription("Choose a day authorized in the app. Appearance follows its saved numeric or photo style.")
    @Parameter(title: "Day") var day: DayEntity?
}
struct DayListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Day List"
    static var description = IntentDescription("Choose up to three days in this order. Empty or removed slots stay empty.")
    @Parameter(title: "First day") var first: DayEntity?
    @Parameter(title: "Second day") var second: DayEntity?
    @Parameter(title: "Third day") var third: DayEntity?
}
private enum DayTimeline {
    static func entry(ids: [UUID?], date: Date = Date()) -> DayWidgetEntry {
        DayWidgetEntry(date: date, ids: ids, snapshot: try? ImportantDayWidgetSnapshotStore.shared().read(), sample: false)
    }
    static func timeline(ids: [UUID?]) -> Timeline<DayWidgetEntry> {
        let now = Date(), snapshot = try? ImportantDayWidgetSnapshotStore.shared().read()
        let dates = ImportantDayWidgetTimeline.dates(from: now)
        return Timeline(entries: dates.map { .init(date: $0, ids: ids, snapshot: snapshot, sample: false) }, policy: .atEnd)
    }
    static func sample(list: Bool) -> DayWidgetEntry {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let date = Date(), civil = ImportantCivilDay(date), next = civil.adding(days: 23)!
        let records = [ImportantDayWidgetRecord(id: a, title: String(localized: "A day to look forward to"), rule: .init(year: next.year, month: next.month, day: next.day), photoStyle: false, cropX: 0.5, cropY: 0.5, coverFilename: nil),
            ImportantDayWidgetRecord(id: b, title: String(localized: "A new beginning"), rule: .init(preset: .beginning, year: civil.year - 1, month: 1, day: 1), photoStyle: false, cropX: 0.5, cropY: 0.5, coverFilename: nil)]
        return .init(date: date, ids: list ? [a, b, nil] : [a], snapshot: .init(version: 1, generation: UUID(), generatedAt: date, records: records), sample: true)
    }
}
struct SingleDayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayWidgetEntry { DayTimeline.sample(list: false) }
    func snapshot(for configuration: SingleDayIntent, in context: Context) async -> DayWidgetEntry {
        context.isPreview ? DayTimeline.sample(list: false) : DayTimeline.entry(ids: [configuration.day?.id])
    }
    func timeline(for configuration: SingleDayIntent, in context: Context) async -> Timeline<DayWidgetEntry> { DayTimeline.timeline(ids: [configuration.day?.id]) }
}
struct DayListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayWidgetEntry { DayTimeline.sample(list: true) }
    func snapshot(for configuration: DayListIntent, in context: Context) async -> DayWidgetEntry {
        context.isPreview ? DayTimeline.sample(list: true) : DayTimeline.entry(ids: [configuration.first?.id, configuration.second?.id, configuration.third?.id])
    }
    func timeline(for configuration: DayListIntent, in context: Context) async -> Timeline<DayWidgetEntry> { DayTimeline.timeline(ids: [configuration.first?.id, configuration.second?.id, configuration.third?.id]) }
}

struct ImportantDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ImportantDay", intent: SingleDayIntent.self, provider: SingleDayProvider()) { SingleDayWidgetView(entry: $0) }
            .configurationDisplayName("Important Day").description("A numeric or photo view of a day you choose.").supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct ImportantDayListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ImportantDayList", intent: DayListIntent.self, provider: DayListProvider()) { DayListWidgetView(entry: $0) }
            .configurationDisplayName("Day List").description("Up to three chosen days in your own order.").supportedFamilies([.systemMedium])
    }
}
@main
struct ImportantDaysWidgetBundle: WidgetBundle {
    var body: some Widget { ImportantDayWidget(); ImportantDayListWidget() }
}

#Preview(as: .systemSmall) { ImportantDayWidget() } timeline: { DayTimeline.sample(list: false) }
#Preview(as: .systemMedium) { ImportantDayListWidget() } timeline: { DayTimeline.sample(list: true) }
