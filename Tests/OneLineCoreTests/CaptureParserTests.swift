import XCTest
@testable import OneLineCore

final class CaptureParserTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var parser: CaptureParser!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        // 2026-10-27 是星期二。
        now = makeDate(2026, 10, 27, 8, 31)
        parser = CaptureParser(now: now, calendar: calendar)
    }

    // MARK: - 主流程

    func testFullEventSyntax() {
        let capture = parse("c 产品评审 明天 14:00-15:00 @工作 #评审")
        XCTAssertEqual(capture.kind, .event)
        XCTAssertEqual(capture.title, "产品评审")
        XCTAssertEqual(capture.listHint, "工作")
        XCTAssertEqual(capture.tags, ["评审"])
        XCTAssertFalse(capture.timing?.isAllDay ?? true)
        assertDate(capture.timing?.start, 2026, 10, 28, 14, 0)
        assertDate(capture.timing?.end, 2026, 10, 28, 15, 0)
        XCTAssertTrue(capture.warnings.isEmpty)
    }

    func testReminderSyntax() {
        let capture = parse("r 买牛奶 明天 18:00 @购物 !!")
        XCTAssertEqual(capture.kind, .reminder)
        XCTAssertEqual(capture.title, "买牛奶")
        XCTAssertEqual(capture.listHint, "购物")
        XCTAssertEqual(capture.priority, .medium)
        assertDate(capture.timing?.start, 2026, 10, 28, 18, 0)
        XCTAssertNil(capture.timing?.end)
    }

    func testNoteKeepsContentVerbatim() {
        let capture = parse("n 读书笔记 #Swift\n并发章节：actor 与 Sendable")
        XCTAssertEqual(capture.kind, .note)
        XCTAssertEqual(capture.title, "读书笔记 #Swift")
        XCTAssertEqual(capture.body, "并发章节：actor 与 Sendable")
        XCTAssertNil(capture.timing)
        XCTAssertNil(capture.recurrence)
        XCTAssertTrue(capture.tags.isEmpty)
    }

    func testDefaultKindIsReminder() {
        let capture = parse("买牛奶 明天")
        XCTAssertEqual(capture.kind, .reminder)
        XCTAssertEqual(capture.title, "买牛奶")
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 28, nil, nil)
    }

    func testChinesePrefix() {
        let capture = parse("待办：买牛奶 明天")
        XCTAssertEqual(capture.kind, .reminder)
        XCTAssertEqual(capture.title, "买牛奶")
    }

    func testMarkdownCheckboxPrefix() {
        let capture = parse("- [ ] 买牛奶 明天")
        XCTAssertEqual(capture.kind, .reminder)
        XCTAssertEqual(capture.title, "买牛奶")
    }

    func testEmojiPrefix() {
        let capture = parse("📅 产品评审 明天 14:00")
        XCTAssertEqual(capture.kind, .event)
        XCTAssertEqual(capture.title, "产品评审")
    }

    func testPrefixOnlyThenContentOnNextLine() {
        let capture = parse("r\n买牛奶 明天")
        XCTAssertEqual(capture.kind, .reminder)
        XCTAssertEqual(capture.title, "买牛奶")
        assertDate(capture.timing?.start, 2026, 10, 28, nil, nil)
    }

    // MARK: - 时间

    func testTimeOnlyUsesNextOccurrence() {
        assertDate(parse("r 站会 9:00").timing?.start, 2026, 10, 27, 9, 0)
        assertDate(parse("r 跑步 7:00").timing?.start, 2026, 10, 28, 7, 0)
    }

    func testThreeOClockDefaultsToAfternoon() {
        assertDate(parse("c 评审 3点").timing?.start, 2026, 10, 27, 15, 0)
        assertDate(parse("c 评审 下午3点").timing?.start, 2026, 10, 27, 15, 0)
        assertDate(parse("c 评审 凌晨3点").timing?.start, 2026, 10, 28, 3, 0)
    }

    func testTonight() {
        assertDate(parse("c 电影 今晚8点").timing?.start, 2026, 10, 27, 20, 0)
    }

    func testTomorrowMorningImpliedTime() {
        let capture = parse("r 跑步 明早")
        XCTAssertFalse(capture.timing?.isAllDay ?? true)
        assertDate(capture.timing?.start, 2026, 10, 28, 9, 0)
    }

    func testTomorrowAfternoonImpliedTime() {
        assertDate(parse("c 讨论 明天下午").timing?.start, 2026, 10, 28, 14, 0)
    }

    func testNextMonday() {
        assertDate(parse("c 周会 下周一 10:00").timing?.start, 2026, 11, 2, 10, 0)
    }

    func testBareWeekdayRollsForwardWhenTimePassed() {
        // 今天是周二 08:31；周二 07:00 已过，应排到下周二。
        assertDate(parse("c 周会 周二 07:00").timing?.start, 2026, 11, 3, 7, 0)
        // 今天周二 10:00 还没到。
        assertDate(parse("c 周会 周二 10:00").timing?.start, 2026, 10, 27, 10, 0)
    }

    func testAbsoluteDates() {
        let capture = parse("r 体检 11月5日 09:30")
        assertDate(capture.timing?.start, 2026, 11, 5, 9, 30)

        let iso = parse("c 评审 2026-12-01 14:00")
        assertDate(iso.timing?.start, 2026, 12, 1, 14, 0)

        let slash = parse("c 评审 12/02 14:00")
        assertDate(slash.timing?.start, 2026, 12, 2, 14, 0)
    }

    func testPastMonthDayRollsToNextYear() {
        assertDate(parse("r 年检 1月5日").timing?.start, 2027, 1, 5, nil, nil)
    }

    func testPastDayOfMonthRollsToNextMonth() {
        assertDate(parse("r 交房租 5号").timing?.start, 2026, 11, 5, nil, nil)
    }

    func testAllDayEvent() {
        let capture = parse("c 团建 后天 全天")
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 29, 0, 0)
        assertDate(capture.timing?.end, 2026, 10, 30, 0, 0)
    }

    func testDuration() {
        let capture = parse("c 写文档 明天 14:00 2小时")
        assertDate(capture.timing?.start, 2026, 10, 28, 14, 0)
        assertDate(capture.timing?.end, 2026, 10, 28, 16, 0)
    }

    func testDurationOnlyStartsNow() {
        let capture = parse("c 写文档 1小时")
        XCTAssertNotNil(capture.timing)
        XCTAssertFalse(capture.timing?.isAllDay ?? true)
        XCTAssertEqual(capture.timing?.end?.timeIntervalSince(capture.timing!.start), 3600)
    }

    func testTimeRangeAcrossMidnight() {
        let capture = parse("c 夜班 明天 23:00-1:00")
        assertDate(capture.timing?.start, 2026, 10, 28, 23, 0)
        assertDate(capture.timing?.end, 2026, 10, 29, 1, 0)
    }

    func testInvalidDateFallsBackWithWarning() {
        let capture = parse("c 测试 2月30日")
        XCTAssertEqual(capture.title, "测试")
        XCTAssertTrue(capture.warnings.contains(where: { $0.contains("不是有效日期") }))
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
    }

    // MARK: - 重复

    func testWeeklyRecurrence() {
        let capture = parse("c 周会 每周五 10:00")
        XCTAssertEqual(capture.recurrence, .weekly(weekday: 6))
        assertDate(capture.timing?.start, 2026, 10, 30, 10, 0)
    }

    func testMonthlyRecurrence() {
        let capture = parse("r 交房租 每月1号")
        XCTAssertEqual(capture.recurrence, .monthly(day: 1))
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 11, 1, nil, nil)
    }

    func testDailyRecurrenceWithTimeRollsToTomorrow() {
        let capture = parse("r 吃药 每天 8:00")
        XCTAssertEqual(capture.recurrence, .daily)
        assertDate(capture.timing?.start, 2026, 10, 28, 8, 0)
    }

    // MARK: - 清理

    func testTitleOnlyEventGetsTodayAllDay() {
        let capture = parse("c 买花")
        XCTAssertEqual(capture.title, "买花")
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 27, 0, 0)
        XCTAssertTrue(capture.warnings.contains(where: { $0.contains("今天全天") }))
    }

    func testReminderWithoutDateStaysInInbox() {
        let capture = parse("r 买牛奶")
        XCTAssertEqual(capture.title, "买牛奶")
        XCTAssertNil(capture.timing)
    }

    func testEmailIsNotAList() {
        let capture = parse("r 发邮件给 a@b.com @工作 #办公")
        XCTAssertEqual(capture.listHint, "工作")
        XCTAssertEqual(capture.tags, ["办公"])
        XCTAssertEqual(capture.title, "发邮件给 a@b.com")
    }

    func testURLFragmentIsNotATag() {
        let capture = parse("r 看链接 https://example.com/a#b #工作")
        XCTAssertEqual(capture.tags, ["工作"])
        XCTAssertEqual(capture.title, "看链接 https://example.com/a#b")
    }

    func testQuotedListName() {
        let capture = parse("c 评审 @\"工作 日历\" 明天")
        XCTAssertEqual(capture.listHint, "工作 日历")
        XCTAssertEqual(capture.title, "评审")
    }

    func testTagsWithPunctuation() {
        let capture = parse("r 整理资料 #工作，明天")
        XCTAssertEqual(capture.tags, ["工作"])
        XCTAssertEqual(capture.title, "整理资料")
    }

    func testEmptyInput() {
        if case .failure(let error) = parser.parse("   ") {
            XCTAssertEqual(error, .emptyInput)
        } else {
            XCTFail("空输入应当失败")
        }
    }

    func testPrefixOnlyFails() {
        if case .failure(let error) = parser.parse("c 明天 14:00") {
            XCTAssertEqual(error, .missingTitle)
        } else {
            XCTFail("缺少标题应当失败")
        }
    }

    func testEnglishTitle() {
        let capture = parse("c Call with Bob 明天 10:00")
        XCTAssertEqual(capture.kind, .event)
        XCTAssertEqual(capture.title, "Call with Bob")
        assertDate(capture.timing?.start, 2026, 10, 28, 10, 0)
    }

    func testBodyBecomesNotesAndTagsAreAppended() {
        let capture = parse("c 评审 明天 14:00 #重要\n带上原型图")
        XCTAssertEqual(capture.title, "评审")
        XCTAssertEqual(capture.body, "带上原型图")
        XCTAssertEqual(capture.combinedNotes, "带上原型图\n#重要")
    }


    func testTimeOnlyRangeShiftsBothStartAndEnd() {
        let lateParser = CaptureParser(now: makeDate(2026, 10, 27, 23, 45), calendar: calendar)
        let capture = parse("c 夜班 23:30-00:30", using: lateParser)
        assertDate(capture.timing?.start, 2026, 10, 28, 23, 30)
        assertDate(capture.timing?.end, 2026, 10, 29, 0, 30)
    }

    func testAllDayWithoutDateDoesNotWarn() {
        let capture = parse("c 买花 全天")
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 27, nil, nil)
        XCTAssertTrue(capture.warnings.isEmpty)
    }

    func testAllDayReminderWithoutDateUsesToday() {
        let capture = parse("r 买牛奶 全天")
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 27, nil, nil)
    }

    func testTitleStartingWithParenthesesIsPreserved() {
        let capture = parse("c (临时) 会议 明天 14:00")
        XCTAssertEqual(capture.title, "(临时) 会议")
    }

    func testAllDayWordInsideTitleIsPreserved() {
        let capture = parse("c 全天候支持 明天")
        XCTAssertEqual(capture.title, "全天候支持")
    }

    // MARK: - Helpers

    private func parse(
        _ input: String,
        defaultKind: CaptureKind = .reminder,
        using customParser: CaptureParser? = nil
    ) -> ParsedCapture {
        let parser = customParser ?? self.parser!
        switch parser.parse(input, defaultKind: defaultKind) {
        case .success(let capture):
            return capture
        case .failure(let error):
            XCTFail("解析失败：\(error.localizedDescription) — \(input)")
            fatalError("parse failed")
        }
    }


    // MARK: - 边界与重复

    func testWeeklyWithoutWeekdayAnchorsToToday() {
        let lateParser = CaptureParser(now: makeDate(2026, 10, 27, 11, 0), calendar: calendar)
        let capture = parse("c 周会 每周 10:00", using: lateParser)
        XCTAssertEqual(capture.recurrence, .weekly(weekday: nil))
        assertDate(capture.timing?.start, 2026, 11, 3, 10, 0)
    }

    func testYearlyRecurrence() {
        let capture = parse("c 纪念日 每年10月1日")
        XCTAssertEqual(capture.recurrence, .yearly)
        assertDate(capture.timing?.start, 2027, 10, 1, nil, nil)
    }

    func testDailyReminderWithoutTime() {
        let capture = parse("r 吃药 每天")
        XCTAssertEqual(capture.recurrence, .daily)
        XCTAssertTrue(capture.timing?.isAllDay ?? false)
        assertDate(capture.timing?.start, 2026, 10, 27, nil, nil)
    }

    func testSundayNextMonday() {
        let sundayParser = CaptureParser(now: makeDate(2026, 10, 25, 10, 0), calendar: calendar)
        let capture = parse("c 周会 下周一 10:00", using: sundayParser)
        assertDate(capture.timing?.start, 2026, 10, 26, 10, 0)
    }

    func testHyphenRangeIsNotADate() {
        let capture = parse("c 预订5-6人包间 明天")
        XCTAssertEqual(capture.title, "预订5-6人包间")
        assertDate(capture.timing?.start, 2026, 10, 28, nil, nil)
    }

    func testPunctuationSeparatedMetadata() {
        let capture = parse("r 整理资料，#工作，@工作清单 明天")
        XCTAssertEqual(capture.title, "整理资料")
        XCTAssertEqual(capture.tags, ["工作"])
        XCTAssertEqual(capture.listHint, "工作清单")
        assertDate(capture.timing?.start, 2026, 10, 28, nil, nil)
    }

    func testHighPriority() {
        let capture = parse("r 交报告 明天 !!!")
        XCTAssertEqual(capture.priority, .high)
        XCTAssertEqual(capture.title, "交报告")
    }

    func testChineseTimeWithQuarter() {
        assertDate(parse("c 评审 明天 下午3点一刻").timing?.start, 2026, 10, 28, 15, 15)
    }

    func testCrossMidnightChineseTime() {
        let capture = parse("c 夜班 明天 晚上11点-1点")
        assertDate(capture.timing?.start, 2026, 10, 28, 23, 0)
        assertDate(capture.timing?.end, 2026, 10, 29, 1, 0)
    }

    func testDefaultKindEvent() {
        let capture = parse("产品评审 明天 14:00", defaultKind: .event)
        XCTAssertEqual(capture.kind, .event)
        XCTAssertEqual(capture.title, "产品评审")
        assertDate(capture.timing?.start, 2026, 10, 28, 14, 0)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func assertDate(
        _ date: Date?,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int?,
        _ minute: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date else {
            XCTFail("日期为空", file: file, line: line)
            return
        }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        if let hour {
            XCTAssertEqual(components.hour, hour, file: file, line: line)
        }
        if let minute {
            XCTAssertEqual(components.minute, minute, file: file, line: line)
        }
    }
}
