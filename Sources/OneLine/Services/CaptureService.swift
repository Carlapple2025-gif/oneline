import EventKit
import Foundation
import OneLineCore

@MainActor
final class CaptureService {
    private let eventKit: EventKitService
    private let permissions: PermissionCenter
    private let notes: NotesService

    init(eventKit: EventKitService, permissions: PermissionCenter, notes: NotesService) {
        self.eventKit = eventKit
        self.permissions = permissions
        self.notes = notes
    }

    func capture(_ capture: ParsedCapture, defaults: CaptureDefaults) async throws -> CaptureReceipt {
        switch capture.kind {
        case .event:
            return try await captureEvent(capture, defaults: defaults)
        case .reminder:
            return try await captureReminder(capture, defaults: defaults)
        case .note:
            return try captureNote(capture, defaults: defaults)
        }
    }

    // MARK: - 日程

    private func captureEvent(_ capture: ParsedCapture, defaults: CaptureDefaults) async throws -> CaptureReceipt {
        guard await permissions.requestAccess(for: .event) else {
            throw CaptureWriteError.calendarAccessDenied
        }
        guard let timing = capture.timing else {
            throw CaptureWriteError.eventKitFailed("没有可用的时间")
        }

        let resolved = eventKit.resolveEventCalendar(
            hint: capture.listHint,
            defaultID: defaults.calendarID
        )
        guard let calendar = resolved.calendar else {
            throw CaptureWriteError.noWritableCalendar
        }

        var warnings = capture.warnings
        if let hint = capture.listHint, !hint.isEmpty, !resolved.hintMatched {
            warnings.append("未找到日历「\(hint)」，已写入「\(calendar.title)」")
        }

        _ = try eventKit.saveEvent(
            title: capture.title,
            notes: capture.combinedNotes.isEmpty ? nil : capture.combinedNotes,
            timing: timing,
            recurrence: capture.recurrence,
            calendar: calendar
        )

        return CaptureReceipt(
            kind: .event,
            title: capture.title,
            destination: calendar.title,
            timing: timing,
            recurrence: capture.recurrence,
            warnings: warnings
        )
    }

    // MARK: - 待办

    private func captureReminder(_ capture: ParsedCapture, defaults: CaptureDefaults) async throws -> CaptureReceipt {
        guard await permissions.requestAccess(for: .reminder) else {
            throw CaptureWriteError.reminderAccessDenied
        }

        let resolved = eventKit.resolveReminderList(
            hint: capture.listHint,
            defaultID: defaults.reminderListID
        )
        guard let list = resolved.calendar else {
            throw CaptureWriteError.noWritableReminderList
        }

        var warnings = capture.warnings
        if let hint = capture.listHint, !hint.isEmpty, !resolved.hintMatched {
            warnings.append("未找到清单「\(hint)」，已写入「\(list.title)」")
        }

        _ = try eventKit.saveReminder(
            title: capture.title,
            notes: capture.combinedNotes.isEmpty ? nil : capture.combinedNotes,
            timing: capture.timing,
            priority: capture.priority,
            recurrence: capture.recurrence,
            list: list
        )

        return CaptureReceipt(
            kind: .reminder,
            title: capture.title,
            destination: list.title,
            timing: capture.timing,
            recurrence: capture.recurrence,
            warnings: warnings
        )
    }

    // MARK: - 备忘录

    private func captureNote(_ capture: ParsedCapture, defaults: CaptureDefaults) throws -> CaptureReceipt {
        let configuredFolder = defaults.notesFolder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (configuredFolder?.isEmpty ?? true) ? nil : configuredFolder

        let result = try notes.createNote(
            title: capture.title,
            body: capture.body,
            folder: folder
        )

        var warnings = capture.warnings
        if let folder, result.usedFolder == nil {
            warnings.append("未找到文件夹「\(folder)」，已保存到默认文件夹")
        }

        return CaptureReceipt(
            kind: .note,
            title: capture.title,
            destination: result.usedFolder ?? "备忘录",
            timing: nil,
            recurrence: nil,
            warnings: warnings
        )
    }
}
