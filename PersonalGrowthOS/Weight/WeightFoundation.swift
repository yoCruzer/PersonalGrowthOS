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
        persistedRecord.updatedAt = now()
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
