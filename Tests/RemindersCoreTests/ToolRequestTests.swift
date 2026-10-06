import MCP
import XCTest
@testable import RemindersCore

final class ToolRequestTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func parse(_ name: String, _ args: [String: Value]? = nil) throws -> ToolRequest {
        try ToolRequest.parse(name: name, arguments: args, timeZone: utc)
    }

    private func assertFails(
        _ name: String, _ args: [String: Value]?, contains fragment: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(name, args), file: file, line: line) { error in
            guard let e = error as? ArgumentError else {
                return XCTFail("wrong error type: \(error)", file: file, line: line)
            }
            XCTAssertTrue(e.message.contains(fragment), "'\(e.message)' lacks '\(fragment)'", file: file, line: line)
        }
    }

    // MARK: JSON-RPC level

    func testDecodesToolsCallParametersFromJSONRPCBody() throws {
        let body = """
        {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{
          "name":"reminders_create_reminder",
          "arguments":{"title":"Buy milk","list":"Groceries","priority":1,"due_date":"2026-05-01"}}}
        """
        struct Envelope: Decodable { let method: String; let params: CallTool.Parameters }
        let env = try JSONDecoder().decode(Envelope.self, from: Data(body.utf8))
        XCTAssertEqual(env.method, CallTool.name)

        let req = try ToolRequest.parse(name: env.params.name, arguments: env.params.arguments, timeZone: utc)
        guard case let .createReminder(title, list, notes, due, priority) = req else {
            return XCTFail("expected createReminder, got \(req)")
        }
        XCTAssertEqual(title, "Buy milk")
        XCTAssertEqual(list, "Groceries")
        XCTAssertNil(notes)
        XCTAssertEqual(due?.hasTime, false)
        XCTAssertEqual(priority, 1)
    }

    // MARK: Routing

    func testUnknownToolIsRejected() {
        assertFails("pr_list_groups", nil, contains: "Unknown tool")
        assertFails("", nil, contains: "Unknown tool")
    }

    func testListListsNeedsNoArguments() throws {
        XCTAssertEqual(try parse("reminders_list_lists"), .listLists)
        XCTAssertEqual(try parse("reminders_list_lists", [:]), .listLists)
    }

    // MARK: list / search

    func testListRemindersRequiresList() {
        assertFails("reminders_list_reminders", [:], contains: "'list' is required")
        assertFails("reminders_list_reminders", ["list": .string("  ")], contains: "'list' is required")
    }

    func testIncludeCompletedAcceptsBoolAndString() throws {
        XCTAssertEqual(
            try parse("reminders_list_reminders", ["list": "Groceries", "include_completed": true]),
            .listReminders(list: "Groceries", includeCompleted: true))
        XCTAssertEqual(
            try parse("reminders_list_reminders", ["list": "Groceries", "include_completed": "true"]),
            .listReminders(list: "Groceries", includeCompleted: true))
        XCTAssertEqual(
            try parse("reminders_list_reminders", ["list": "Groceries"]),
            .listReminders(list: "Groceries", includeCompleted: false))
        assertFails("reminders_list_reminders", ["list": "x", "include_completed": "maybe"], contains: "true or false")
    }

    func testSearchRequiresQuery() throws {
        assertFails("reminders_search_reminders", [:], contains: "'query' is required")
        XCTAssertEqual(
            try parse("reminders_search_reminders", ["query": "milk", "list": "Groceries"]),
            .searchReminders(query: "milk", list: "Groceries"))
    }

    // MARK: create

    func testCreateRequiresTitleAndList() {
        assertFails("reminders_create_reminder", ["list": "Groceries"], contains: "'title' is required")
        assertFails("reminders_create_reminder", ["title": "x"], contains: "'list' is required")
    }

    func testCreateRejectsBadDueDateInsteadOfDroppingIt() {
        assertFails("reminders_create_reminder",
                    ["title": "x", "list": "y", "due_date": "next tuesday"], contains: "Could not parse")
    }

    func testPriorityValidation() throws {
        for ok: Value in [.int(0), .int(1), .int(9), .string("5")] {
            XCTAssertNoThrow(try parse("reminders_create_reminder", ["title": "x", "list": "y", "priority": ok]))
        }
        for bad: Value in [.int(10), .int(-1), .string("high"), .double(2.5), .bool(true)] {
            assertFails("reminders_create_reminder",
                        ["title": "x", "list": "y", "priority": bad], contains: "0 to 9")
        }
    }

    // MARK: complete / move

    func testCompleteRequiresId() throws {
        assertFails("reminders_complete_reminder", nil, contains: "'id' is required")
        XCTAssertEqual(try parse("reminders_complete_reminder", ["id": "abc"]), .completeReminder(id: "abc"))
    }

    func testMoveNormalisesEmptyAppendNotes() throws {
        XCTAssertEqual(
            try parse("reminders_move_reminder", ["id": "a", "target_list": "B", "append_notes": ""]),
            .moveReminder(id: "a", targetList: "B", appendNotes: nil))
        XCTAssertEqual(
            try parse("reminders_move_reminder", ["id": "a", "target_list": "B", "append_notes": "moved"]),
            .moveReminder(id: "a", targetList: "B", appendNotes: "moved"))
        assertFails("reminders_move_reminder", ["id": "a"], contains: "'target_list' is required")
    }

    // MARK: update

    func testUpdateNeedsAtLeastOneField() {
        assertFails("reminders_update_reminder", ["id": "a"], contains: "Nothing to update")
    }

    func testUpdateRejectsBlankTitle() {
        assertFails("reminders_update_reminder", ["id": "a", "title": "  "], contains: "must not be empty")
    }

    func testUpdateDueDateNoneClears() throws {
        for none in ["none", "NONE", " None "] {
            XCTAssertEqual(
                try parse("reminders_update_reminder", ["id": "a", "due_date": .string(none)]),
                .updateReminder(id: "a", title: nil, notes: nil, due: .clear, priority: nil))
        }
    }

    func testUpdateAllowsEmptyNotesToClearThem() throws {
        XCTAssertEqual(
            try parse("reminders_update_reminder", ["id": "a", "notes": ""]),
            .updateReminder(id: "a", title: nil, notes: "", due: nil, priority: nil))
    }

    func testUpdateRejectsBadDue() {
        assertFails("reminders_update_reminder", ["id": "a", "due_date": "soon"], contains: "Could not parse")
    }

    // MARK: delete

    func testDeleteRequiresExplicitConfirmation() throws {
        assertFails("reminders_delete_reminder", ["id": "a"], contains: "confirm=true")
        assertFails("reminders_delete_reminder", ["id": "a", "confirm": false], contains: "confirm=true")
        assertFails("reminders_delete_reminder", ["id": "a", "confirm": "yes"], contains: "true or false")
        XCTAssertEqual(try parse("reminders_delete_reminder", ["id": "a", "confirm": true]), .deleteReminder(id: "a"))
        XCTAssertEqual(try parse("reminders_delete_reminder", ["id": "a", "confirm": "true"]), .deleteReminder(id: "a"))
    }
}
