import Foundation

enum ScheduleType: String, Codable, CaseIterable {
    case manual = "Manual"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case interval = "Interval"
}

struct TaskSchedule: Codable, Equatable {
    var type: ScheduleType = .daily
    var time: Date = Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()
    var weekdays: Set<Int> = [] // 1=Sunday, 7=Saturday
    var intervalMinutes: Int = 60

    var displaySummary: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        switch type {
        case .manual:
            return "Manual"
        case .daily:
            return "Daily at \(formatter.string(from: time))"
        case .weekly:
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let days = weekdays.sorted().compactMap { d in
                (1...7).contains(d) ? dayNames[d - 1] : nil
            }.joined(separator: ", ")
            return "\(days) at \(formatter.string(from: time))"
        case .monthly:
            let day = Calendar.current.component(.day, from: time)
            return "Monthly on day \(day) at \(formatter.string(from: time))"
        case .interval:
            if intervalMinutes < 60 {
                return "Every \(intervalMinutes) min"
            } else {
                let hours = intervalMinutes / 60
                return "Every \(hours) hr"
            }
        }
    }
}
