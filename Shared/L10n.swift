import Foundation

final class LocalizationBundleToken: NSObject {}

enum L {
    private static let bundle = Bundle(for: LocalizationBundleToken.self)
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }
}
