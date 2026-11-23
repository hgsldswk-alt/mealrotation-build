import Foundation
import Security

enum TrialKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.mealrotation.trial-start",
        kSecAttrAccount as String: "first-paid-open"
    ]

    static func firstOpen(_ now: Date) -> Date {
        var read = query
        read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let time = Double(String(decoding: data, as: UTF8.self)), time.isFinite {
            return Date(timeIntervalSince1970: time)
        }
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = Data(String(now.timeIntervalSince1970).utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
        return now
    }
}
