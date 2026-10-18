import Foundation
import SwiftData

@Model
final class WeightRecord {
    @Attribute(.unique) var id: UUID
    var weightKilograms: Double
    var recordedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        weightKilograms: Double,
        recordedAt: Date,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.weightKilograms = weightKilograms
        self.recordedAt = recordedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum WeightValidationError: Error, Equatable {
    case invalidWeight
    case missingRecord
}

enum WeightRules {
    static let maximumKilograms = 1_000.0

    static func kilograms(from input: String) throws -> Double {
        guard let value = Double(input.replacingOccurrences(of: ",", with: ".")) else {
            throw WeightValidationError.invalidWeight
        }
        return try validatedKilograms(value)
    }

    static func validatedKilograms(_ value: Double) throws -> Double {
        guard value.isFinite, value > 0, value <= maximumKilograms else {
            throw WeightValidationError.invalidWeight
        }
        return value
    }
}

enum WeightRecordOrdering {
    static let newestFirstSortDescriptors = [
        SortDescriptor(\WeightRecord.recordedAt, order: .reverse),
        SortDescriptor(\WeightRecord.createdAt, order: .reverse),
        SortDescriptor(\WeightRecord.id, order: .forward)
    ]

    static func newestFirst(_ records: [WeightRecord]) -> [WeightRecord] {
        records.sorted {
            if $0.recordedAt != $1.recordedAt {
                return $0.recordedAt > $1.recordedAt
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func oldestFirst(_ records: [WeightRecord]) -> [WeightRecord] {
        Array(newestFirst(records).reversed())
    }
}

struct WeightTrend: Equatable {
    let latestKilograms: Double
    let changeKilograms: Double?

    static func make(from records: [WeightRecord]) -> WeightTrend? {
        let ordered = WeightRecordOrdering.newestFirst(records)
        guard let latest = ordered.first else { return nil }
        return WeightTrend(
            latestKilograms: latest.weightKilograms,
            changeKilograms: ordered.dropFirst().first.map {
                latest.weightKilograms - $0.weightKilograms
            }
        )
    }
}

@MainActor
final class WeightRecordService {
    private let context: ModelContext
    private let now: () -> Date
    private let save: () throws -> Void

    init(
        context: ModelContext,
        now: @escaping () -> Date = Date.init,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.now = now
        self.save = save ?? { try context.save() }
    }

    func create(weightKilograms: Double, recordedAt: Date) throws -> WeightRecord {
        let validatedWeight = try WeightRules.validatedKilograms(weightKilograms)
        let timestamp = now()
        let record = WeightRecord(
            weightKilograms: validatedWeight,
            recordedAt: recordedAt,
            createdAt: timestamp
        )
        context.insert(record)
        do {
            try save()
            return record
        } catch {
            context.rollback()
            throw error
        }
    }

    func update(
        _ record: WeightRecord,
        weightKilograms: Double,
        recordedAt: Date
    ) throws {
        let validatedWeight = try WeightRules.validatedKilograms(weightKilograms)
        guard let persistedRecord = try fetch(id: record.id) else {
            throw WeightValidationError.missingRecord
        }
        let originalWeight = persistedRecord.weightKilograms
        let originalRecordedAt = persistedRecord.recordedAt
        let originalUpdatedAt = persistedRecord.updatedAt
        persistedRecord.weightKilograms = validatedWeight
        persistedRecord.recordedAt = recordedAt
        persistedRecord.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: persistedRecord.createdAt, previous: persistedRecord.updatedAt)
        do {
            try save()
        } catch {
            context.rollback()
            persistedRecord.weightKilograms = originalWeight
            persistedRecord.recordedAt = originalRecordedAt
            persistedRecord.updatedAt = originalUpdatedAt
            throw error
        }
    }

    func delete(_ record: WeightRecord) throws {
        guard let persistedRecord = try fetch(id: record.id) else {
            throw WeightValidationError.missingRecord
        }
        context.delete(persistedRecord)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchAll() throws -> [WeightRecord] {
        let records = try context.fetch(FetchDescriptor<WeightRecord>(
            sortBy: WeightRecordOrdering.newestFirstSortDescriptors
        ))
        return WeightRecordOrdering.newestFirst(records)
    }

    private func fetch(id: UUID) throws -> WeightRecord? {
        let requestedID = id
        var descriptor = FetchDescriptor<WeightRecord>(
            predicate: #Predicate { $0.id == requestedID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

struct TodayWeightSnapshot {
    let today: WeightRecord?
    let previous: WeightRecord?

    init(records: [WeightRecord], now: Date = Date(), calendar: Calendar = .current) {
        let ordered = WeightRecordOrdering.newestFirst(records).filter { $0.recordedAt <= now }
        today = ordered.first { calendar.isDate($0.recordedAt, inSameDayAs: now) }
        previous = ordered.first { $0.recordedAt < calendar.startOfDay(for: now) }
    }
}

// Weight has no saved LocalDay: freeze the current Gregorian zone for the entire snapshot.
enum WeightReviewRange: String, CaseIterable, Sendable, Identifiable {
    case week, month, quarter, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: String(localized: "Last 7 days")
        case .month: String(localized: "Last 30 days")
        case .quarter: String(localized: "Last 3 months")
        case .year: String(localized: "Last year")
        case .all: String(localized: "All time")
        }
    }
    func start(endExclusive: Date, calendar: Calendar, earliest: Date?) -> Date {
        let shifted: Date = switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: endExclusive)!
        case .month: calendar.date(byAdding: .day, value: -30, to: endExclusive)!
        case .quarter: calendar.date(byAdding: .month, value: -3, to: endExclusive)!
        case .year: calendar.date(byAdding: .year, value: -1, to: endExclusive)!
        case .all: earliest ?? calendar.date(byAdding: .day, value: -1, to: endExclusive)!
        }
        return calendar.startOfDay(for: shifted)
    }
}

struct WeightMeasurement: Identifiable, Equatable, Sendable {
    let id: UUID
    let kilograms: Double
    let recordedAt: Date
    let createdAt: Date
    init(id: UUID = UUID(), kilograms: Double, recordedAt: Date, createdAt: Date? = nil) {
        self.id = id; self.kilograms = kilograms; self.recordedAt = recordedAt; self.createdAt = createdAt ?? recordedAt
    }
    init(_ record: WeightRecord) {
        id = record.id; kilograms = record.weightKilograms; recordedAt = record.recordedAt; createdAt = record.createdAt
    }
    static func newer(_ a: Self, _ b: Self) -> Bool {
        if a.recordedAt != b.recordedAt { return a.recordedAt > b.recordedAt }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}

struct WeightDailyMean: Identifiable, Equatable, Sendable {
    let day: Date
    let mean: Double
    let observations: Int
    let segment: Int
    var id: Date { day }
}
struct WeightRangeSummary: Equatable, Sendable {
    let start: Date
    let endExclusive: Date
    let days: Int
    let observations: Int
    let mean: Double?
}
struct WeightReviewSnapshot: Sendable {
    let now: Date
    let calendar: Calendar
    let asOfDay: Date
    let endExclusive: Date
    let daily: [WeightDailyMean]
    let latest: [WeightMeasurement] // At most two real measurements, including same-day repeats.
    let summaries: [WeightReviewRange: WeightRangeSummary]
    let longestStreak: Int
    let endingStreak: Int
    let streakEnd: Date?
    var earliest: Date? { daily.first?.day }
    var recordedDays: Int { daily.count }
    var spanDays: Int { earliest.map { calendar.ordinality(of: .day, in: .era, for: asOfDay)! - calendar.ordinality(of: .day, in: .era, for: $0)! + 1 } ?? 0 }
    func points(_ range: WeightReviewRange) -> [WeightDailyMean] {
        guard let summary = summaries[range] else { return [] }
        return daily.filter { $0.day >= summary.start && $0.day < endExclusive }
    }
    func axis(range: WeightReviewRange, references: Set<WeightReviewRange>) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        let values = points(range).map(\.mean) + references.compactMap { summaries[$0]?.mean }
        guard let low = values.min(), let high = values.max() else { return (0...2, [0, 0.5, 1, 1.5, 2]) }
        let spread = max(high - low, 2)
        let padding = max(0.5, spread * 0.1)
        let desired = max(2, high - low + 2 * padding) / 5
        let step = [0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500].first { $0 >= desired } ?? 500
        let lower = max(0, floor((low - padding) / step) * step)
        let upper = max(lower + 2, ceil((high + padding) / step) * step)
        return (lower...upper, Array(stride(from: lower, through: upper, by: step)))
    }
}

/// Streaming builder retains one aggregate per date and two measurements, never full history rows.
struct WeightReviewBuilder {
    let now: Date
    let calendar: Calendar
    let asOfDay: Date
    let endExclusive: Date
    private var sums: [Date: (sum: Double, count: Int)] = [:]
    private var latest: [WeightMeasurement] = []
    init(now: Date, through: Date? = nil, timeZone: TimeZone = .current) {
        self.now = now
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        self.calendar = calendar
        asOfDay = calendar.startOfDay(for: through ?? now)
        endExclusive = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: asOfDay)!)
    }
    mutating func append(_ value: WeightMeasurement) {
        guard value.recordedAt <= now, value.recordedAt < endExclusive else { return }
        let day = calendar.startOfDay(for: value.recordedAt)
        var group = sums[day, default: (0, 0)]; group.sum += value.kilograms; group.count += 1; sums[day] = group
        latest.append(value); latest.sort(by: WeightMeasurement.newer); latest = Array(latest.prefix(2))
    }
    func snapshot() -> WeightReviewSnapshot {
        var previous: Date?, segment = 0, streak = 0, best = 0
        var daily: [WeightDailyMean] = []
        for day in sums.keys.sorted() {
            let adjacent = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }.map { calendar.startOfDay(for: $0) } == day
            if !adjacent { segment += 1; streak = 0 }
            streak += 1; best = max(best, streak)
            let group = sums[day]!
            daily.append(.init(day: day, mean: group.sum / Double(group.count), observations: group.count, segment: segment))
            previous = day
        }
        var summaries: [WeightReviewRange: WeightRangeSummary] = [:]
        for range in WeightReviewRange.allCases {
            let start = range.start(endExclusive: endExclusive, calendar: calendar, earliest: daily.first?.day)
            let selected = daily.filter { $0.day >= start && $0.day < endExclusive }
            summaries[range] = .init(start: start, endExclusive: endExclusive, days: selected.count,
                observations: selected.reduce(0) { $0 + $1.observations },
                mean: selected.isEmpty ? nil : selected.reduce(0) { $0 + $1.mean } / Double(selected.count))
        }
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: asOfDay)!)
        let activeEnd = previous == asOfDay || previous == yesterday ? previous : nil
        return .init(now: now, calendar: calendar, asOfDay: asOfDay, endExclusive: endExclusive, daily: daily, latest: latest,
            summaries: summaries, longestStreak: best, endingStreak: activeEnd == nil ? 0 : streak, streakEnd: activeEnd)
    }
}

