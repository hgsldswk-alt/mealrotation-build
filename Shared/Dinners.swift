import Foundation

enum DinnerError: Error {
    case storage, invalidName, duplicateName, invalidCode, invalidBackup
    case staleDay, staleChoice, alreadyLogged, changedRecord
}

struct LocalDay: Codable, Hashable, Comparable {
    let key: Int

    static func calendar(in zone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    init(_ date: Date, zone: TimeZone = .current) {
        let parts = Self.calendar(in: zone).dateComponents([.year, .month, .day], from: date)
        key = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    var date: Date {
        Self.calendar(in: .gmt).date(from: DateComponents(year: key / 10_000,
            month: key / 100 % 100, day: key % 100, hour: 12)) ?? .distantPast
    }
    var valid: Bool { (19000101...99991231).contains(key) && LocalDay(date, zone: .gmt) == self }
    func adding(_ days: Int) -> Self {
        let date = Self.calendar(in: .gmt).date(byAdding: .day, value: days, to: date) ?? date
        return Self(date, zone: .gmt)
    }
    func distance(to other: Self) -> Int {
        Self.calendar(in: .gmt).dateComponents([.day], from: date, to: other.date).day ?? 0
    }
    func formatted(_ style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar(in: .gmt)
        formatter.timeZone = .gmt
        formatter.dateStyle = style
        return formatter.string(from: date)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }
}

struct Dinner: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quick = false
    var archived = false
}

enum DinnerKind: String, Codable {
    case home, leftovers, out

    var key: String {
        switch self {
        case .home: "home"
        case .leftovers: "leftovers"
        case .out: "ate_out"
        }
    }
}

struct DinnerLog: Codable, Identifiable, Equatable {
    var id = UUID()
    let day: LocalDay
    let kind: DinnerKind
    let dinnerID: UUID?
    let name: String
    let createdAt: Date
    let timeZone: String
    var title: String { kind == .home ? name : L.t(kind.key) }
}

struct TodayBatch: Codable, Equatable {
    let day: LocalDay
    let quick: Bool
    let avoid: Int
    let ids: [UUID]
    var turn: Int? = nil
}

struct DinnerChoice: Identifiable, Equatable {
    let dinner: Dinner
    let last: LocalDay?
    var id: UUID { dinner.id }
    func detail(on day: LocalDay) -> String {
        guard let last else { return L.t("never_logged") }
        let days = last.distance(to: day)
        if days == 0 { return L.t("day_today") }
        return days == 1 ? L.t("last_yesterday") : L.f("last_days", days)
    }
}

struct WeeklyReview: Codable, Equatable {
    let start: LocalDay
    let dinners: [String]
    let frequent: [String]
    let overdue: [String]
}

struct DinnerState: Codable, Equatable {
    var dinners: [Dinner] = []
    var logs: [DinnerLog] = []
    var batch: TodayBatch?
    var quickOnly = false
    var avoidDays = 2
    var entitlement = Entitlement()
    var reviews: [WeeklyReview] = []
    var coreDays: [LocalDay] = []
    var ratedVersion: String?

    func log(on day: LocalDay) -> DinnerLog? { logs.first { $0.day == day } }
    var homeDays: Int { logs.filter { $0.kind == .home }.count }

    func choices(on day: LocalDay, now: Date) -> [DinnerChoice] {
        guard log(on: day) == nil else { return [] }
        let premium = entitlement.hasPro(at: now)
        let quick = premium && quickOnly
        let avoid = premium ? avoidDays : 2
        let ranked = Rotation.ranked(dinners, logs: logs, through: day, quick: quick, includeToday: false)
        if let batch, batch.day == day, batch.quick == quick, batch.avoid == avoid {
            let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
            let selection = batch.ids.compactMap { byID[$0] }
            if selection.count == min(3, ranked.count) { return selection }
        }
        return Rotation.batch(ranked, on: day, avoid: avoid)
    }

    mutating func shuffle(on day: LocalDay, now: Date) {
        let pro = entitlement.hasPro(at: now)
        let quick = pro && quickOnly
        let avoid = pro ? avoidDays : 2
        let previous = Set(choices(on: day, now: now).map(\.id))
        let ranked = Rotation.ranked(dinners, logs: logs, through: day, quick: quick, includeToday: false)
        let turn = (batch?.day == day ? batch?.turn ?? 0 : 0) + 1
        let next = Rotation.batch(ranked, on: day, avoid: avoid, excluding: previous, turn: turn)
        batch = TodayBatch(day: day, quick: quick, avoid: avoid, ids: next.map(\.id), turn: turn)
    }

