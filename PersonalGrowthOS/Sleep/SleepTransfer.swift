import Foundation
import SwiftData

struct SleepRecordTransfer: Codable, Equatable {
    var id: UUID
    var wakeDay: String
    var timeZoneID: String
    var values: SleepValues
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    var revision: Int
    init(_ record: SleepRecord) throws {
        id = record.id; wakeDay = record.wakeDay; timeZoneID = record.timeZoneID; values = try record.values()
        createdAt = record.createdAt; updatedAt = record.updatedAt; revision = record.revision
    }
    func model() throws -> SleepRecord {
        let record = try SleepRecord(id: id, wakeDay: wakeDay, timeZoneID: timeZoneID, values: values, createdAt: createdAt)
        record.updatedAt = updatedAt; record.revision = revision; return record
    }
}
struct SleepGoalTransfer: Codable, Equatable {
    var id: UUID
    var effectiveDay: String
    var cutoffMinute: Int?
    @TodoTransferInstant var createdAt: Date
    init(_ rule: SleepGoalRule) { id = rule.id; effectiveDay = rule.effectiveDay; cutoffMinute = rule.cutoffMinute; createdAt = rule.createdAt }
    func model() -> SleepGoalRule { SleepGoalRule(id: id, effectiveDay: effectiveDay, cutoffMinute: cutoffMinute, createdAt: createdAt) }
}
extension TransferData {
    func validateSleep(packageVersion: Int) throws {
        guard packageVersion >= 9 || (sleepRecords.isEmpty && sleepGoals.isEmpty),
              Set(sleepRecords.map(\.id)).count == sleepRecords.count,
              Set(sleepRecords.map(\.wakeDay)).count == sleepRecords.count,
              Set(sleepGoals.map(\.id)).count == sleepGoals.count,
              Set(sleepGoals.map(\.effectiveDay)).count == sleepGoals.count else { throw TransferPackageError.invalidObject("sleep identity") }
        for transfer in sleepRecords {
            try SleepRules.validate(day: transfer.wakeDay, zoneID: transfer.timeZoneID, values: transfer.values)
            guard transfer.revision >= 0, transfer.updatedAt >= transfer.createdAt,
                  transfer.createdAt.timeIntervalSinceReferenceDate.isFinite, transfer.updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw TransferPackageError.invalidObject("sleep timestamp") }
            let v = transfer.values
            for (exists, stamp) in [(v.bedtime != nil, v.bedtimeFilledAt), (v.wake != nil, v.wakeFilledAt), (v.feeling != nil, v.feelingFilledAt)] {
                guard exists || stamp == nil, stamp.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= transfer.createdAt && $0 <= transfer.updatedAt }) ?? true else { throw TransferPackageError.invalidObject("sleep field evidence") }
            }
        }
        for rule in sleepGoals {
            guard ImportantCivilDay(identifier: rule.effectiveDay) != nil, rule.cutoffMinute.map({ (0..<1440).contains($0) }) ?? true,
                  rule.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw TransferPackageError.invalidObject("sleep goal") }
        }
    }
    func insertSleep(into context: ModelContext) throws {
        for transfer in sleepRecords { try Task.checkCancellation(); context.insert(try transfer.model()) }
        for transfer in sleepGoals { try Task.checkCancellation(); context.insert(transfer.model()) }
    }
}