/// Detached reader keeps multi-year fetch/aggregation off the UI executor. It never writes.
@ModelActor actor WeightReviewReader {
    func snapshot(now: Date, through: Date? = nil, zone: TimeZone = .current) throws -> WeightReviewSnapshot {
        modelContext.autosaveEnabled = false
        var builder = WeightReviewBuilder(now: now, through: through, timeZone: zone)
        let end = builder.endExclusive
        let query = FetchDescriptor<WeightRecord>(predicate: #Predicate { $0.recordedAt <= now && $0.recordedAt < end })
        try modelContext.enumerate(query, batchSize: 256) { record in
            try Task.checkCancellation(); builder.append(WeightMeasurement(record))
        }
        return builder.snapshot()
    }
    func records(start: Date? = nil, end: Date? = nil, now: Date, offset: Int = 0, limit: Int = 5) throws -> [WeightMeasurement] {
        modelContext.autosaveEnabled = false
        let lower = start ?? Date.distantPast, upper = end ?? Date.distantFuture
        var query = FetchDescriptor<WeightRecord>(predicate: #Predicate {
            $0.recordedAt >= lower && $0.recordedAt < upper && $0.recordedAt <= now
        }, sortBy: WeightRecordOrdering.newestFirstSortDescriptors)
        query.fetchOffset = max(0, offset); query.fetchLimit = max(1, min(limit, 50))
        try Task.checkCancellation()
        return try modelContext.fetch(query).map(WeightMeasurement.init)
    }
}

