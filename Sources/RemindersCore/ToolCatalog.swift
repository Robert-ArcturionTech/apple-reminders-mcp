import Foundation
import MCP

/// Names of the tools this server exposes.
public enum ToolName: String, CaseIterable {
    case listLists = "reminders_list_lists"
    case listReminders = "reminders_list_reminders"
    case createReminder = "reminders_create_reminder"
    case completeReminder = "reminders_complete_reminder"
    case moveReminder = "reminders_move_reminder"
    case updateReminder = "reminders_update_reminder"
    case deleteReminder = "reminders_delete_reminder"
    case searchReminders = "reminders_search_reminders"
}

public enum ToolCatalog {
    private static func prop(_ type: String, _ desc: String) -> Value {
        .object(["type": .string(type), "description": .string(desc)])
    }

    private static func schema(
        _ properties: [String: Value], required: [String] = []
    ) -> Value {
        var obj: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty { obj["required"] = .array(required.map { .string($0) }) }
        return .object(obj)
    }

    public static let tools: [Tool] = [
        Tool(
            name: ToolName.listLists.rawValue,
            description: "List all Reminders lists with their incomplete-item counts.",
            inputSchema: schema([:])),
        Tool(
            name: ToolName.listReminders.rawValue,
            description: "List the reminders in one list. Pass the exact list name (e.g. 'Groceries') or its identifier. Incomplete items only unless include_completed is true.",
            inputSchema: schema([
                "list": prop("string", "Exact list name (e.g. 'Groceries') or list identifier"),
                "include_completed": prop("boolean", "Also include completed reminders (default false)"),
            ], required: ["list"])),
        Tool(
            name: ToolName.createReminder.rawValue,
            description: "Create a reminder in an existing list.",
            inputSchema: schema([
                "title": prop("string", "Reminder title"),
                "list": prop("string", "Target list name, e.g. 'Groceries'"),
                "notes": prop("string", "Optional notes/body"),
                "due_date": prop("string", "Optional due date: ISO 8601 timestamp (2026-05-01T09:00:00) or bare date (2026-05-01, all-day)"),
                "priority": prop("integer", "Optional: 1=high, 5=medium, 9=low, 0=none"),
            ], required: ["title", "list"])),
        Tool(
            name: ToolName.completeReminder.rawValue,
            description: "Mark a reminder as completed by its id (from reminders_list_reminders).",
            inputSchema: schema(["id": prop("string", "Reminder identifier")], required: ["id"])),
        Tool(
            name: ToolName.moveReminder.rawValue,
            description: "Move a reminder to a different list in one save. The id, due date, alarms, notes and creation date are preserved; no copy is made. Both lists must belong to the same account.",
            inputSchema: schema([
                "id": prop("string", "Reminder identifier to move"),
                "target_list": prop("string", "Destination list name or identifier"),
                "append_notes": prop("string", "Optional text appended to the existing notes"),
            ], required: ["id", "target_list"])),
        Tool(
            name: ToolName.updateReminder.rawValue,
            description: "Edit a reminder in place by id. Only the fields you pass are changed. Pass due_date='none' to clear the due date and its alarms.",
            inputSchema: schema([
                "id": prop("string", "Reminder identifier"),
                "title": prop("string", "Optional new title"),
                "notes": prop("string", "Optional new notes (replaces existing notes)"),
                "due_date": prop("string", "Optional ISO 8601 due date, or 'none' to clear the due date and alarms"),
                "priority": prop("integer", "Optional: 1=high, 5=medium, 9=low, 0=none"),
            ], required: ["id"])),
        Tool(
            name: ToolName.deleteReminder.rawValue,
            description: "PERMANENTLY delete a reminder by id. Irreversible: Reminders has no trash. Requires confirm=true. Prefer reminders_complete_reminder unless deletion was explicitly requested.",
            inputSchema: schema([
                "id": prop("string", "Reminder identifier"),
                "confirm": prop("boolean", "Must be true to proceed"),
            ], required: ["id", "confirm"])),
        Tool(
            name: ToolName.searchReminders.rawValue,
            description: "Case-insensitive text search over the titles and notes of incomplete reminders, across all lists or within one list.",
            inputSchema: schema([
                "query": prop("string", "Search term"),
                "list": prop("string", "Optional: limit to one list name or identifier"),
            ], required: ["query"])),
    ]
}
