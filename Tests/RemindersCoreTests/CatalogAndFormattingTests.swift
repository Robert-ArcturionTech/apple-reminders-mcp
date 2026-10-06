import MCP
import XCTest
@testable import RemindersCore

final class CatalogAndFormattingTests: XCTestCase {
    func testEveryToolNameHasExactlyOneDefinition() {
        let defined = ToolCatalog.tools.map(\.name)
        XCTAssertEqual(Set(defined).count, defined.count, "duplicate tool names")
        XCTAssertEqual(Set(defined), Set(ToolName.allCases.map(\.rawValue)))
    }

    func testToolNamesUseGenericPrefix() {
        for t in ToolCatalog.tools { XCTAssertTrue(t.name.hasPrefix("reminders_"), t.name) }
    }

    func testRequiredFieldsAreDeclaredProperties() {
        for tool in ToolCatalog.tools {
            let schema = tool.inputSchema.objectValue
            XCTAssertEqual(schema?["type"]?.stringValue, "object", tool.name)
            let props = schema?["properties"]?.objectValue ?? [:]
            for r in schema?["required"]?.arrayValue ?? [] {
                XCTAssertNotNil(props[r.stringValue ?? ""], "\(tool.name): required '\(r)' is not a property")
            }
        }
    }

    func testSearchMatchingIsCaseInsensitiveOverTitleAndNotes() {
        XCTAssertTrue(Formatting.matches(query: "MILK", title: "Buy milk", notes: nil))
        XCTAssertTrue(Formatting.matches(query: "oat", title: "Groceries", notes: "Oat Milk, 2L"))
        XCTAssertFalse(Formatting.matches(query: "eggs", title: "Buy milk", notes: "2L"))
        XCTAssertFalse(Formatting.matches(query: "  ", title: "anything", notes: nil))
        XCTAssertFalse(Formatting.matches(query: "x", title: nil, notes: nil))
    }

    func testJSONIsSortedAndSafe() {
        let out = Formatting.json([["b": 1, "a": "x"]])
        XCTAssertTrue(out.range(of: "\"a\"")!.lowerBound < out.range(of: "\"b\"")!.lowerBound)
        XCTAssertEqual(Formatting.json(["bad": Double.nan]), "[]")
    }

    func testListSummaryPluralisation() {
        let s = Formatting.listSummary([(title: "Groceries", count: 1), (title: "Work", count: 3)])
        XCTAssertTrue(s.contains("Groceries  [1 item]"))
        XCTAssertTrue(s.contains("Work  [3 items]"))
    }
}
