import Foundation

/// 识别一行文本中的日期、时间、时长和重复规则，并把识别到的片段从文本中移除。
///
/// 设计原则：
/// - 所有时间都使用 `calendar` 的时区来解析，便于测试。
/// - 识别顺序经过安排，避免「每周五」被拆成「每周」+「周五」。
/// - 无法识别的日期不会静默改动文本，而是记录 warning。
struct DateExpressionScanner {
    let now: Date
    let calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    struct Output {
        var timing: CaptureTiming?
        var recurrence: CaptureRecurrence?
        var warnings: [String]
    }

    // MARK: - 中间状态

    private enum WeekdayMode {
        case bare
        case thisWeek
        case nextWeek
        case weekAfterNext
    }

    private enum DayPeriod {
        case earlyMorning
        case morning
        case noon
        case afternoon
        case evening

        var impliedTime: (hour: Int, minute: Int) {
            switch self {
            case .earlyMorning: return (6, 0)
            case .morning: return (9, 0)
            case .noon: return (12, 0)
            case .afternoon: return (14, 0)
            case .evening: return (20, 0)
            }
        }
    }

    private struct RawTime {
        var hour: Int
        var minute: Int
        var period: DayPeriod?
        var text: String
    }

    private struct State {
        var absoluteDay: Date?
        var relativeOffset: Int?
        var weekdayTarget: Int?
        var weekdayMode: WeekdayMode?
        var monthDay: Int?
        var recurrence: CaptureRecurrence?

        var startTime: RawTime?
        var endTime: RawTime?
        var duration: TimeInterval?
        var allDay = false
        var impliedPeriod: DayPeriod?
        var hasExplicitTime = false
        var hasExplicitDate = false
        var matchedTexts: [String] = []
        var warnings: [String] = []
    }

    // MARK: - 入口

    func scan(_ line: inout String, for kind: CaptureKind) -> Output {
        var state = State()

        takeAllDay(&state, from: &line)
        takeTimeRange(&state, from: &line)
        if state.startTime == nil {
            takeSingleTime(&state, from: &line)
        }
        if kind == .event {
            takeDuration(&state, from: &line)
        }
        takeRecurrence(&state, from: &line)
        takeRelativeDay(&state, from: &line)
        takeWeekday(&state, from: &line)
        takeAbsoluteDate(&state, from: &line)

        let result = resolve(state, for: kind)
        return Output(
            timing: result.timing,
            recurrence: result.recurrence,
            warnings: result.warnings
        )
    }

    // MARK: - 各类表达式

    private func takeAllDay(_ state: inout State, from text: inout String) {
        if let match = take(#"(?i)(?:全\s*天(?!候)|整\s*天|all\s*-?\s*day)"#, from: &text) {
            state.allDay = true
            state.matchedTexts.append(match[0] ?? "全天")
        }
    }

    private func takeTimeRange(_ state: inout State, from text: inout String) {
        let token = timeTokenPattern()
        let pattern = "\(token)\\s*(?:-|–|—|~|～|到|至)\\s*\(token)"
        guard let found = firstMatch(pattern, in: text), let whole = found.groups[0] else { return }

        guard let separator = firstSeparatorRange(in: whole) else { return }
        let ns = whole as NSString
        let left = ns.substring(to: separator.location)
        let right = ns.substring(from: separator.location + separator.length)

        guard let start = parseTime(left), let rawEnd = parseTime(right) else { return }

        var end = rawEnd
        if end.period == nil {
            end.period = start.period
        }
        state.startTime = start
        state.endTime = end
        state.hasExplicitTime = true
        state.matchedTexts.append(whole)
        text.removeSubrange(found.range)
    }

    private func takeSingleTime(_ state: inout State, from text: inout String) {
        guard let found = firstMatch(timeTokenPattern(), in: text),
              let whole = found.groups[0],
              let time = parseTime(whole) else { return }
        state.startTime = time
        state.hasExplicitTime = true
        state.matchedTexts.append(whole)
        text.removeSubrange(found.range)
    }

