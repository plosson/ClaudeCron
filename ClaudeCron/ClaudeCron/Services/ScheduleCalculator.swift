import Foundation

struct ScheduleCalculator {
    static func nextRuns(for schedule: TaskSchedule, count: Int = 5) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var candidate = Date()

        for _ in 0..<(count * 30) {
            guard dates.count < count else { break }

            switch schedule.type {
            case .daily:
                let h = calendar.component(.hour, from: schedule.time)
                let m = calendar.component(.minute, from: schedule.time)
                var next = calendar.date(bySettingHour: h, minute: m, second: 0, of: candidate)!
                if next <= Date() { next = calendar.date(byAdding: .day, value: 1, to: next)! }
                if !dates.contains(next) { dates.append(next) }
                candidate = calendar.date(byAdding: .day, value: 1, to: next)!

            case .weekly:
                let h = calendar.component(.hour, from: schedule.time)
                let m = calendar.component(.minute, from: schedule.time)
                let weekday = calendar.component(.weekday, from: candidate)
                if schedule.weekdays.contains(weekday) {
                    var next = calendar.date(bySettingHour: h, minute: m, second: 0, of: candidate)!
                    if next > Date() && !dates.contains(next) { dates.append(next) }
                }
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!

            case .interval:
                let next = dates.last ?? Date()
                let upcoming = next.addingTimeInterval(Double(schedule.intervalMinutes * 60))
                dates.append(upcoming)
                candidate = upcoming

            case .monthly:
                let h = calendar.component(.hour, from: schedule.time)
                let m = calendar.component(.minute, from: schedule.time)
                let d = calendar.component(.day, from: schedule.time)
                var comps = calendar.dateComponents([.year, .month], from: candidate)
                comps.day = d
                comps.hour = h
                comps.minute = m
                comps.second = 0
                if let next = calendar.date(from: comps), next > Date(), !dates.contains(next) {
                    dates.append(next)
                }
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate)!

            case .manual:
                return dates
            }
        }
        return dates
    }
}
