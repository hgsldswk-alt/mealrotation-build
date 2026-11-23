import Foundation
import SQLite3

struct DinnerStore: Sendable {
    let url: URL

    static func shared() throws -> Self {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Launch.appGroup) else {
            throw DinnerError.storage
        }
        return Self(url: directory.appendingPathComponent("dinners.sqlite"))
    }

    func read(defaultDate: Date = .now) throws -> DinnerState {
        try withConnection { db in
            try transaction(db, begin: "BEGIN") { try load(db, defaultDate: defaultDate) }
        }
    }

    func update<T>(defaultDate: Date = .now, _ edit: (inout DinnerState) throws -> T) throws -> (T, DinnerState) {
        try withConnection { db in
            try transaction(db, begin: "BEGIN IMMEDIATE") {
                var state = try load(db, defaultDate: defaultDate)
                let before = Dictionary(uniqueKeysWithValues: state.logs.map { ($0.day, $0) })
                let result = try edit(&state)
                state.logs.sort { $0.day < $1.day }
                try saveLogs(state.logs, previous: before, db: db)
                var metadata = state
                metadata.logs = []
                let data = try JSONEncoder().encode(metadata)
                try statement("INSERT OR REPLACE INTO rotation (id, state) VALUES (1, ?)", db) { stmt in
                    try bind(data, at: 1, to: stmt)
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw DinnerError.storage }
                }
                return (result, state)
            }
        }
    }

    private func withConnection<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { if let pointer { sqlite3_close(pointer) } }
        guard status == SQLITE_OK, let db = pointer else { throw DinnerError.storage }
        sqlite3_busy_timeout(db, 5_000)
        try execute("CREATE TABLE IF NOT EXISTS rotation (id INTEGER PRIMARY KEY CHECK (id = 1), state BLOB NOT NULL)", db)
        try execute("CREATE TABLE IF NOT EXISTS daily_logs (day INTEGER PRIMARY KEY, entry BLOB NOT NULL)", db)
        return try work(db)
    }

    private func load(_ db: OpaquePointer, defaultDate: Date) throws -> DinnerState {
        var state = try statement("SELECT state FROM rotation WHERE id = 1", db) { stmt in
            switch sqlite3_step(stmt) {
            case SQLITE_DONE:
                return DinnerState(entitlement: Entitlement(firstOpen: defaultDate))
            case SQLITE_ROW:
                return try JSONDecoder().decode(DinnerState.self, from: blob(stmt))
            default:
                throw DinnerError.storage
            }
        }
        state.logs = try statement("SELECT entry FROM daily_logs ORDER BY day", db) { stmt in
            let decoder = JSONDecoder()
            var logs: [DinnerLog] = []
            var step = sqlite3_step(stmt)
            while step == SQLITE_ROW {
                logs.append(try decoder.decode(DinnerLog.self, from: blob(stmt)))
                step = sqlite3_step(stmt)
            }
            guard step == SQLITE_DONE else { throw DinnerError.storage }
            return logs
        }
        return state
    }

    private func saveLogs(_ logs: [DinnerLog], previous: [LocalDay: DinnerLog], db: OpaquePointer) throws {
        let keys = Set(logs.map(\.day))
        guard keys.count == logs.count else { throw DinnerError.alreadyLogged }
        try statement("DELETE FROM daily_logs WHERE day = ?", db) { stmt in
            for day in previous.keys where !keys.contains(day) {
                guard sqlite3_bind_int64(stmt, 1, Int64(day.key)) == SQLITE_OK,
                      sqlite3_step(stmt) == SQLITE_DONE else { throw DinnerError.storage }
                sqlite3_reset(stmt)
            }
        }
        try statement("INSERT OR REPLACE INTO daily_logs (day, entry) VALUES (?, ?)", db) { stmt in
            let encoder = JSONEncoder()
            for log in logs where previous[log.day] != log {
                guard sqlite3_bind_int64(stmt, 1, Int64(log.day.key)) == SQLITE_OK else { throw DinnerError.storage }
                try bind(try encoder.encode(log), at: 2, to: stmt)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw DinnerError.storage }
                sqlite3_reset(stmt)
            }
        }
    }

    private func blob(_ stmt: OpaquePointer) throws -> Data {
        guard let bytes = sqlite3_column_blob(stmt, 0) else { throw DinnerError.storage }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
    }

    private func bind(_ data: Data, at index: Int32, to stmt: OpaquePointer) throws {
        let status = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(bytes.count),
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK else { throw DinnerError.storage }
    }

    private func transaction<T>(_ db: OpaquePointer, begin: String, _ work: () throws -> T) throws -> T {
        try execute(begin, db)
        do {
            let result = try work()
            try execute("COMMIT", db)
            return result
        } catch {
            try? execute("ROLLBACK", db)
            throw error
        }
    }

    private func execute(_ sql: String, _ db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DinnerError.storage }
    }

    private func statement<T>(_ sql: String, _ db: OpaquePointer, _ work: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &pointer, nil)
        defer { if let pointer { sqlite3_finalize(pointer) } }
        guard status == SQLITE_OK, let stmt = pointer else { throw DinnerError.storage }
        return try work(stmt)
    }

    func logCandidate(day: LocalDay, id: UUID, now: Date? = nil,
                      zone: TimeZone? = nil) throws -> (DinnerLog, DinnerState) {
        try update { state in
            let now = now ?? Date()
            let zone = zone ?? TimeZone.current
            guard day == LocalDay(now, zone: zone) else { throw DinnerError.staleDay }
            guard state.log(on: day) == nil else { throw DinnerError.alreadyLogged }
            guard state.choices(on: day, now: now).contains(where: { $0.id == id }) else {
                throw DinnerError.staleChoice
            }
            return try state.record(on: day, dinnerID: id, kind: .home, replacing: nil,
                                    now: now, zone: zone, countForReview: true)
        }
    }
}
