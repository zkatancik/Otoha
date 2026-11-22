import SwiftUI

@main struct OtohaApp: App {
  @StateObject private var remote = Remote()
  var body: some Scene {
    WindowGroup { RemoteView().environmentObject(remote) }
  }
}
