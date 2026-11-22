import Security
import SwiftUI

@main struct OtohaApp: App {
  @StateObject private var remote = Remote()
  init() { Self.removeRetiredWebhookCredentials(.standard) }

  var body: some Scene {
    WindowGroup { RemoteView().environmentObject(remote) }
  }

  private static func removeRetiredWebhookCredentials(_ defaults: UserDefaults) {
    let migration = "removedWebhookCredentials.v1"
    guard !defaults.bool(forKey: migration) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "Otoha.IRWebhook",
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { return }
    struct SavedKind: Decodable { let kind: String }
    for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("directIR.") {
      if let data = value as? Data, (try? JSONDecoder().decode(SavedKind.self, from: data))?.kind == "webhook" {
        defaults.removeObject(forKey: key)
      }
    }
    defaults.set(true, forKey: migration)
  }
}
