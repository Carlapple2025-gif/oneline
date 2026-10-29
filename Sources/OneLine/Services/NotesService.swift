import AppKit
import Foundation

@MainActor
final class NotesService {
    struct NoteResult {
        let noteID: String?
        let usedFolder: String?
    }

    func createNote(title: String, body: String, folder: String?) throws -> NoteResult {
        let html = Self.htmlBody(from: body)
        let escapedTitle = Self.appleScriptString(title)
        let escapedBody = Self.appleScriptString(html)

        if let folder, !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let result = try runScript(
                    folder: trimmedFolder,
                    title: escapedTitle,
                    body: escapedBody
                )
                return NoteResult(noteID: result, usedFolder: trimmedFolder)
            } catch let error as NotesScriptError {
                if error.kind == .folderNotFound {
                    // 配置的文件夹可能被改名或删除，退回默认文件夹，避免丢内容。
                    let result = try runScript(folder: nil, title: escapedTitle, body: escapedBody)
                    return NoteResult(noteID: result, usedFolder: nil)
                }
                throw error.captureWriteError
            }
        }

        do {
            let result = try runScript(folder: nil, title: escapedTitle, body: escapedBody)
            return NoteResult(noteID: result, usedFolder: nil)
        } catch let error as NotesScriptError {
            throw error.captureWriteError
        }
    }

    private func runScript(folder: String?, title: String, body: String) throws -> String? {
        let scriptSource: String
        if let folder {
            scriptSource = """
            tell application "Notes"
                set targetFolder to folder "\(folder)"
                set newNote to make new note at targetFolder with properties {name:"\(title)", body:"\(body)"}
                return id of newNote as text
            end tell
            """
        } else {
            scriptSource = """
            tell application "Notes"
                set newNote to make new note with properties {name:"\(title)", body:"\(body)"}
                return id of newNote as text
            end tell
            """
        }

        guard let script = NSAppleScript(source: scriptSource) else {
            throw NotesScriptError(kind: .other, message: "无法创建 AppleScript")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "未知错误"

            if number == -1743 || message.localizedCaseInsensitiveContains("not authorized") ||
                message.localizedCaseInsensitiveContains("not permitted") {
                throw NotesScriptError(kind: .automationDenied, message: message)
            }
            if number == -1728 || message.localizedCaseInsensitiveContains("can’t get folder") ||
                message.localizedCaseInsensitiveContains("can't get folder") {
                throw NotesScriptError(kind: .folderNotFound, message: message)
            }
            throw NotesScriptError(kind: .other, message: message)
        }

        return result.stringValue
    }

    private static func htmlBody(from body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        let rendered = lines.map { line -> String in
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<div>\(escaped.isEmpty ? "<br>" : escaped)</div>"
        }.joined()
        return "<html><body>\(rendered)</body></html>"
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

private struct NotesScriptError: Error {
    enum Kind {
        case automationDenied
        case folderNotFound
        case other
    }

    let kind: Kind
    let message: String

    var captureWriteError: CaptureWriteError {
        switch kind {
        case .automationDenied:
            return .notesAutomationDenied
        case .folderNotFound:
            return .notesFailed(message.isEmpty ? "找不到备忘录文件夹" : message)
        case .other:
            return .notesFailed(message)
        }
    }
}
