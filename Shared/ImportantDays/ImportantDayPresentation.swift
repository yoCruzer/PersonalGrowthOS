import Foundation

extension ImportantDayPreset {
    var label: String {
        switch self {
        case .anticipated: String(localized: "Look forward to a day")
        case .beginning: String(localized: "Remember a beginning")
        case .anniversary: String(localized: "Celebrate each year")
        }
    }
}
extension ImportantDayTodayPolicy {
    var label: String {
        switch self {
        case .automatic: String(localized: "Automatic · next 7 days")
        case .always: String(localized: "Always in Today")
        case .hidden: String(localized: "Hidden from Today")
        }
    }
}
extension ImportantDayCalendar {
    var label: String { self == .gregorian ? String(localized: "Gregorian") : String(localized: "Chinese lunar · Shanghai") }
}
extension ImportantDayDateRule {
    var dateDescription: String {
        let yearText = year.map(String.init) ?? String(localized: "Year unknown")
        let leap = isLeapMonth ? String(localized: "Leap month") : ""
        return "\(calendar.label) · \(yearText) · \(leap) \(month)/\(day)"
    }
    var exceptionDescription: String {
        [leapDayRule?.label, leapMonthRule?.label, shortMonthRule?.label].compactMap { $0 }.joined(separator: " · ")
    }
    func distanceDescription(today: ImportantCivilDay) -> String {
        guard let result = try? ImportantDayDateEngine.evaluate(self, today: today) else { return String(localized: "Date outside supported range or invalid") }
        if result.signedDays == 0 { return String(localized: "It is today") }
        if result.signedDays > 0 { return String(localized: "In \(result.signedDays) days") }
        if preset == .anticipated { return String(localized: "Planned day passed \(-result.signedDays) days ago") }
        return String(localized: "\(-result.signedDays) days elapsed")
    }
}
extension ImportantLeapDayRule {
    var label: String {
        switch self {
        case .february28: String(localized: "February 28 in common years")
        case .march1: String(localized: "March 1 in common years")
        case .leapYearsOnly: String(localized: "Leap years only")
        }
    }
}
extension ImportantLeapMonthRule {
    var label: String { self == .regularFallback ? String(localized: "Leap month, otherwise the regular month") : String(localized: "Matching leap month only") }
}
extension ImportantShortMonthRule {
    var label: String { self == .lastDay ? String(localized: "Use the last day of a short month") : String(localized: "Skip years without this day") }
}
