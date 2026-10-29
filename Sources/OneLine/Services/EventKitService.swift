import EventKit
import Foundation
import OneLineCore

enum EventAccessState: Equatable {
    case notDetermined
    case granted
    case writeOnly
    case denied
    case restricted

    var isGranted: Bool { self == .granted }

    var label: String {
        switch self {
        case .notDetermined: return "未授权"
        case .granted: return "已授权"
        case .writeOnly: return "仅写入"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        }
    }
}

@MainActor
final class EventKitService {
    let store = EKEventStore()

    func accessState(for kind: CaptureKind) -> EventAccessState {
        guard kind != .note else { return .granted }
        let entityType: EKEntityType = kind == .event ? .event : .reminder
        switch EKEventStore.authorizationStatus(for: entityType) {
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    func requestFullAccess(for kind: CaptureKind) async -> Bool {
        guard kind != .note else { return true }
        return await withCheckedContinuation { continuation in
            if kind == .event {
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                store.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    var eventCalendars: [EKCalendar] {
        store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var reminderLists: [EKCalendar] {
        store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func resolveEventCalendar(hint: String?, defaultID: String?) -> (calendar: EKCalendar?, hintMatched: Bool) {
        resolveCalendar(hint: hint, defaultID: defaultID, from: eventCalendars, fallback: store.defaultCalendarForNewEvents)
    }

    func resolveReminderList(hint: String?, defaultID: String?) -> (calendar: EKCalendar?, hintMatched: Bool) {
        resolveCalendar(hint: hint, defaultID: defaultID, from: reminderLists, fallback: store.defaultCalendarForNewReminders())
    }

    private func resolveCalendar(
        hint: String?,
        defaultID: String?,
        from calendars: [EKCalendar],
        fallback: EKCalendar?
    ) -> (calendar: EKCalendar?, hintMatched: Bool) {
        if let hint, !hint.isEmpty {
            if let exact = calendars.first(where: {
                $0.title.compare(hint, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return (exact, true)
            }
            if let partial = calendars.first(where: {
                $0.title.localizedCaseInsensitiveContains(hint) || hint.localizedCaseInsensitiveContains($0.title)
            }) {
                return (partial, true)
            }
        }

        if let defaultID, !defaultID.isEmpty,
           let chosen = calendars.first(where: { $0.calendarIdentifier == defaultID }) {
            return (chosen, false)
        }

        if let fallback, fallback.allowsContentModifications {
            return (fallback, false)
        }

        return (calendars.first, false)
    }

    func saveEvent(
        title: String,
        notes: String?,
        timing: CaptureTiming,
        recurrence: CaptureRecurrence?,
        calendar: EKCalendar
    ) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.startDate = timing.start
        event.isAllDay = timing.isAllDay

        var end = timing.end ?? timing.start.addingTimeInterval(3600)
        if timing.isAllDay {
            if end <= timing.start {
                end = Calendar.current.date(byAdding: .day, value: 1, to: timing.start) ?? end
            }
        } else if end <= timing.start {
            end = timing.start.addingTimeInterval(3600)
        }
        event.endDate = end

        if let recurrence, let rule = Self.recurrenceRule(for: recurrence) {
            event.recurrenceRules = [rule]
        }

        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw CaptureWriteError.eventKitFailed(error.localizedDescription)
        }
        return event
    }

    func saveReminder(
        title: String,
        notes: String?,
        timing: CaptureTiming?,
        priority: CapturePriority,
        recurrence: CaptureRecurrence?,
        list: EKCalendar
    ) throws -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority.rawValue

        if let timing {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: timing.start
            )
            if timing.isAllDay {
                components.hour = nil
                components.minute = nil
            }
            reminder.dueDateComponents = components
            if !timing.isAllDay {
                // 带具体时间的待办加一个「到点提醒」，否则提醒事项只会显示截止时间，不会通知。
                reminder.addAlarm(EKAlarm(relativeOffset: 0))
            }
        }

        if let recurrence, let rule = Self.recurrenceRule(for: recurrence) {
            reminder.recurrenceRules = [rule]
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw CaptureWriteError.eventKitFailed(error.localizedDescription)
        }
        return reminder
    }

    static func recurrenceRule(for recurrence: CaptureRecurrence) -> EKRecurrenceRule? {
        switch recurrence {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly(let weekday):
            if let weekday, let day = EKWeekday(rawValue: weekday) {
                let dayOfWeek = EKRecurrenceDayOfWeek(dayOfTheWeek: day, weekNumber: 0)
                return EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    daysOfTheWeek: [dayOfWeek],
                    daysOfTheMonth: nil,
                    monthsOfTheYear: nil,
                    weeksOfTheYear: nil,
                    daysOfTheYear: nil,
                    setPositions: nil,
                    end: nil
                )
            }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly(let day):
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: day)],
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }
}
