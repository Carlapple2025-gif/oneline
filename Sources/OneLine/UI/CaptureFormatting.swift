import Foundation
import OneLineCore
import SwiftUI

enum CaptureFormatting {
    static func kindName(_ kind: CaptureKind) -> String {
        switch kind {
        case .event: return "日历"
        case .reminder: return "待办"
        case .note: return "备忘录"
        }
    }

    static func destinationName(_ kind: CaptureKind) -> String {
        switch kind {
        case .event: return "日程"
        case .reminder: return "待办"
        case .note: return "笔记"
        }
    }

    static func icon(_ kind: CaptureKind) -> String {
        switch kind {
        case .event: return "calendar"
        case .reminder: return "checkmark.circle"
        case .note: return "note.text"
        }
    }

    static func color(_ kind: CaptureKind) -> Color {
        switch kind {
        case .event: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .reminder: return Color(red: 0.95, green: 0.53, blue: 0.18)
        case .note: return Color(red: 0.82, green: 0.64, blue: 0.18)
        }
    }

    static func dayLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let target = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case 3: return "大后天"
        case -1: return "昨天"
        case -2: return "前天"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = calendar
            if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
                formatter.dateFormat = "M月d日 EEE"
            } else {
                formatter.dateFormat = "yyyy年M月d日 EEE"
            }
            return formatter.string(from: date)
        }
    }

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func timingLine(kind: CaptureKind, timing: CaptureTiming?, recurrence: CaptureRecurrence?) -> String {
        guard let timing else {
            return kind == .reminder ? "无截止时间" : "未设置时间"
        }
        var parts: [String] = []
        let day = dayLabel(for: timing.start)

        switch kind {
        case .event:
            if timing.isAllDay {
                parts.append("\(day) · 全天")
            } else {
                let start = timeLabel(timing.start)
                if let end = timing.end {
                    let endDay = dayLabel(for: end)
                    if Calendar.current.isDate(timing.start, inSameDayAs: end) {
                        parts.append("\(day) \(start)–\(timeLabel(end))")
                    } else {
                        parts.append("\(day) \(start) – \(endDay) \(timeLabel(end))")
                    }
                } else {
                    parts.append("\(day) \(start)")
                }
            }
        case .reminder:
            if timing.isAllDay {
                parts.append("\(day) · 全天")
            } else {
                parts.append("\(day) \(timeLabel(timing.start))")
            }
        case .note:
            break
        }

        if let recurrence {
            parts.append(recurrenceLabel(recurrence))
        }
        return parts.joined(separator: " · ")
    }

    static func recurrenceLabel(_ recurrence: CaptureRecurrence) -> String {
        switch recurrence {
        case .daily:
            return "每天"
        case .weekly(let weekday):
            if let weekday, let name = weekdayName(weekday) {
                return "每周\(name)"
            }
            return "每周"
        case .monthly(let day):
            return "每月\(day)号"
        case .yearly:
            return "每年"
        }
    }

    static func weekdayName(_ weekday: Int) -> String? {
        switch weekday {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return nil
        }
    }

    static func priorityLabel(_ priority: CapturePriority) -> String? {
        switch priority {
        case .none: return nil
        case .high: return "高优先级"
        case .medium: return "中优先级"
        case .low: return "低优先级"
        }
    }
}
