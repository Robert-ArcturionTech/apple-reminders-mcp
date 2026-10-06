import EventKit
import Foundation
import MCP
import RemindersCore

// apple-reminders-mcp: a native MCP server for Apple Reminders, built on EventKit.
// Argument parsing/validation lives in RemindersCore; this file only talks to EventKit.

// MARK: - EventKit store

@MainActor
final class ReminderStore {
    static let shared = ReminderStore()
    let store = EKEventStore()
    var granted = false

    func requestAccess() async {
        do {
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToReminders()
            } else {
                granted = try await store.requestAccess(to: .reminder)
            }
        } catch {
            granted = false
        }
    }

    func allCalendars() -> [EKCalendar] { store.calendars(for: .reminder) }

    /// Resolves a list by identifier first, then by exact title.
    func resolve(_ nameOrID: String) -> EKCalendar? {
        let cals = allCalendars()
        return cals.first { $0.calendarIdentifier == nameOrID }
            ?? cals.first { $0.title == nameOrID }
    }

    func fetchIncomplete(in calendars: [EKCalendar]?) async -> [EKReminder] {
        await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars)
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
    }

    func fetchAll(in calendars: [EKCalendar]?) async -> [EKReminder] {
        await withCheckedContinuation { cont in
            let pred = store.predicateForReminders(in: calendars)
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
    }

    func reminder(withID id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    func save(_ reminder: EKReminder) throws { try store.save(reminder, commit: true) }
    func remove(_ reminder: EKReminder) throws { try store.remove(reminder, commit: true) }
}

// MARK: - Helpers

func reminderDict(_ r: EKReminder) -> [String: Any] {
    var d: [String: Any] = [
        "id": r.calendarItemIdentifier,
        "title": r.title ?? "",
        "list": r.calendar?.title ?? "unknown",
        "done": r.isCompleted,
        "priority": r.priority,
    ]
    if let n = r.notes, !n.isEmpty { d["notes"] = n }
    if let dc = r.dueDateComponents, let date = Calendar.current.date(from: dc) {
        d["due"] = DateParsing.iso8601String(date)
    }
    return d
}

func clearAlarms(_ rem: EKReminder) {
    for a in rem.alarms ?? [] { rem.removeAlarm(a) }
}

func setDue(_ rem: EKReminder, _ due: DueDate) {
    let units: Set<Calendar.Component> = due.hasTime
        ? [.year, .month, .day, .hour, .minute]
        : [.year, .month, .day]
    rem.dueDateComponents = Calendar.current.dateComponents(units, from: due.date)
    clearAlarms(rem)
    if due.hasTime { rem.addAlarm(EKAlarm(absoluteDate: due.date)) }
}

enum Outcome {
    case ok(String)
    case failure(String)
}

// MARK: - Tool execution

@MainActor
func execute(_ request: ToolRequest) async -> Outcome {
    let rs = ReminderStore.shared

    switch request {

    case .listLists:
        let all = await rs.fetchIncomplete(in: nil)
        var counts: [String: Int] = [:]
        for r in all { counts[r.calendar?.calendarIdentifier ?? "", default: 0] += 1 }
        let lists = rs.allCalendars().map {
            (title: $0.title, count: counts[$0.calendarIdentifier] ?? 0)
        }
        return .ok(Formatting.listSummary(lists))

    case .listReminders(let listName, let includeCompleted):
        guard let cal = rs.resolve(listName) else {
            return .failure("List '\(listName)' not found. Run reminders_list_lists to see valid names.")
        }
        let rems = includeCompleted
            ? await rs.fetchAll(in: [cal])
            : await rs.fetchIncomplete(in: [cal])
        if rems.isEmpty {
            return .ok("No \(includeCompleted ? "" : "incomplete ")reminders in '\(listName)'.")
        }
        return .ok(Formatting.json(rems.map(reminderDict)))

    case .createReminder(let title, let listName, let notes, let due, let priority):
        guard let cal = rs.resolve(listName) else {
            return .failure("List '\(listName)' not found. Run reminders_list_lists.")
        }
        let rem = EKReminder(eventStore: rs.store)
        rem.calendar = cal
        rem.title = title
        if let notes { rem.notes = notes }
        if let due { setDue(rem, due) }
        if let priority { rem.priority = priority }
        do {
            try rs.save(rem)
            return .ok("Created '\(title)' in \(cal.title)  · id: \(rem.calendarItemIdentifier)")
        } catch { return .failure(error.localizedDescription) }

    case .completeReminder(let id):
        guard let rem = rs.reminder(withID: id) else {
            return .failure("Reminder '\(id)' not found.")
        }
        guard !rem.isCompleted else { return .failure("Reminder '\(id)' is already completed.") }
        rem.isCompleted = true
        do {
            try rs.save(rem)
            return .ok("Completed: '\(rem.title ?? id)'")
        } catch { return .failure(error.localizedDescription) }

    // A true move: the same EKReminder is reassigned in one save, so it keeps its id,
    // creation date, due date, alarms, notes and priority. No copy, no completed ghost.
    case .moveReminder(let id, let targetName, let appendNotes):
        guard let target = rs.resolve(targetName) else {
            return .failure("Target list '\(targetName)' not found. Run reminders_list_lists.")
        }
        guard let rem = rs.reminder(withID: id) else {
            return .failure("Reminder '\(id)' not found.")
        }
        guard !rem.isCompleted else {
            return .failure("Refusing to move completed reminder '\(id)'.")
        }
        let from = rem.calendar
        let fromTitle = from?.title ?? "unknown"
        if from?.calendarIdentifier == target.calendarIdentifier {
            return .failure("Reminder is already in '\(target.title)'.")
        }
        // EventKit cannot reassign across accounts; fail early with a clear message.
        guard target.source == from?.source else {
            return .failure("Cannot move across accounts (\(fromTitle) -> \(target.title)).")
        }
        rem.calendar = target
        if let extra = appendNotes {
            let existing = rem.notes ?? ""
            rem.notes = existing.isEmpty ? extra : existing + "\n" + extra
        }
        do {
            try rs.save(rem)
            return .ok("Moved '\(rem.title ?? id)'  \(fromTitle) -> \(target.title)  · id unchanged: \(rem.calendarItemIdentifier)")
        } catch { return .failure(error.localizedDescription) }

    case .updateReminder(let id, let title, let notes, let due, let priority):
        guard let rem = rs.reminder(withID: id) else {
            return .failure("Reminder '\(id)' not found.")
        }
        var changed: [String] = []
        if let title { rem.title = title; changed.append("title") }
        if let notes { rem.notes = notes; changed.append("notes") }
        switch due {
        case .clear?:
            rem.dueDateComponents = nil
            clearAlarms(rem)
            changed.append("due cleared")
        case .set(let d)?:
            setDue(rem, d)
            changed.append("due")
        case nil:
            break
        }
        if let priority { rem.priority = priority; changed.append("priority") }
        do {
            try rs.save(rem)
            return .ok("Updated '\(rem.title ?? id)' (\(changed.joined(separator: ", "))) in \(rem.calendar?.title ?? "?")")
        } catch { return .failure(error.localizedDescription) }

    case .deleteReminder(let id):
        guard let rem = rs.reminder(withID: id) else {
            return .failure("Reminder '\(id)' not found.")
        }
        let label = rem.title ?? id
        let listTitle = rem.calendar?.title ?? "unknown"
        do {
            try rs.remove(rem)
            return .ok("Deleted '\(label)' from \(listTitle) (permanent)")
        } catch { return .failure(error.localizedDescription) }

    case .searchReminders(let query, let listName):
        var cals: [EKCalendar]? = nil
        if let listName {
            guard let cal = rs.resolve(listName) else {
                return .failure("List '\(listName)' not found. Run reminders_list_lists.")
            }
            cals = [cal]
        }
        let hits = await rs.fetchIncomplete(in: cals).filter {
            Formatting.matches(query: query, title: $0.title, notes: $0.notes)
        }
        return hits.isEmpty ? .ok("No matches for '\(query)'.") : .ok(Formatting.json(hits.map(reminderDict)))
    }
}

// MARK: - Bootstrap

let store = ReminderStore.shared
await store.requestAccess()

guard store.granted else {
    fputs("""
        ERROR: Reminders access denied.
        Grant access in System Settings > Privacy & Security > Reminders
        (for the app that launches this server, e.g. Terminal, Claude Desktop), then retry.

        """, stderr)
    exit(1)
}

let server = Server(
    name: "apple-reminders-mcp",
    version: "1.0.0",
    capabilities: .init(tools: .init())
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: ToolCatalog.tools)
}

await server.withMethodHandler(CallTool.self) { params in
    do {
        let request = try ToolRequest.parse(name: params.name, arguments: params.arguments)
        switch await execute(request) {
        case .ok(let text):
            return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        case .failure(let message):
            return CallTool.Result(content: [.text(text: "ERROR: \(message)", annotations: nil, _meta: nil)], isError: true)
        }
    } catch {
        return CallTool.Result(content: [.text(text: "ERROR: \(error)", annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