// Optional personal settings are created only by an explicit save, never by viewing a review.
@Model final class BodyReferenceSettings {
    static let singletonID=UUID(uuidString:"C8E99F09-842D-48A5-9825-D1CB981D2195")!
    @Attribute(.unique) var id: UUID
    var heightCentimeters: Double?
    var referenceRawValue: String
    init(heightCentimeters: Double?, reference: BMIReference = .china) {
        id=Self.singletonID;self.heightCentimeters=heightCentimeters;referenceRawValue=reference.rawValue
    }
}
enum BMIReference: String, Codable, CaseIterable {
    case china, who
    var thresholds: [Double] { self == .china ? [18.5,24,28] : [18.5,25,30] }
}
enum BMICategory: Int { case low, usual, elevated, high }
enum BMICalculation {
    /// Broad input guard in cm; this is an input constraint, not a reference for adult stature.
    static let heightRange=50.0...300.0
    static func value(kilograms: Double, centimeters: Double) -> Double? {
        guard kilograms.isFinite,kilograms > 0,centimeters.isFinite,heightRange.contains(centimeters) else {return nil}
        let result=kilograms / pow(centimeters / 100,2)
        return result.isFinite && result > 0 ? result : nil
    }
    static func category(_ value: Double, reference: BMIReference) -> BMICategory? {
        guard value.isFinite,value > 0 else {return nil}
        let limits=reference.thresholds
        if value < limits[0] {return .low}
        if value < limits[1] {return .usual}
        if value < limits[2] {return .elevated}
        return .high
    }
    /// Retain a short familiar value. An adjacent boundary hint carries the exact classification.
    static func boundaryHint(_ value: Double, reference: BMIReference) -> Double? {
        let displayed=(value * 10).rounded() / 10
        return reference.thresholds.first { value < $0 && displayed >= $0 }
    }
}