    private func takeDuration(_ state: inout State, from text: inout String) {
        var total: TimeInterval = 0
        var found = false

        for _ in 0..<3 {
            if let match = take(#"(\d+)\s*个\s*半\s*(?:小时|钟头)"#, from: &text),
               let number = match[1].flatMap(Int.init) {
                total += Double(number) * 3600 + 1800
                found = true
                state.matchedTexts.append(match[0] ?? "")
                continue
            }
            if let match = take(#"(\d+(?:\.\d+)?)\s*(?:个)?\s*(?:小时|钟头|h\b)"#, from: &text),
               let number = match[1].flatMap(Double.init) {
                total += number * 3600
                found = true
                state.matchedTexts.append(match[0] ?? "")
                continue
            }
            if let match = take(#"(\d+)\s*(?:分钟|min\b|m\b)"#, from: &text),
               let number = match[1].flatMap(Double.init) {
                total += number * 60
                found = true
                state.matchedTexts.append(match[0] ?? "")
                continue
            }
            if let match = take(#"半\s*小时"#, from: &text) {
                total += 1800
                found = true
                state.matchedTexts.append(match[0] ?? "")
                continue
            }
            break
        }

        if found, total > 0 {
            state.duration = total
        }
    }

    private func takeRecurrence(_ state: inout State, from text: inout String) {
        if let match = take(#"每(?:天|日)"#, from: &text) {
            state.recurrence = .daily
            state.matchedTexts.append(match[0] ?? "每天")
            return
        }

        if let match = take(#"每(?:个)?(?:周|星期|礼拜)\s*([一二三四五六日天1-7])?"#, from: &text) {
            let weekday = match[1].flatMap(weekdayNumber)
            state.recurrence = .weekly(weekday: weekday)
            if let weekday {
                state.weekdayTarget = weekday
                state.weekdayMode = .bare
                state.hasExplicitDate = true
            } else {
                // 没写星期几的「每周」以今天为锚点；若今天的时刻已过，后面会顺延一周。
                state.weekdayTarget = calendar.component(.weekday, from: now)
                state.weekdayMode = .bare
                state.hasExplicitDate = true
            }
            state.matchedTexts.append(match[0] ?? "")
            return
        }

        if let match = take(#"每(?:个)?月\s*(\d{1,2})\s*[日号]?"#, from: &text) {
            if let day = match[1].flatMap(Int.init), (1...31).contains(day) {
                state.recurrence = .monthly(day: day)
                state.monthDay = day
                state.hasExplicitDate = true
                state.matchedTexts.append(match[0] ?? "")
            } else {
                state.warnings.append("「\(match[0] ?? "")」不是有效的每月日期，已忽略")
                state.matchedTexts.append(match[0] ?? "")
            }
            return
        }

        if let match = take(#"每(?:个)?年(?:\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?)?"#, from: &text) {
            state.recurrence = .yearly
            if let month = match[1].flatMap(Int.init), let day = match[2].flatMap(Int.init) {
                if let date = nextYearDate(month: month, day: day) {
                    state.absoluteDay = date
                    state.hasExplicitDate = true
                } else {
                    state.warnings.append("「\(month)月\(day)日」不是有效日期，已忽略")
                }
            }
            state.matchedTexts.append(match[0] ?? "每年")
        }
    }

    private func takeRelativeDay(_ state: inout State, from text: inout String) {
        let pattern = #"(大后天|后天|明天|明日|明儿|今天|今日|今儿|今晚|今早|今晨|明晚|明早|昨天|昨日|前天)\s*(凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜间)?"#
        if let match = take(pattern, from: &text), let word = match[0] {
            let token = match[1] ?? ""
            var offset = 0
            var period: DayPeriod?

            switch token {
            case "大后天": offset = 3
            case "后天": offset = 2
            case "明天", "明日", "明儿": offset = 1
            case "今天", "今日", "今儿": offset = 0
            case "今晚": offset = 0; period = .evening
            case "今早", "今晨": offset = 0; period = .morning
            case "明晚": offset = 1; period = .evening
            case "明早": offset = 1; period = .morning
            case "昨天", "昨日": offset = -1
            case "前天": offset = -2
            default: offset = 0
            }

            if let periodWord = match[2] {
                period = dayPeriod(from: periodWord)
            }
            state.relativeOffset = offset
            state.impliedPeriod = period
            state.hasExplicitDate = true
            state.matchedTexts.append(word)
            return
        }

        if let match = take(#"(\d{1,2})\s*天(?:之)?后"#, from: &text), let days = match[1].flatMap(Int.init) {
            state.relativeOffset = days
            state.hasExplicitDate = true
            state.matchedTexts.append(match[0] ?? "")
            return
        }
        if let match = take(#"(\d{1,2})\s*天(?:之)?前"#, from: &text), let days = match[1].flatMap(Int.init) {
            state.relativeOffset = -days
            state.hasExplicitDate = true
            state.matchedTexts.append(match[0] ?? "")
        }
    }

    private func takeWeekday(_ state: inout State, from text: inout String) {
        let pattern = #"(下下|下|这|本)?\s*(?:周|星期|礼拜)\s*([一二三四五六日天1-7])"#
        guard let match = take(pattern, from: &text),
              let weekdayText = match[2],
              let weekday = weekdayNumber(weekdayText) else { return }

        let mode: WeekdayMode
        switch match[1] {
        case "下下": mode = .weekAfterNext
        case "下": mode = .nextWeek
        case "这", "本": mode = .thisWeek
        default: mode = .bare
        }

        state.weekdayTarget = weekday
        state.weekdayMode = mode
        state.hasExplicitDate = true
        state.matchedTexts.append(match[0] ?? "")
    }

    private func takeAbsoluteDate(_ state: inout State, from text: inout String) {
        if let match = take(#"(?<!\d)(\d{4})\s*(?:年|[-/.])\s*(\d{1,2})\s*(?:月|[-/.])\s*(\d{1,2})\s*[日号]?"#, from: &text),
           let year = match[1].flatMap(Int.init),
           let month = match[2].flatMap(Int.init),
           let day = match[3].flatMap(Int.init) {
            if let date = makeDate(year: year, month: month, day: day) {
                state.absoluteDay = date
                state.hasExplicitDate = true
            } else {
                state.warnings.append("「\(match[0] ?? "")」不是有效日期，已改用今天")
            }
            state.matchedTexts.append(match[0] ?? "")
            return
        }

        if let match = take(#"(?<!\d)(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#, from: &text),
           let month = match[1].flatMap(Int.init),
           let day = match[2].flatMap(Int.init) {
            if let date = nextMonthDayDate(month: month, day: day) {
                state.absoluteDay = date
                state.hasExplicitDate = true
            } else {
                state.warnings.append("「\(match[0] ?? "")」不是有效日期，已改用今天")
            }
            state.matchedTexts.append(match[0] ?? "")
            return
        }

        if let match = take(#"(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)"#, from: &text),
           let month = match[1].flatMap(Int.init),
           let day = match[2].flatMap(Int.init) {
            if let date = nextMonthDayDate(month: month, day: day) {
                state.absoluteDay = date
                state.hasExplicitDate = true
            } else {
                state.warnings.append("「\(match[0] ?? "")」不是有效日期，已改用今天")
            }
            state.matchedTexts.append(match[0] ?? "")
            return
        }

        if let match = take(#"(?<!\d)(\d{1,2})\s*[日号](?!线)"#, from: &text),
           let day = match[1].flatMap(Int.init) {
            if let date = nextDayOfMonthDate(day: day) {
                state.absoluteDay = date
                state.hasExplicitDate = true
            } else {
                state.warnings.append("「\(day)号」不是有效日期，已忽略")
            }
            state.matchedTexts.append(match[0] ?? "")
        }
    }

    // MARK: - 解析结果

    private func resolve(_ state: State, for kind: CaptureKind) -> (timing: CaptureTiming?, recurrence: CaptureRecurrence?, warnings: [String]) {
        var warnings = state.warnings

        var day: Date?
        var dayIsImplicit = false

        if let absoluteDay = state.absoluteDay {
            day = absoluteDay
        } else if let offset = state.relativeOffset {
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        } else if let target = state.weekdayTarget, let mode = state.weekdayMode {
            day = weekdayDate(target: target, mode: mode)
        } else if let monthDay = state.monthDay {
            day = nextDayOfMonthDate(day: monthDay)
        } else {
            day = calendar.startOfDay(for: now)
            dayIsImplicit = true
        }

        guard let day else {
            warnings.append("没有识别到日期，已使用今天")
            return (nil, state.recurrence, warnings)
        }

        // 无日期、无时间、无时长：日程默认今天全天；待办只留在收件箱。
        if kind == .reminder, !state.hasExplicitDate, state.startTime == nil, state.duration == nil,
           state.recurrence == nil, !state.allDay {
            return (nil, state.recurrence, warnings)
        }

        var startMinutes: Int?
        var hasExplicitTime = state.hasExplicitTime
        if let start = state.startTime {
            let hour = normalizedHour(start, fallback: state.impliedPeriod)
            startMinutes = hour * 60 + start.minute
        } else if let period = state.impliedPeriod {
            let implied = period.impliedTime
            startMinutes = implied.hour * 60 + implied.minute
            hasExplicitTime = true
        }

        var isAllDay = state.allDay || (startMinutes == nil && !dayIsImplicit)
        if kind == .event, startMinutes == nil, state.duration != nil {
            isAllDay = false
        }

        var startDate: Date
        var endDate: Date?

        if let startMinutes {
            let hour = startMinutes / 60
            let minute = startMinutes % 60
            startDate = date(on: day, hour: hour, minute: minute)
            isAllDay = false

            if dayIsImplicit {
                // 只写时间时，选择最近一次未来时间。
                if startDate < now {
                    startDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                }
            } else if state.weekdayMode == .bare, state.weekdayTarget != nil, state.absoluteDay == nil, state.relativeOffset == nil {
                // 只说「周二」时，如果今天就是周二且时间已过，顺延一周。
                if startDate < now {
                    startDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate) ?? startDate
                }
            }
        } else if kind == .event, dayIsImplicit, let duration = state.duration {
            startDate = roundedNow()
            endDate = startDate.addingTimeInterval(duration)
            isAllDay = false
        } else {
            startDate = calendar.startOfDay(for: day)
            isAllDay = true
            if dayIsImplicit, kind == .event, !state.allDay {
                warnings.append("没有识别到日期，已设为今天全天")
            }
        }

        if state.allDay {
            isAllDay = true
            startDate = calendar.startOfDay(for: day)
            startMinutes = nil
        }

        // 重复规则的第一次发生时间尽量落在未来。
        if let recurrence = state.recurrence {
            startDate = advanceRecurrenceStartIfNeeded(
                startDate,
                recurrence: recurrence,
                isAllDay: isAllDay
            )
        }

        if kind == .event {
            if isAllDay {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate)
            } else if let end = state.endTime {
                let endHour = normalizedHour(end, fallback: state.startTime?.period ?? state.impliedPeriod)
                var endMinutes = endHour * 60 + end.minute
                if let startMinutes, endMinutes <= startMinutes,
                   startMinutes >= 18 * 60, end.hour <= 6 {
                    // 跨午夜：23:00 - 1:00。
                    endMinutes = end.hour * 60 + end.minute
                }
                let startDay = calendar.startOfDay(for: startDate)
                var candidateEnd = date(on: startDay, hour: endMinutes / 60, minute: endMinutes % 60)
                if candidateEnd <= startDate {
                    candidateEnd = calendar.date(byAdding: .day, value: 1, to: candidateEnd) ?? candidateEnd
                }
                endDate = candidateEnd
            } else if let duration = state.duration {
                endDate = startDate.addingTimeInterval(duration)
            } else {
                endDate = startDate.addingTimeInterval(3600)
            }
        }

        let timing = CaptureTiming(
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            hasExplicitTime: hasExplicitTime || state.allDay,
            hasExplicitDate: state.hasExplicitDate,
            sourceText: state.matchedTexts.joined(separator: " ")
        )

        return (timing, state.recurrence, warnings)
    }

    private func roundedNow() -> Date {
        let interval: TimeInterval = 300
        return Date(timeIntervalSinceReferenceDate: ceil(now.timeIntervalSinceReferenceDate / interval) * interval)
    }

    private func advanceRecurrenceStartIfNeeded(_ start: Date, recurrence: CaptureRecurrence, isAllDay: Bool) -> Date {
        guard start < now else { return start }
        // 今天的全天重复项目仍然算今天，不往后跳。
        if isAllDay, calendar.isDate(start, inSameDayAs: now) {
            return start
        }

        var candidate = start
        for _ in 0..<400 {
            switch recurrence {
            case .daily:
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return candidate }
                candidate = next
            case .weekly:
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) else { return candidate }
                candidate = next
            case .monthly:
                guard let next = calendar.date(byAdding: .month, value: 1, to: candidate) else { return candidate }
                candidate = next
            case .yearly:
                guard let next = calendar.date(byAdding: .year, value: 1, to: candidate) else { return candidate }
                candidate = next
            }
            if candidate >= now { return candidate }
        }
        return candidate
    }

    // MARK: - 日期计算

    private func weekdayDate(target: Int, mode: WeekdayMode) -> Date? {
        let today = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: today)

        switch mode {
        case .bare:
            let diff = (target - currentWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: diff, to: today)
        case .thisWeek:
            let start = startOfWeek(containing: today)
            let offset = (target - calendar.component(.weekday, from: start) + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: start)
        case .nextWeek:
            let start = startOfWeek(containing: today)
            let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let offset = (target - calendar.component(.weekday, from: next) + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: next)
        case .weekAfterNext:
            let start = startOfWeek(containing: today)
            let next = calendar.date(byAdding: .weekOfYear, value: 2, to: start) ?? start
            let offset = (target - calendar.component(.weekday, from: next) + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: next)
        }
    }

    /// 以周一为一周的开始（符合中文习惯）。
    private func startOfWeek(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = 周日
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: calendar.startOfDay(for: date)) ?? date
    }

    private func nextMonthDayDate(month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: today)
        for yearOffset in 0..<8 {
            if let date = makeDate(year: currentYear + yearOffset, month: month, day: day) {
                if date >= today { return date }
            }
        }
        return nil
    }

