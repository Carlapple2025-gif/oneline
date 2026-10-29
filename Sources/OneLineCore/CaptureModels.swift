import Foundation

/// 一条记录最终要写入的目的地。
public enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case event
    case reminder
    case note

    /// 类型前缀的短写法。
    public var sigil: String {
        switch self {
        case .event: return "c"
        case .reminder: return "r"
        case .note: return "n"
        }
    }
}

/// 提醒事项的优先级，rawValue 与 EventKit 的 EKReminderPriority 对齐。
public enum CapturePriority: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    public var shortLabel: String {
        switch self {
        case .none: return "无"
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    public static func fromExclamationCount(_ count: Int) -> CapturePriority {
        switch count {
        case 1: return .low
        case 2: return .medium
        case 3...: return .high
        default: return .none
        }
    }
}

/// 简单的重复规则，用于日历与提醒事项。
public enum CaptureRecurrence: Equatable, Sendable {
    case daily
    case weekly(weekday: Int?)   // 1 = 周日, 2 = 周一 ... 7 = 周六
    case monthly(day: Int)
    case yearly
}

/// 与具体 App 无关的时间结果。
public struct CaptureTiming: Equatable, Sendable {
    public var start: Date
    /// 仅日程使用。
    public var end: Date?
    /// 只精确到日（例如「明天」「全天」）。
    public var isAllDay: Bool
    public var hasExplicitTime: Bool
    public var hasExplicitDate: Bool
    /// 被识别并移除的原始时间文本，用于预览与调试。
    public var sourceText: String

    public init(
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        hasExplicitTime: Bool = false,
        hasExplicitDate: Bool = false,
        sourceText: String = ""
    ) {
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.hasExplicitTime = hasExplicitTime
        self.hasExplicitDate = hasExplicitDate
        self.sourceText = sourceText
    }
}

/// 解析成功后的完整记录。
public struct ParsedCapture: Equatable, Sendable {
    public var kind: CaptureKind
    public var title: String
    /// 首行之后的正文；备忘录直接作为正文，日程/待办作为备注。
    public var body: String
    public var tags: [String]
    /// `@工作`：日程指日历名，待办指清单名。
    public var listHint: String?
    public var priority: CapturePriority
    public var timing: CaptureTiming?
    public var recurrence: CaptureRecurrence?
    public var warnings: [String]
    public var rawInput: String

    public init(
        kind: CaptureKind,
        title: String,
        body: String = "",
        tags: [String] = [],
        listHint: String? = nil,
        priority: CapturePriority = .none,
        timing: CaptureTiming? = nil,
        recurrence: CaptureRecurrence? = nil,
        warnings: [String] = [],
        rawInput: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.tags = tags
        self.listHint = listHint
        self.priority = priority
        self.timing = timing
        self.recurrence = recurrence
        self.warnings = warnings
        self.rawInput = rawInput
    }

    /// 组合正文与标签，写入 EventKit 的 notes 字段。
    public var combinedNotes: String {
        var parts: [String] = []
        if !body.isEmpty { parts.append(body) }
        if !tags.isEmpty {
            parts.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: "\n")
    }
}

public enum CaptureParseError: Error, Equatable, LocalizedError, Sendable {
    case emptyInput
    case missingTitle

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "先写点什么吧"
        case .missingTitle:
            return "缺少标题，例如：c 产品评审 明天 14:00"
        }
    }
}