struct BodyReferencePreference: Equatable {
    var heightCentimeters: Double?
    var reference: BMIReference
}
enum BodyReferenceFailure: Error, LocalizedError {
    case invalidHeight, invalidSettings
    var errorDescription: String? {
        switch self {
        case .invalidHeight: return String(localized:"Enter a height from 50 to 300 cm. Use a decimal point or comma.")
        case .invalidSettings: return String(localized:"Could not read BMI settings. Retry before changing them.")
        }
    }
}
@MainActor enum BodyReferenceService {
    static func read(_ container: ModelContainer) throws -> BodyReferencePreference {
        let read=ModelContext(container)
        var query=FetchDescriptor<BodyReferenceSettings>();query.fetchLimit=2
        let rows=try read.fetch(query)
        guard rows.count <= 1 else {throw BodyReferenceFailure.invalidSettings}
        guard let row=rows.first else {return .init(reference:.china)}
        guard row.id == BodyReferenceSettings.singletonID,let reference=BMIReference(rawValue:row.referenceRawValue),
              row.heightCentimeters.map({$0.isFinite && BMICalculation.heightRange.contains($0)}) ?? true else {throw BodyReferenceFailure.invalidSettings}
        return .init(heightCentimeters:row.heightCentimeters,reference:reference)
    }
    static func height(from text: String) throws -> Double? {
        let text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else {return nil}
        guard let value=Double(text.replacingOccurrences(of:",",with:".")),value.isFinite,BMICalculation.heightRange.contains(value) else {throw BodyReferenceFailure.invalidHeight}
        return value
    }
    static func save(_ preference: BodyReferencePreference, container: ModelContainer) throws {
        if let height=preference.heightCentimeters, !height.isFinite || !BMICalculation.heightRange.contains(height) {throw BodyReferenceFailure.invalidHeight}
        _ = try read(container)
        let write=ModelContext(container);write.autosaveEnabled=false
        let rows=try write.fetch(FetchDescriptor<BodyReferenceSettings>())
        if preference.heightCentimeters == nil && preference.reference == .china {rows.forEach(write.delete)}
        else if let row=rows.first {row.heightCentimeters=preference.heightCentimeters;row.referenceRawValue=preference.reference.rawValue}
        else {write.insert(BodyReferenceSettings(heightCentimeters:preference.heightCentimeters,reference:preference.reference))}
        try write.save()
    }
}


/// A selection belongs to the calendar that produced its midnight. A zone refresh
/// returns to recent records instead of querying a partial day with an old instant.
enum WeightReviewSelection {
    static func retainedDay(_ day: Date?,previousZoneID: String?,calendar: Calendar) -> Date? {
        guard let day,previousZoneID == nil || previousZoneID == calendar.timeZone.identifier else {return nil}
        return calendar.startOfDay(for:day)
    }
}
