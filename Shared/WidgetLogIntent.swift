import AppIntents
import Foundation
import WidgetKit

struct WidgetLogIntent: AppIntent {
    static let title: LocalizedStringResource = "widget_action"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "widget_dinner_id") var dinnerID: String
    @Parameter(title: "widget_day") var dayKey: Int

    init() {}

    init(dinnerID: UUID, day: LocalDay) {
        self.dinnerID = dinnerID.uuidString
        self.dayKey = day.key
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        defer { WidgetCenter.shared.reloadTimelines(ofKind: Launch.widgetKind) }
        do {
            guard let id = UUID(uuidString: dinnerID) else { throw DinnerError.staleChoice }
            let store = try DinnerStore.shared()
            let key = dayKey
            try await Task.detached(priority: .userInitiated) {
                let now = Date()
                let day = LocalDay(now)
                guard day.key == key else { throw DinnerError.staleDay }
                _ = try store.logCandidate(day: day, id: id)
            }.value
            return .result(dialog: IntentDialog(stringLiteral: L.t("logged")))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: L.t("widget_stale")))
        }
    }
}
