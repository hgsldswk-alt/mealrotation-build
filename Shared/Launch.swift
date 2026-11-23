import Foundation

enum Launch {
    static let freePeriod = false
    static let appGroup = "group.com.hgsldswk.mealrotation"
    static let widgetKind = "TonightDinners"
    static let cookingTimeURL = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?term=开饭倒推".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var testing: Bool { arguments.contains("-ui-testing") }
    static var isFree: Bool { freePeriod && !(testing && arguments.contains(where: ["-paid-mode", "-paywall", "-expired"].contains)) }
    static var appStoreURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}
