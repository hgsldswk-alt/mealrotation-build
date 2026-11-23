import Foundation

enum Demo {
    static let keys = ["sample_chicken", "sample_salmon", "sample_soup",
                       "sample_noodles", "sample_tacos", "sample_curry", "sample_rice", "sample_pasta"]
    static func state(at now: Date) -> DinnerState {
        let day = LocalDay(now)
        var state = DinnerState(entitlement: Entitlement(firstOpen: now.addingTimeInterval(-5 * 86_400)))
        for (index, key) in keys.enumerated() {
            let dinner = Dinner(name: L.t(key), quick: index >= 3)
            state.dinners.append(dinner)
            let days = [24, 19, 16, 11, 7, 5, 3, 2]
            let earlier = day.adding(-days[index])
            state.logs.append(DinnerLog(day: earlier, kind: .home, dinnerID: dinner.id,
                                        name: dinner.name, createdAt: earlier.date, timeZone: TimeZone.current.identifier))
        }
        return state
    }
}
