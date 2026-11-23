import CoreImage
import Foundation
import UIKit
import XCTest

final class CoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let utc = TimeZone.gmt
    private var day: LocalDay { LocalDay(now, zone: utc) }

    private func localStore() throws -> DinnerStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return DinnerStore(url: folder.appendingPathComponent("test.sqlite"))
    }

    @discardableResult
    private func log(_ dinner: Dinner, daysAgo: Int, in state: inout DinnerState) throws -> DinnerLog {
        let past = day.adding(-daysAgo)
        return try state.record(on: past, dinnerID: dinner.id, kind: .home, replacing: nil,
                                now: past.date, zone: utc, countForReview: false)
    }

    func testZeroThroughThreeChoicesAndArchive() {
        let names = ["Noodles", "Beans", "Chili"]
        for count in 0...3 {
            var state = DinnerState()
            state.dinners = names.prefix(count).map { Dinner(name: $0) }
            XCTAssertEqual(state.choices(on: day, now: now).map(\.dinner.name), names.prefix(count).sorted())
        }
        var state = DinnerState()
        state.dinners = [Dinner(name: "Pie", archived: true), Dinner(name: "Stew")]
        XCTAssertEqual(state.choices(on: day, now: now).map(\.dinner.name), ["Stew"])
        state.dinners[0].archived = false
        XCTAssertEqual(state.choices(on: day, now: now).map(\.dinner.name), ["Pie", "Stew"])
    }

    func testOldestFirstNeverLoggedAndSameDayByName() throws {
        let a = Dinner(name: "Apple"), b = Dinner(name: "Beans"), c = Dinner(name: "Chili"), d = Dinner(name: "Dumplings")
        let stored = [d, c, b, a]
        let logs = [
            DinnerLog(day: day.adding(-3), kind: .home, dinnerID: b.id, name: b.name, createdAt: now, timeZone: utc.identifier),
            DinnerLog(day: day.adding(-3), kind: .home, dinnerID: a.id, name: a.name, createdAt: now, timeZone: utc.identifier),
            DinnerLog(day: day, kind: .home, dinnerID: d.id, name: d.name, createdAt: now, timeZone: utc.identifier)
        ]
        XCTAssertEqual(Rotation.ranked(stored, logs: logs, through: day, includeToday: false).map(\.dinner.name),
                       ["Chili", "Apple", "Beans"])
        XCTAssertEqual(Rotation.ranked(stored, logs: logs, through: day.adding(-1)).last?.last, day.adding(-3))
    }

    func testShuffleFillsAndPrefersNewChoicesThenStaysStable() throws {
        let store = try localStore()
        try store.update { state in
            state.dinners = ["Pie", "Noodles", "Soup", "Fish"].map { Dinner(name: $0) }
        }
        let initial = try store.read().choices(on: day, now: now).map(\.id)
        let (_, shuffled) = try store.update { $0.shuffle(on: day, now: now) }
        let next = shuffled.choices(on: day, now: now).map(\.id)
        XCTAssertEqual(next.count, 3)
        XCTAssertEqual(Set(next).subtracting(initial).count, 1)
        XCTAssertEqual(try store.read().choices(on: day, now: now).map(\.id), next)
        let (record, _) = try store.logCandidate(day: day, id: next[0], now: now, zone: utc)
        let (_, undone) = try store.update { try $0.undo(record) }
        XCTAssertEqual(undone.choices(on: day, now: now).map(\.id), next)
    }

    func testShuffleWithEnoughDinnersAndAllRecentlyMade() {
        var state = DinnerState()
        state.dinners = (0..<7).map { Dinner(name: "Meal \($0)") }
        let ranked = state.dinners.map { DinnerChoice(dinner: $0, last: day.adding(-1)) }
        let first = Rotation.batch(ranked, on: day, avoid: 2)
        let second = Rotation.batch(ranked, on: day, avoid: 2, excluding: Set(first.map(\.id)), turn: 1)
        XCTAssertEqual(second.count, 3)
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
    }

    func testBatchPasteTrimsAndDeduplicatesWithoutReplacingTags() {
        let existing = [Dinner(name: "Crème brûlée", quick: true, archived: true)]
        let names = Rotation.lines("  Soup\r\n\n SOUP \n Rice \n crème brûlée\n\(String(repeating: "x", count: 81))",
                                   existing: existing)
        XCTAssertEqual(names, ["Soup", "Rice"])
    }

    func testReplacementsUndoRenameAndHistorySnapshots() throws {
        var state = DinnerState()
        let a = Dinner(name: "Pasta"), b = Dinner(name: "Stew")
        state.dinners = [a, b]
        let old = try log(a, daysAgo: 2, in: &state)
        state.dinners[0].name = "Tomato pasta"
        XCTAssertEqual(state.log(on: old.day)?.name, "Pasta")
        let changed = try state.record(on: old.day, dinnerID: b.id, kind: .home, replacing: old.id,
                                       now: now, zone: utc, countForReview: false)
        XCTAssertThrowsError(try state.undo(old))
        XCTAssertEqual(state.log(on: old.day)?.id, changed.id)
        XCTAssertEqual(state.choices(on: day, now: now).first?.dinner.id, a.id)
        XCTAssertEqual(state.homeDays, 1)
    }

    func testLocalMidnightAndTimeZoneDoNotMoveStoredRecord() throws {
        let before = Date(timeIntervalSince1970: 1_799_999_999)
        let next = LocalDay.calendar(in: utc).startOfDay(for: before).addingTimeInterval(86_400)
        let west = try XCTUnwrap(TimeZone(secondsFromGMT: -7 * 3600))
        XCTAssertEqual(LocalDay(next.addingTimeInterval(-1), zone: utc).adding(1), LocalDay(next, zone: utc))
        XCTAssertNotEqual(LocalDay(next, zone: west), LocalDay(next, zone: utc))
        let store = try localStore()
        let dinner = Dinner(name: "Soup")
        try store.update { $0.dinners.append(dinner) }
        let oldDay = LocalDay(next, zone: west)
        XCTAssertThrowsError(try store.logCandidate(day: oldDay, id: dinner.id, now: next, zone: utc))
        let (record, _) = try store.logCandidate(day: oldDay, id: dinner.id, now: next, zone: west)
        XCTAssertEqual(record.day, oldDay)
        XCTAssertEqual(record.timeZone, west.identifier)
        XCTAssertNil(try store.read().log(on: LocalDay(next, zone: utc)))
    }

    func testConcurrentConnectionsKeepOneDinnerPerDay() async throws {
        let store = try localStore()
        let choice = Dinner(name: "Soup")
        let now = self.now, day = self.day, zone = utc
        try store.update { $0.dinners.append(choice) }
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<12 {
                group.addTask { (try? store.logCandidate(day: day, id: choice.id, now: now, zone: zone)) != nil }
            }
            var count = 0
            for await result in group where result { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(try store.read().logs.count, 1)
        XCTAssertEqual(try store.read().coreDays, [day])
    }

    func testOfflineColdStartAndStaleCandidate() throws {
        let store = try localStore()
        let dinner = Dinner(name: "Soup")
        try store.update(defaultDate: now) { $0.dinners.append(dinner) }
        try store.update { $0.dinners[0].archived = true }
        let cold = DinnerStore(url: store.url)
        XCTAssertEqual(try cold.read().entitlement.firstOpen, now)
        XCTAssertThrowsError(try cold.logCandidate(day: day, id: dinner.id, now: now, zone: utc))
        XCTAssertTrue(try cold.read().logs.isEmpty)
    }

    func testTrialStartsAtFirstOpenAndReceiptNeverExtendsIt() {
        var access = Entitlement(firstOpen: now)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(access.hasPro(at: now, free: false))
        XCTAssertTrue(access.hasPro(at: now.addingTimeInterval(30 * 86_400 - 1), free: false))
        XCTAssertFalse(access.hasPro(at: now.addingTimeInterval(30 * 86_400), free: false))
        access.applyPurchases(pro: false, trial: now.addingTimeInterval(10 * 86_400))
        XCTAssertEqual(access.trialStart, now)
        let restored = now.addingTimeInterval(-40 * 86_400)
        access.applyPurchases(pro: false, trial: restored)
        XCTAssertEqual(access.trialStart, restored)
        XCTAssertFalse(access.hasPro(at: now, free: false))
    }

    func testLegacyPaidStartBuyoutAndRevocation() {
        var access = Entitlement(firstOpen: now.addingTimeInterval(-90 * 86_400), proStartedAt: now)
        XCTAssertTrue(access.hasPro(at: now, free: false))
        let expired = now.addingTimeInterval(100 * 86_400)
        access.applyPurchases(pro: true, trial: nil)
        XCTAssertTrue(access.hasPro(at: expired, free: false))
        access.applyPurchases(pro: false, trial: nil)
        XCTAssertFalse(access.hasPro(at: expired, free: false))
    }

    func testExpiredAccessKeepsDataAndSavedReviews() throws {
        var state = DinnerState(entitlement: Entitlement(firstOpen: now))
        let entry = Dinner(name: "Stew")
        state.dinners = [entry]
        state.quickOnly = true
        let start = day.adding(-3)
        _ = try log(entry, daysAgo: 1, in: &state)
        let saved = state.createReview(start: start, now: now)
        XCTAssertNotNil(saved)
        let expired = now.addingTimeInterval(31 * 86_400)
        XCTAssertEqual(state.createReview(start: start, now: expired), saved)
        XCTAssertNil(state.createReview(start: start.adding(7), now: expired))
        XCTAssertEqual(state.choices(on: LocalDay(expired), now: expired).first?.id, entry.id)
        XCTAssertEqual(state.logs.count, 1)
    }

    func testMenuCodesRejectMalformedOversizeAndUnknownFieldsAndMergeAtomically() throws {
        let store = try localStore()
        let old = Dinner(name: "Soup", quick: false)
        try store.update { $0.dinners = [old] }
        let code = try MenuCode.encode([MenuItem(name: " soup ", quick: true), MenuItem(name: "Rice", quick: true)])
        let items = try MenuCode.decode(code)
        XCTAssertEqual(MenuCode.preview(items, existing: [old]).added.map(\.name), ["Rice"])
        let bad = Data(#"[{"name":"Rice","date":"private"}]"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        for invalid in ["MR2:AAAA", "MR1:??", "MR1:" + bad, String(repeating: "A", count: 24 * 1024 + 1)] {
            XCTAssertThrowsError(try store.update { state in
                state.dinners.removeAll()
                MenuCode.merge(try MenuCode.decode(invalid), into: &state)
            })
            XCTAssertEqual(try store.read().dinners, [old])
        }
        try store.update { MenuCode.merge(items, into: &$0) }
        XCTAssertEqual(try store.read().dinners.first, old)
        XCTAssertEqual(try store.read().dinners.last?.quick, true)
    }

    func testBackupVersionMergeAndSafeCSV() throws {
        var source = DinnerState()
        let dinner = Dinner(name: "=SUM(1,2), \"Stew\"")
        source.dinners = [dinner]
        let imported = try log(dinner, daysAgo: 1, in: &source)
        let data = try MenuBackup(state: source, now: now).encoded()
        let raw = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":0")
        XCTAssertThrowsError(try MenuBackup.read(Data(raw.utf8)))
        let backup = try MenuBackup.read(data)
        var target = DinnerState()
        let existing = Dinner(name: dinner.name, quick: true)
        target.dinners = [existing]
        let result = backup.merge(into: &target)
        XCTAssertEqual(result.dinners, 0)
        XCTAssertEqual(result.logs, 1)
        XCTAssertEqual(target.log(on: imported.day)?.dinnerID, existing.id)
        XCTAssertTrue(String(decoding: MenuBackup.csv(target.logs), as: UTF8.self).contains("\"'=SUM(1,2), \"\"Stew\"\"\""))
        XCTAssertEqual(backup.merge(into: &target).logs, 0)
    }

    func testBackupRestoresSavedReviewsAndInitialPreferences() throws {
        var source = DinnerState(entitlement: Entitlement(firstOpen: now))
        source.quickOnly = true
        source.avoidDays = 6
        let week = try XCTUnwrap(source.createReview(start: day, now: now))
        let backup = try MenuBackup.read(MenuBackup(state: source, now: now).encoded())
        var target = DinnerState()
        target.entitlement.purchasedPro = true
        XCTAssertEqual(backup.preview(in: target).reviews, 1)
        XCTAssertEqual(backup.preview(in: target).preferences?.avoidDays, 6)
        _ = backup.merge(into: &target)
        XCTAssertTrue(target.quickOnly)
        XCTAssertEqual(target.avoidDays, 6)
        XCTAssertEqual(target.reviews, [week])
        XCTAssertTrue(target.entitlement.purchasedPro)
        XCTAssertTrue(backup.preview(in: target).isEmpty)
    }

    func testDistinctCoreDatesMilestoneAndUndo() throws {
        var state = DinnerState()
        let dinner = Dinner(name: "Stew")
        state.dinners = [dinner]
        for index in 0..<7 {
            let date = day.adding(-index)
            _ = try state.record(on: date, dinnerID: dinner.id, kind: .home, replacing: nil,
                                 now: date.date, zone: utc, countForReview: index < 3)
        }
        XCTAssertEqual(state.homeDays, 7)
        XCTAssertEqual(state.coreDays.count, 3)
        let current = try XCTUnwrap(state.log(on: day))
        try state.undo(current)
        XCTAssertEqual(state.homeDays, 6)
        XCTAssertEqual(state.coreDays.count, 2)
    }

    func testSharePNGHasRequiredSizeAndDecodableQRCode() throws {
        let url = URL(string: "https://apps.apple.com/app/id123456789")!
        for link in [nil, url] as [URL?] {
            let data = ShareCard.png(ShareContent(names: ["Ginger rice", "Soup"]), showNames: true, link: link)
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1350)
            let reader = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let codes = reader.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertTrue(codes.contains((link ?? ShareCard.placeholder).absoluteString))
        }
        XCTAssertNotEqual(L.t("tonight"), "tonight")
    }
}
