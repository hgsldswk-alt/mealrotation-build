import Foundation


struct MenuPreview {
    let added: [MenuItem]
    let duplicates: [MenuItem]
}

enum MenuCode {
    static let limit = 24 * 1024
    static let countLimit = 30

    static func encode(_ items: [MenuItem]) throws -> String {
        guard (1...countLimit).contains(items.count),
              items.allSatisfy({ Rotation.validName($0.name) }) else { throw DinnerError.invalidCode }
        let data = try JSONEncoder().encode(items)
        let url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let code = "MR1:" + url
        guard code.utf8.count <= limit else { throw DinnerError.invalidCode }
        return code
    }

    static func decode(_ input: String) throws -> [MenuItem] {
        guard input.utf8.count <= limit else { throw DinnerError.invalidCode }
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("MR1:") else { throw DinnerError.invalidCode }
        let raw = code.dropFirst(4)
        guard raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw DinnerError.invalidCode }
        let base64 = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              (1...countLimit).contains(objects.count),
              objects.allSatisfy({ Set($0.keys).isSubset(of: ["name", "quick"]) && !($0["quick"] is NSNull) }),
              let decoded = try? JSONDecoder().decode([MenuItem].self, from: data) else {
            throw DinnerError.invalidCode
        }
        let items = decoded.map { MenuItem(name: Rotation.cleaned($0.name), quick: $0.quick == true) }
        guard items.allSatisfy({ Rotation.validName($0.name) }) else { throw DinnerError.invalidCode }
        return items
    }

    static func preview(_ items: [MenuItem], existing: [Dinner]) -> MenuPreview {
        var seen = Set(existing.map { Rotation.nameKey($0.name) })
        var duplicates = Set<String>()
        var added: [MenuItem] = [], repeated: [MenuItem] = []
        for item in items {
            if seen.insert(item.id).inserted {
                added.append(item)
            } else if duplicates.insert(item.id).inserted {
                repeated.append(item)
            }
        }
        return MenuPreview(added: added, duplicates: repeated)
    }

    static func merge(_ items: [MenuItem], into state: inout DinnerState) {
        let additions = preview(items, existing: state.dinners).added
        state.dinners += additions.map { Dinner(name: $0.name, quick: $0.quick == true) }
        if !additions.isEmpty { state.batch = nil }
    }
}

struct MenuBackup: Codable {
    struct Preferences: Codable {
        let avoidDays: Int
        let quickOnly: Bool
    }

    struct Changes {
        let dinners: [Dinner]
        let logs: Int
        let reviews: Int
        let preferences: Preferences?
        var isEmpty: Bool { dinners.isEmpty && logs == 0 && reviews == 0 && preferences == nil }
    }

    static let maxSize = 16 * 1024 * 1024
    let version: Int
    let exportedAt: Date
    let dinners: [Dinner]
    let logs: [DinnerLog]
    let reviews: [WeeklyReview]?
    let preferences: Preferences?