    private func nextYearDate(month: Int, day: Int) -> Date? {
        nextMonthDayDate(month: month, day: day)
    }

    private func nextDayOfMonthDate(day: Int) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return nil
        }
        for monthOffset in 0..<14 {
            guard let start = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) else { continue }
            if let date = makeDate(
                year: calendar.component(.year, from: start),
                month: calendar.component(.month, from: start),
                day: day
            ) {
                if date >= today { return date }
            }
        }
        return nil
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    // MARK: - 时间片段

    private func timeTokenPattern() -> String {
        let period = #"(?:凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜间)"#
        let clock = #"(?:[01]?\d|2[0-3])\s*[:：]\s*[0-5]\d"#
        let chinese = #"(?<!第)(?<!第\s)\d{1,2}\s*点(?:\s*(?:半|一刻|三刻|\d{1,2}\s*分?))?"#
        return #"(?:(?:\#(period))\s*)?(?:\#(clock)|\#(chinese))"#
    }

    private func parseTime(_ text: String) -> RawTime? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var period: DayPeriod?

        for word in ["凌晨", "清晨", "早上", "早晨", "上午", "中午", "下午", "傍晚", "晚上", "夜里", "夜间"] {
            if working.hasPrefix(word) {
                period = dayPeriod(from: word)
                working.removeFirst(word.count)
                working = working.trimmingCharacters(in: .whitespaces)
                break
            }
        }

        let pattern = #"^(?:(\d{1,2})\s*[:：]\s*(\d{2})|(\d{1,2})\s*点(?:\s*(半|一刻|三刻|(\d{1,2})\s*分?))?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: working, range: NSRange(location: 0, length: (working as NSString).length)) else {
            return nil
        }
        let ns = working as NSString

        func group(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: index))
        }

        var hour: Int?
        var minute = 0

        if let hourText = group(1), let minuteText = group(2) {
            hour = Int(hourText)
            minute = Int(minuteText) ?? 0
        } else if let hourText = group(3) {
            hour = Int(hourText)
            switch group(4) {
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default:
                minute = group(5).flatMap(Int.init) ?? 0
            }
        }

        guard let hour, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return RawTime(hour: hour, minute: minute, period: period, text: text)
    }

    private func normalizedHour(_ time: RawTime, fallback: DayPeriod?) -> Int {
        let period = time.period ?? fallback
        let hour = time.hour

        switch period {
        case .earlyMorning, .morning:
            return hour == 12 ? 0 : hour
        case .noon:
            return hour < 11 ? hour + 12 : hour
        case .afternoon, .evening:
            if hour == 12 { return 0 }
            return hour < 12 ? hour + 12 : hour
        case nil:
            // 「3点」按下午处理；凌晨时间请显式写「凌晨3点」。
            if (1...6).contains(hour) { return hour + 12 }
            return hour
        }
    }

    private func dayPeriod(from word: String) -> DayPeriod? {
        switch word {
        case "凌晨", "清晨": return .earlyMorning
        case "早上", "早晨", "上午": return .morning
        case "中午": return .noon
        case "下午": return .afternoon
        case "傍晚", "晚上", "夜里", "夜间": return .evening
        default: return nil
        }
    }

    private func firstSeparatorRange(in text: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"\s*(?:-|–|—|~|～|到|至)\s*"#) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))?.range
    }

    private func weekdayNumber(_ text: String) -> Int? {
        switch text {
        case "一", "1": return 2
        case "二", "2": return 3
        case "三", "3": return 4
        case "四", "4": return 5
        case "五", "5": return 6
        case "六", "6": return 7
        case "日", "天", "7": return 1
        default: return nil
        }
    }

    // MARK: - 文本摘除

    /// 找到第一个匹配，但不修改原文本。
    private func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> (groups: [String?], range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        var groups: [String?] = []
        for index in 0..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            if groupRange.location == NSNotFound {
                groups.append(nil)
            } else {
                groups.append(ns.substring(with: groupRange))
            }
        }
        return (groups, range)
    }

    /// 摘除第一个匹配；返回 [完整匹配, 捕获组...]。匹配失败返回 nil。
    private func take(_ pattern: String, from text: inout String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String?]? {
        guard let found = firstMatch(pattern, in: text, options: options) else { return nil }
        text.removeSubrange(found.range)
        return found.groups
    }
}
