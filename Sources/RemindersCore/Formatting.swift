import Foundation

public enum Formatting {
    /// Case-insensitive substring match over title and notes.
    public static func matches(query: String, title: String?, notes: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        return (title ?? "").lowercased().contains(q) || (notes ?? "").lowercased().contains(q)
    }

    /// Pretty-printed, key-sorted JSON; never traps on unserialisable input.
    public static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else { return "[]" }
        return s
    }

    /// One line per list: "  - Groceries  [3 items]".
    public static func listSummary(_ lists: [(title: String, count: Int)]) -> String {
        var lines = ["Reminders lists:"]
        for l in lists {
            lines.append("  - \(l.title)  [\(l.count) \(l.count == 1 ? "item" : "items")]")
        }
        return lines.joined(separator: "\n")
    }
}
