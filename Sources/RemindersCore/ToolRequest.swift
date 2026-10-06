import Foundation
import MCP

/// Raised when a tool call's arguments are missing or malformed.
public struct ArgumentError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum DueUpdate: Equatable {
    case clear
    case set(DueDate)
}

/// A validated, strongly-typed tool call. Parsing and validation live here so they
/// can be unit-tested without touching EventKit.
public enum ToolRequest: Equatable {
    case listLists
    case listReminders(list: String, includeCompleted: Bool)
    case createReminder(title: String, list: String, notes: String?, due: DueDate?, priority: Int?)
    case completeReminder(id: String)
    case moveReminder(id: String, targetList: String, appendNotes: String?)
    case updateReminder(id: String, title: String?, notes: String?, due: DueUpdate?, priority: Int?)
    case deleteReminder(id: String)
    case searchReminders(query: String, list: String?)

    public static func parse(
        name: String,
        arguments: [String: Value]?,
        timeZone: TimeZone = .current
    ) throws -> ToolRequest {
        guard let tool = ToolName(rawValue: name) else {
            throw ArgumentError("Unknown tool '\(name)'.")
        }
        let a = Arguments(arguments ?? [:], timeZone: timeZone)

        switch tool {
        case .listLists:
            return .listLists

        case .listReminders:
            return .listReminders(
                list: try a.requiredString("list"),
                includeCompleted: try a.bool("include_completed") ?? false)

        case .createReminder:
            return .createReminder(
                title: try a.requiredString("title"),
                list: try a.requiredString("list"),
                notes: try a.string("notes"),
                due: try a.dueDate("due_date"),
                priority: try a.priority("priority"))

        case .completeReminder:
            return .completeReminder(id: try a.requiredString("id"))

        case .moveReminder:
            let append = try a.string("append_notes")
            return .moveReminder(
                id: try a.requiredString("id"),
                targetList: try a.requiredString("target_list"),
                appendNotes: (append?.isEmpty ?? true) ? nil : append)

        case .updateReminder:
            let id = try a.requiredString("id")
            let title = try a.string("title")
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ArgumentError("'title' must not be empty.")
            }
            let notes = try a.string("notes")
            let due = try a.dueUpdate("due_date")
            let priority = try a.priority("priority")
            if title == nil, notes == nil, due == nil, priority == nil {
                throw ArgumentError(
                    "Nothing to update: pass at least one of title, notes, due_date, priority.")
            }
            return .updateReminder(id: id, title: title, notes: notes, due: due, priority: priority)

        case .deleteReminder:
            let id = try a.requiredString("id")
            guard try a.bool("confirm") == true else {
                throw ArgumentError("Delete is permanent: pass confirm=true to proceed.")
            }
            return .deleteReminder(id: id)

        case .searchReminders:
            return .searchReminders(
                query: try a.requiredString("query"),
                list: try a.string("list"))
        }
    }
}

/// Typed accessors over the raw MCP argument dictionary. Clients differ in whether
/// they send booleans/integers natively or as strings, so both forms are accepted.
struct Arguments {
    let raw: [String: Value]
    let timeZone: TimeZone

    init(_ raw: [String: Value], timeZone: TimeZone = .current) {
        self.raw = raw
        self.timeZone = timeZone
    }

    private func value(_ key: String) -> Value? {
        guard let v = raw[key], !v.isNull else { return nil }
        return v
    }

    func string(_ key: String) throws -> String? {
        guard let v = value(key) else { return nil }
        switch v {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: throw ArgumentError("'\(key)' must be a string.")
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ArgumentError("'\(key)' is required.") }
        return s
    }

    func bool(_ key: String) throws -> Bool? {
        guard let v = value(key) else { return nil }
        switch v {
        case .bool(let b): return b
        case .string(let s):
            switch s.lowercased() {
            case "true": return true
            case "false": return false
            default: throw ArgumentError("'\(key)' must be true or false.")
            }
        default: throw ArgumentError("'\(key)' must be true or false.")
        }
    }

    /// 0 = none, 1 = high, 5 = medium, 9 = low (EventKit's scale; 1-4 are all "high", 6-9 "low").
    func priority(_ key: String) throws -> Int? {
        guard let v = value(key) else { return nil }
        let parsed: Int?
        switch v {
        case .int(let i): parsed = i
        case .string(let s): parsed = Int(s.trimmingCharacters(in: .whitespaces))
        default: parsed = nil
        }
        guard let p = parsed, (0...9).contains(p) else {
            throw ArgumentError("'\(key)' must be an integer from 0 to 9 (1=high, 5=medium, 9=low, 0=none).")
        }
        return p
    }

    func dueDate(_ key: String) throws -> DueDate? {
        guard let s = try string(key) else { return nil }
        guard let d = DateParsing.parse(s, timeZone: timeZone) else {
            throw ArgumentError("Could not parse '\(key)' value '\(s)'. Use ISO 8601, e.g. 2026-05-01T09:00:00 or 2026-05-01.")
        }
        return d
    }

    func dueUpdate(_ key: String) throws -> DueUpdate? {
        guard let s = try string(key) else { return nil }
        if s.trimmingCharacters(in: .whitespaces).lowercased() == "none" { return .clear }
        return .set(try dueDate(key)!)
    }
}
