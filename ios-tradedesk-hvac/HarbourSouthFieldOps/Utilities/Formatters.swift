import Foundation

nonisolated enum Formatters {
    /// `code` is required on purpose. There is no default currency in this app:
    /// the caller must resolve the company's configured `currencyCode`, so USD
    /// can never be assumed by omission.
    static func currency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    static func currencyRounded(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func dayAndTime(_ date: Date) -> String {
        "\(dayTitle(date)) · \(time(date))"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func shortDayAndTime(_ date: Date) -> String {
        "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time(date))"
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }

    static func relativeDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours) hr" }
        return "\(hours) hrs \(mins) min"
    }

    static func durationLabel(from start: Date, to end: Date) -> String {
        relativeDuration(minutes: max(Int(end.timeIntervalSince(start) / 60), 0))
    }

    static func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// "Valid until Sep 9 · 14 days left" / "Expired 9 days ago".
    static func validityLabel(_ date: Date) -> String {
        let days = daysUntil(date)
        if days < 0 {
            let past = abs(days)
            return "Expired \(past) day\(past == 1 ? "" : "s") ago"
        }
        if days == 0 { return "Valid until today" }
        return "Valid until \(shortDate(date)) · \(days) day\(days == 1 ? "" : "s") left"
    }

    /// "Due in 6 days" / "Due today" / "14 days overdue". Used on invoices,
    /// where lateness is the thing the reader is looking for.
    static func dueLabel(_ date: Date) -> String {
        let days = daysUntil(date)
        if days < 0 {
            let late = abs(days)
            return "\(late) day\(late == 1 ? "" : "s") overdue"
        }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }

    /// Eight-point compass label for a heading in degrees.
    static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalised < 0 ? normalised + 360 : normalised
        let index = Int((positive / 45).rounded()) % points.count
        return points[index]
    }

    /// Speed in the units the company's country expects.
    static func speedLabel(_ metresPerSecond: Double, countryCode: String) -> String {
        let usesMiles = ["US", "GB", "LR", "MM"].contains(countryCode.uppercased())
        if usesMiles {
            return "\(Int((metresPerSecond * 2.23694).rounded())) mph"
        }
        return "\(Int((metresPerSecond * 3.6).rounded())) km/h"
    }

    static func coordinateLabel(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}