    mutating func record(on day: LocalDay, dinnerID: UUID?, kind: DinnerKind,
                         replacing expected: UUID?, now: Date, zone: TimeZone,
                         countForReview: Bool) throws -> DinnerLog {
        let existing = log(on: day)
        if let expected {
            guard existing?.id == expected else { throw DinnerError.changedRecord }
        } else if existing != nil {
            throw DinnerError.alreadyLogged
        }
        let name: String
        if kind == .home {
            guard let dinner = dinners.first(where: { $0.id == dinnerID && !$0.archived }) else {
                throw DinnerError.staleChoice
            }
            name = dinner.name
        } else {
            name = ""
        }
        let entry = DinnerLog(day: day, kind: kind, dinnerID: kind == .home ? dinnerID : nil,
                              name: name, createdAt: now, timeZone: zone.identifier)
        logs.removeAll { $0.day == day }
        logs.append(entry)
        if day != LocalDay(now, zone: zone) { batch = nil }
        if countForReview, !coreDays.contains(day) { coreDays.append(day) }
        return entry
    }

    mutating func undo(_ entry: DinnerLog) throws {
        guard log(on: entry.day)?.id == entry.id else { throw DinnerError.changedRecord }
        logs.removeAll { $0.id == entry.id }
        coreDays.removeAll { $0 == entry.day }
    }

    mutating func createReview(start: LocalDay, now: Date) -> WeeklyReview? {
        guard entitlement.hasPro(at: now) else { return reviews.first(where: { $0.start == start }) }
        let end = min(start.adding(6), LocalDay(now))
        let weekly = logs.filter { $0.kind == .home && $0.day >= start && $0.day <= end }.sorted { $0.day < $1.day }
        let counts = Dictionary(grouping: weekly, by: \.name).mapValues(\.count)
        let frequent = counts.keys.sorted {
            let lhs = counts[$0, default: 0], rhs = counts[$1, default: 0]
            return lhs == rhs ? Rotation.nameKey($0) < Rotation.nameKey($1) : lhs > rhs
        }
        let overdue = Rotation.ranked(dinners, logs: logs, through: end).prefix(3).map(\.dinner.name)
        let review = WeeklyReview(start: start, dinners: weekly.map(\.name), frequent: Array(frequent.prefix(3)), overdue: overdue)
        reviews.removeAll { $0.start == start }
        reviews.append(review)
        return review
    }
}

enum Rotation {
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validName(_ name: String) -> Bool {
        (1...80).contains(name.count) && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func lines(_ text: String, existing: [Dinner] = []) -> [String] {
        var seen = Set(existing.map { nameKey($0.name) })
        return text.components(separatedBy: .newlines).map(cleaned)
            .filter { validName($0) && seen.insert(nameKey($0)).inserted }
    }

    static func ranked(_ dinners: [Dinner], logs: [DinnerLog], through day: LocalDay,
                       quick: Bool = false, includeToday: Bool = true) -> [DinnerChoice] {
        var last: [UUID: LocalDay] = [:]
        var loggedToday = Set<UUID>()
        for log in logs where log.kind == .home && log.day <= day {
            guard let id = log.dinnerID else { continue }
            if log.day == day { loggedToday.insert(id) }
            last[id] = max(last[id] ?? log.day, log.day)
        }
        return dinners.filter { !$0.archived && (!quick || $0.quick) && (includeToday || !loggedToday.contains($0.id)) }
            .map { DinnerChoice(dinner: $0, last: last[$0.id]) }
            .sorted {
                if $0.last != $1.last {
                    guard let left = $0.last else { return true }
                    guard let right = $1.last else { return false }
                    return left < right
                }
                let left = nameKey($0.dinner.name), right = nameKey($1.dinner.name)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
    }

    static func batch(_ ranked: [DinnerChoice], on day: LocalDay, avoid: Int,
                      excluding previous: Set<UUID> = [], turn: Int = 0) -> [DinnerChoice] {
        func older(_ choice: DinnerChoice) -> Bool {
            choice.last.map { $0.distance(to: day) > avoid } ?? true
        }
        let new = ranked.filter { !previous.contains($0.id) }
        let old = ranked.filter { previous.contains($0.id) }
        let fresh = new.filter(older)
        let offset = fresh.count > 3 ? max(0, turn - 1) % fresh.count : 0
        let rotated = Array(fresh.dropFirst(offset)) + Array(fresh.prefix(offset))
        return Array((rotated + new.filter { !older($0) } + old).prefix(3))
    }
}
