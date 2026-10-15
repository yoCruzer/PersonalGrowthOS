import SwiftUI
import WidgetKit
import UIKit

enum ImportantDayWidgetTimeline {
    static func dates(from now: Date, calendar: Calendar = .current) -> [Date] {
        [now] + (1...35).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now)) }
    }
}

struct DayWidgetEntry: TimelineEntry {
    let date: Date
    let ids: [UUID?]
    let snapshot: ImportantDayWidgetSnapshot?
    let sample: Bool
    func record(at index: Int) -> ImportantDayWidgetRecord? {
        guard ids.indices.contains(index), let id = ids[index] else { return nil }
        return snapshot?.records.first { $0.id == id }
    }
}
struct SingleDayWidgetView: View {
    let entry: DayWidgetEntry
    var previewMode = false
    var previewImage: UIImage? = nil
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if previewMode { content.padding(16).background { background } }
        else { content.containerBackground(for: .widget) { background } }
    }
    private var content: some View {
        Group {
            if !redactionReasons.contains(.privacy), let record = entry.record(at: 0), let result = try? ImportantDayDateEngine.evaluate(record.rule, today: .init(entry.date)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if result.signedDays == 0 { Text("It is today").font(.title2.bold()) }
                    else {
                        Text(result.signedDays > 0 ? String(localized: "Remaining") : record.rule.preset == .anticipated ? String(localized: "Planned day passed") : String(localized: "Elapsed")).font(.caption)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(abs(result.signedDays).formatted()).font(.system(typeSize.isAccessibilitySize ? .title : .largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            Text("days").font(.caption)
                        }
                    }
                    if !typeSize.isAccessibilitySize { Text(result.displayDay.identifier).font(.caption2).monospacedDigit() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(hasPhoto(record) && renderingMode == .fullColor ? .white : .primary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(record.title + ", " + record.rule.distanceDescription(today: .init(entry.date)))
                .privacySensitive()
                .widgetURL(ImportantDayRoute.url(id: record.id))
            } else { neutral }
        }
    }
    @ViewBuilder private var background: some View {
            if !redactionReasons.contains(.privacy), let record = entry.record(at: 0), let image = photo(record), renderingMode == .fullColor {
                ImportantDayPhotoView(image: image, cropX: record.cropX, cropY: record.cropY)
                    .overlay(Color.black.opacity(0.58))
            } else { Color(.secondarySystemBackground) }
    }
    private func photo(_ record: ImportantDayWidgetRecord) -> UIImage? {
        guard record.photoStyle else { return nil }
        if let previewImage { return previewImage }
        guard let generation = entry.snapshot?.generation,
              let store = try? ImportantDayWidgetSnapshotStore.shared(), let url = store.coverURL(record: record, generation: generation) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    private func hasPhoto(_ record: ImportantDayWidgetRecord) -> Bool { photo(record) != nil }
    private var neutral: some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: "calendar"); Text("Choose an Important Day").font(.headline); Text("Authorize a day in the app, then edit this widget.").font(.caption) }
    }
}
struct DayListWidgetView: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: DayWidgetEntry
    var previewMode = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if previewMode { content.padding(16).background(Color(.secondarySystemBackground)) }
        else { content.containerBackground(Color(.secondarySystemBackground), for: .widget) }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Important Days").font(.caption.bold())
            ForEach(0..<(typeSize.isAccessibilitySize ? 2 : 3), id: \.self) { index in
                if !redactionReasons.contains(.privacy), let record = entry.record(at: index) {
                    Link(destination: ImportantDayRoute.url(id: record.id)) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.title).font(.subheadline).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                            Spacer(minLength: 4)
                            Text(record.rule.distanceDescription(today: .init(entry.date))).font(.caption).monospacedDigit().multilineTextAlignment(.trailing)
                        }.privacySensitive()
                    }
                } else {
                    Label("Choose a day", systemImage: "calendar.badge.plus").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
