import Foundation

struct SleepReviewNight: Identifiable {
    let record: SleepRecordTransfer
    var id: UUID { record.id }
    let bedtime: SleepRange?
    let wake: SleepRange?
    let interval: ClosedRange<TimeInterval>?
    let feeling: Int?
    let goal: SleepGoalResult
    let fieldTimings: [SleepFieldTiming]
    /// Civil minutes relative to wake-day midnight; 23:30 then 00:30 stays -30 then +30.
    func axis(_ range: SleepRange) -> ClosedRange<Int>? {
        guard let start = ImportantCivilDay(identifier: range.day), let wake = ImportantCivilDay(identifier: record.wakeDay),
              let days = wake.distance(to: start) else { return nil }
        let lower = days * 1440 + range.minute
        return lower...(lower + range.precision)
    }
}
struct SleepReviewSnapshot {
    let windowDays: Int
    let nights: [SleepReviewNight]
    /// Keep complete recorded buckets visible, including a late wake range ending next day.
    var axisHourDomain: ClosedRange<Double> {
        var lower = -24.0, upper = 24.0
        for night in nights {
            for value in [night.bedtime, night.wake] {
                guard let value, let axis = night.axis(value) else { continue }
                lower = min(lower, Double(axis.lowerBound) / 60)
                upper = max(upper, Double(axis.upperBound) / 60)
            }
        }
        return lower...upper
    }
    var recordedDays: Int { nights.count }
    var bedtimeCount: Int { nights.filter { $0.bedtime != nil }.count }
    var wakeCount: Int { nights.filter { $0.wake != nil }.count }
    var intervalCount: Int { nights.filter { $0.interval != nil }.count }
    var feelingCount: Int { nights.filter { $0.feeling != nil }.count }
    func count(timing: SleepFieldTiming) -> Int { nights.flatMap(\.fieldTimings).filter { $0 == timing }.count }
    func count(feeling: Int) -> Int { nights.filter { $0.feeling == feeling }.count }
    func count(goal: SleepGoalResult) -> Int { nights.filter { $0.goal == goal }.count }
    init(records: [SleepRecordTransfer], goals: [SleepGoalRule], windowDays: Int, today: ImportantCivilDay, now: Date) {
        self.windowDays = windowDays
        let start = today.adding(days: -(windowDays - 1))!.identifier
        nights = records.filter { $0.wakeDay >= start && $0.wakeDay <= today.identifier }.sorted { $0.wakeDay > $1.wakeDay }.compactMap { record in
            guard let zone = TimeZone(identifier: record.timeZoneID) else { return nil }
            let v = record.values
            let bt = SleepRules.timing(v.bedtimeFilledAt, day: record.wakeDay, zone: zone, now: now)
            let wt = SleepRules.timing(v.wakeFilledAt, day: record.wakeDay, zone: zone, now: now)
            let ft = SleepRules.timing(v.feelingFilledAt, day: record.wakeDay, zone: zone, now: now)
            return SleepReviewNight(record: record, bedtime: bt.included ? v.bedtime : nil, wake: wt.included ? v.wake : nil,
                interval: bt.included && wt.included ? SleepRules.interval(v, zone: zone) : nil,
                feeling: ft.included ? v.feeling : nil,
                goal: SleepRules.goal(day: record.wakeDay, zone: zone, values: v, rules: goals, now: now),
                fieldTimings: [(v.bedtime != nil, bt), (v.wake != nil, wt), (v.feeling != nil, ft)].compactMap { $0.0 ? $0.1 : nil })
        }
    }
}
