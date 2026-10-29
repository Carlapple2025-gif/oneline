import Foundation
import OneLineCore

enum PrivacyTarget {
    case calendars
    case reminders
    case automation

    var settingsAnchor: String {
        switch self {
        case .calendars: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .automation: return "Privacy_Automation"
        }
    }
}

enum CaptureWriteError: LocalizedError {
    case calendarAccessDenied
    case reminderAccessDenied
    case noWritableCalendar
    case noWritableReminderList
    case notesAutomationDenied
    case notesFolderNotFound(String)
    case notesFailed(String)
    case eventKitFailed(String)

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            return "没有日历权限，无法写入日程"
        case .reminderAccessDenied:
            return "没有提醒事项权限，无法写入待办"
        case .noWritableCalendar:
            return "找不到可写入的日历，请先在日历 App 中创建一个日历"
        case .noWritableReminderList:
            return "找不到可写入的提醒清单，请先在提醒事项 App 中创建清单"
        case .notesAutomationDenied:
            return "没有控制「备忘录」的权限"
        case .notesFolderNotFound(let folder):
            return "备忘录文件夹「\(folder)」不存在"
        case .notesFailed(let message):
            return "写入备忘录失败：\(message)"
        case .eventKitFailed(let message):
            return "写入时出错：\(message)"
        }
    }

    var failureReason: String? {
        switch self {
        case .calendarAccessDenied, .reminderAccessDenied:
            return "请在系统设置 › 隐私与安全性中允许「一行」访问。"
        case .notesAutomationDenied:
            return "请在系统设置 › 隐私与安全性 › 自动化中勾选「备忘录」。"
        case .noWritableCalendar, .noWritableReminderList:
            return "也可以在一行设置里选择其他默认位置。"
        case .notesFolderNotFound:
            return "已尝试使用默认文件夹。"
        default:
            return nil
        }
    }

    var privacyTarget: PrivacyTarget? {
        switch self {
        case .calendarAccessDenied: return .calendars
        case .reminderAccessDenied: return .reminders
        case .notesAutomationDenied: return .automation
        default: return nil
        }
    }
}

struct CaptureDefaults {
    var calendarID: String?
    var reminderListID: String?
    var notesFolder: String?

    static let empty = CaptureDefaults(calendarID: nil, reminderListID: nil, notesFolder: nil)
}

struct CaptureReceipt {
    let kind: CaptureKind
    let title: String
    let destination: String
    let timing: CaptureTiming?
    let recurrence: CaptureRecurrence?
    let warnings: [String]
}
