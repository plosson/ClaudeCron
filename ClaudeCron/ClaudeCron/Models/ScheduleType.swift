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
}