    init(state: DinnerState, now: Date = .now) {
        version = 1
        exportedAt = now
        dinners = state.dinners
        logs = state.logs
        reviews = state.reviews
        preferences = Preferences(avoidDays: state.avoidDays, quickOnly: state.quickOnly)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func read(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard data.count <= maxSize, let backup = try? decoder.decode(Self.self, from: data),
              backup.version == 1, backup.dinners.allSatisfy({ Rotation.validName($0.name) }),
              Set(backup.dinners.map(\.id)).count == backup.dinners.count,
              Set(backup.dinners.map { Rotation.nameKey($0.name) }).count == backup.dinners.count,
              Set(backup.logs.map(\.day)).count == backup.logs.count,
              Set(backup.logs.map(\.id)).count == backup.logs.count else { throw DinnerError.invalidBackup }
        if let preferences = backup.preferences, !(0...14).contains(preferences.avoidDays) {
            throw DinnerError.invalidBackup
        }
        let weeks = backup.reviews ?? []
        guard Set(weeks.map(\.start)).count == weeks.count, weeks.allSatisfy({ review in
            review.start.valid && review.dinners.count <= 7 && review.frequent.count <= 3 && review.overdue.count <= 3 &&
            (review.dinners + review.frequent + review.overdue).allSatisfy(Rotation.validName)
        }) else { throw DinnerError.invalidBackup }
        let ids = Set(backup.dinners.map(\.id))
        guard backup.logs.allSatisfy({ log in
            guard log.day.valid, TimeZone(identifier: log.timeZone) != nil else { return false }
            if log.kind != .home { return log.dinnerID == nil && log.name.isEmpty }
            return log.dinnerID.map(ids.contains) == true && Rotation.validName(log.name)
        }) else { throw DinnerError.invalidBackup }
        return backup
    }

    func preview(in state: DinnerState) -> Changes {
        let names = Set(state.dinners.map { Rotation.nameKey($0.name) })
        let days = Set(state.logs.map(\.day))
        let weeks = Set(state.reviews.map(\.start))
        let restoredPreferences = state.dinners.isEmpty && state.logs.isEmpty && state.avoidDays == 2 && !state.quickOnly
            ? preferences.flatMap { $0.avoidDays == 2 && !$0.quickOnly ? nil : $0 } : nil
        return Changes(dinners: dinners.filter { !names.contains(Rotation.nameKey($0.name)) },
                       logs: logs.filter { !days.contains($0.day) }.count,
                       reviews: (reviews ?? []).filter { !weeks.contains($0.start) }.count,
                       preferences: restoredPreferences)
    }

    func merge(into state: inout DinnerState) -> (dinners: Int, logs: Int) {
        let settings = preview(in: state).preferences
        var names = Dictionary(uniqueKeysWithValues: state.dinners.map { (Rotation.nameKey($0.name), $0.id) })
        var dinnerIDs = Set(state.dinners.map(\.id))
        var mapping: [UUID: UUID] = [:]
        var added = 0
        for var dinner in dinners {
            let original = dinner.id
            let name = Rotation.nameKey(dinner.name)
            if let match = names[name] {
                mapping[original] = match
                continue
            }
            if dinnerIDs.contains(original) { dinner.id = UUID() }
            dinnerIDs.insert(dinner.id)
            mapping[original] = dinner.id
            names[name] = dinner.id
            state.dinners.append(dinner)
            added += 1
        }
        var days = Set(state.logs.map(\.day))
        var logIDs = Set(state.logs.map(\.id))
        var imported = 0
        for entry in logs where days.insert(entry.day).inserted {
            let id = logIDs.insert(entry.id).inserted ? entry.id : UUID()
            let log = DinnerLog(id: id, day: entry.day, kind: entry.kind,
                                dinnerID: entry.dinnerID.flatMap { mapping[$0] },
                                name: entry.name, createdAt: entry.createdAt, timeZone: entry.timeZone)
            state.logs.append(log)
            imported += 1
        }
        let seenWeeks = Set(state.reviews.map(\.start))
        state.reviews += (reviews ?? []).filter { !seenWeeks.contains($0.start) }
        if let settings {
            state.quickOnly = settings.quickOnly
            state.avoidDays = settings.avoidDays
        }
        if added > 0 || imported > 0 || settings != nil { state.batch = nil }
        return (added, imported)
    }

    static func csv(_ logs: [DinnerLog]) -> Data {
        func field(_ value: String) -> String {
            let significant = value.drop(while: \.isWhitespace)
            let risky = value.first.map { $0 == "\t" || $0 == "\r" || $0 == "\n" } == true ||
                significant.first.map { "=+-@".contains($0) } == true
            let safe = (risky ? "'" : "") + value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = logs.sorted { $0.day > $1.day }.map { log in
            let key = log.day.key
            let day = String(format: "%04d-%02d-%02d", key / 10_000, key / 100 % 100, key % 100)
            return [day, log.title, L.t(log.kind.key), log.timeZone].map(field).joined(separator: ",")
        }
        let header = ["csv_day", "csv_dinner", "csv_type", "csv_zone"].map { field(L.t($0)) }.joined(separator: ",")
        return Data(([header] + rows).joined(separator: "\r\n").utf8)
    }
}
