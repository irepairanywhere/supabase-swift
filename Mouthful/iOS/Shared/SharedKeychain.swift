import Foundation
import Security

/// API keys, stored in the keychain and shared with the keyboard through the App Group
/// (an app group identifier doubles as a keychain access group).
enum SharedKeychain {
  static let cloudKeyAccount = "cloud-transcription-api-key"
  static let polishKeyAccount = "polish-api-key"
  private static let service = "com.rocketlaunchmedia.mouthful.ios"

  private static func baseQuery(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: SharedStorage.appGroup,
    ]
  }

  static func get(_ account: String) -> String? {
    var query = baseQuery(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Passing nil or an empty string deletes the item.
  static func set(_ value: String?, account: String) {
    let base = baseQuery(account)
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      SecItemDelete(base as CFDictionary)
      return
    }
    let data = Data(value.utf8)
    let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var add = base
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}
