# apple-reminders-mcp

A native [Model Context Protocol](https://modelcontextprotocol.io) server for **Apple Reminders**, written in Swift on top of EventKit. It lets an MCP client (Claude Code, Claude Desktop, or any other) list, search, create, update, complete, move and delete reminders over stdio. There is no AppleScript and no shelling out, so it is fast and keeps ids, alarms and notes intact.

> Built by Robert Lingoes with AI coding agents (Claude Code / Codex); Robert owns the architecture, requirements and review.

## Tools

| Tool | What it does |
|---|---|
| `reminders_list_lists` | List every Reminders list with its incomplete-item count. |
| `reminders_list_reminders` | List reminders in one list (by name or id). `include_completed` is optional. |
| `reminders_search_reminders` | Case-insensitive search over titles and notes of incomplete reminders, across all lists or one list. |
| `reminders_create_reminder` | Create a reminder: `title`, `list`, optional `notes`, `due_date`, `priority`. |
| `reminders_update_reminder` | Edit in place by id. Only the fields you pass change. `due_date: "none"` clears the due date and its alarms. |
| `reminders_complete_reminder` | Mark a reminder completed by id. |
| `reminders_move_reminder` | True move to another list in a single save: same id, due date, alarms, notes and creation date. Optional `append_notes`. Lists must be in the same account. |
| `reminders_delete_reminder` | Permanently delete by id. Requires `confirm: true`. Reminders has no trash, so prefer completing. |

Notes:

- **Lists, not groups.** EventKit does not expose Reminders' sidebar groups, so the server works with lists only. Address a list by its exact title (e.g. `Groceries`) or by its identifier.
- **Dates.** `due_date` accepts ISO 8601 with a zone (`2026-05-01T09:00:00-04:00`, `...Z`), a zone-less local time (`2026-05-01T09:00:00` or `...T09:00`), or a bare date (`2026-05-01`, an all-day reminder with no alarm). Unparseable dates are rejected rather than silently ignored.
- **Priority.** Integer 0 to 9, EventKit's scale: `1` high, `5` medium, `9` low, `0` none.
- **Arguments** may be sent as native JSON booleans/integers or as strings; both work.
- Failures come back as MCP tool errors (`isError: true`) with a readable message.

## Requirements

- macOS 13 or later
- Swift 5.9+ toolchain (Xcode 15+ or matching Command Line Tools)

## Build and install

```bash
git clone https://github.com/ArcturionTechnologies/apple-reminders-mcp.git
cd apple-reminders-mcp
swift build -c release

# optional: put it on your PATH
install -m 755 .build/release/apple-reminders-mcp /usr/local/bin/apple-reminders-mcp
```

Build from the repository root: the linker embeds `Sources/AppleRemindersMCP/Info.plist` (a Reminders usage description) into the binary, via a path relative to the working directory.

Run the unit tests (pure logic only; they never touch EventKit or your data):

```bash
swift test
```

## Privacy permission (macOS Reminders access)

The first time the server starts, macOS asks whether it may access your Reminders. Approve it. If you declined or nothing was prompted:

1. Open **System Settings > Privacy & Security > Reminders**.
2. Enable the app that launches the server (Terminal, iTerm, Claude Desktop, ...). For a bare command-line binary macOS attributes the request to that parent app.
3. Restart the MCP client.

If access is missing, the server prints an explanation to stderr and exits with status 1. It only talks to the local EventKit store; nothing is sent over the network.

## MCP client configuration

### Claude Code

```bash
claude mcp add apple-reminders -- /usr/local/bin/apple-reminders-mcp
```

Or in a project `.mcp.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/usr/local/bin/apple-reminders-mcp"
    }
  }
}
```

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "/usr/local/bin/apple-reminders-mcp"
    }
  }
}
```

Use the absolute path to the binary (for example `/path/to/apple-reminders-mcp/.build/release/apple-reminders-mcp` if you did not install it), then restart Claude Desktop.

### Example calls

```json
{ "name": "reminders_create_reminder",
  "arguments": { "title": "Buy oat milk", "list": "Groceries",
                 "due_date": "2026-05-01T09:00:00", "priority": 5 } }

{ "name": "reminders_move_reminder",
  "arguments": { "id": "<reminder id>", "target_list": "Errands" } }
```

## Layout

```
Sources/RemindersCore/        pure logic: tool catalog, argument validation, date parsing, formatting
Sources/AppleRemindersMCP/    EventKit store + stdio MCP server
Tests/RemindersCoreTests/     XCTest unit tests for RemindersCore
```

Built on the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk).

## License

MIT, see [LICENSE](LICENSE).
