import Foundation

/// 统一语法解析器。
///
/// 语法：
/// `[类型] 标题 [日期/时间] [@清单或日历] [#标签] [!优先级]`
///
/// 类型前缀支持：
/// - `c` / `cal` / `calendar` / `日程:` / `日历:` / `会议:` / `📅`
/// - `r` / `todo` / `remind` / `待办:` / `提醒:` / `✅` / `[ ]`
/// - `n` / `note` / `memo` / `备忘:` / `笔记:` / `📝`
public struct CaptureParser {
    public let now: Date
    public let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public func parse(_ input: String, defaultKind: CaptureKind = .reminder) -> Result<ParsedCapture, CaptureParseError> {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return .failure(.emptyInput) }

        var lines = normalized.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return .failure(.emptyInput) }

        var head = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        var body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = parsePrefix(in: &head)
        let kind = prefix ?? defaultKind

        // 允许只写类型前缀，内容写在第二行。
        if head.isEmpty, !body.isEmpty {
            var bodyLines = body.components(separatedBy: "\n")
            head = bodyLines.removeFirst().trimmingCharacters(in: .whitespaces)
            body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if kind == .note {
            guard !head.isEmpty else { return .failure(.missingTitle) }
            return .success(
                ParsedCapture(
                    kind: .note,
                    title: head,
                    body: body,
                    warnings: [],
                    rawInput: normalized
                )
            )
        }

        var tags: [String] = []
        var listHint: String?
        var priority: CapturePriority = .none
        var warnings: [String] = []

        takeTags(&tags, from: &head)
        listHint = takeListHint(from: &head)

        if kind == .reminder {
            if let count = takePriority(from: &head) {
                priority = CapturePriority.fromExclamationCount(count)
            }
        }

        let scanned = DateExpressionScanner(now: now, calendar: calendar).scan(&head, for: kind)
        warnings.append(contentsOf: scanned.warnings)

        let title = cleanTitle(head)
        guard !title.isEmpty else { return .failure(.missingTitle) }

        return .success(
            ParsedCapture(
                kind: kind,
                title: title,
                body: body,
                tags: tags,
                listHint: listHint,
                priority: priority,
                timing: scanned.timing,
                recurrence: scanned.recurrence,
                warnings: warnings,
                rawInput: normalized
            )
        )
    }

    // MARK: - 类型前缀

    private func parsePrefix(in head: inout String) -> CaptureKind? {
        let pattern = #"""
        (?x)^\s*(?:
          \[(c|cal|calendar|r|remind|reminder|todo|n|note|memo|日程|日历|会议|待办|提醒|备忘|备忘录|笔记)\]\s*
         |(c|cal|calendar|r|remind|reminder|todo|n|note|memo)(?=\s|[:：]|$)\s*[:：]?\s*
         |(日程|日历|会议|待办|提醒|备忘|备忘录|笔记)\s*[:：]\s*
         |(📅|🗓️|🗓|✅|☑️|📝|🗒️|🗒)\s*[:：]?\s*
         |(?:[-*]\s*)?\[\s*\]\s*
        )
        """#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) else {
            return nil
        }

        let ns = head as NSString
        var matchedKind: CaptureKind?
        var isMarkdownTask = false

        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { continue }
            let token = ns.substring(with: range)
            if token.contains("[") || token.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if let kind = kind(forPrefixToken: token) {
                matchedKind = kind
                break
            }
        }

        if let full = Range(match.range, in: head) {
            if matchedKind == nil, head[full].contains("[") {
                isMarkdownTask = true
            }
            head.removeSubrange(full)
        }

        if isMarkdownTask { return .reminder }
        head = head.trimmingCharacters(in: .whitespaces)
        return matchedKind
    }

    private func kind(forPrefixToken token: String) -> CaptureKind? {
        switch token.lowercased() {
        case "c", "cal", "calendar", "日程", "日历", "会议", "📅", "🗓", "🗓️":
            return .event
        case "r", "remind", "reminder", "todo", "待办", "提醒", "✅", "☑️":
            return .reminder
        case "n", "note", "memo", "备忘", "备忘录", "笔记", "📝", "🗒", "🗒️":
            return .note
        default:
            return nil
        }
    }

    // MARK: - 元信息

    private func takeTags(_ tags: inout [String], from text: inout String) {
        for _ in 0..<20 {
            guard let found = firstMatch(#"(?:^|[\s，,、；;])#([\p{L}\p{N}_-]{1,40})"#, in: text),
                  let tag = found.groups[1] else { return }
            if !tags.contains(tag) {
                tags.append(tag)
            }
            text.removeSubrange(found.range)
        }
    }

    private func takeListHint(from text: inout String) -> String? {
        guard let found = firstMatch(#"(?:^|[\s，,、；;])@(?:"([^"]+)"|([\p{L}\p{N}_\-\.]+))"#, in: text) else {
            return nil
        }
        let hint = found.groups[1] ?? found.groups[2]
        text.removeSubrange(found.range)
        return hint
    }

    private func takePriority(from text: inout String) -> Int? {
        if let found = firstMatch(#"(!{1,3})\s*$"#, in: text) {
            text.removeSubrange(found.range)
            return found.groups[1]?.count
        }
        if let found = firstMatch(#"(?:^|\s)(!{1,3})(?=\s|$)"#, in: text) {
            text.removeSubrange(found.range)
            return found.groups[1]?.count
        }
        return nil
    }

    // MARK: - 文本工具

    private func cleanTitle(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "-–—,，.。;；:：、|/")
        )
        result = result.trimmingCharacters(in: separators)
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatch(_ pattern: String, in text: String) -> (groups: [String?], range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let range = Range(match.range, in: text) else { return nil }

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
}
