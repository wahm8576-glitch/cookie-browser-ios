import SwiftUI

@main
struct WahmCookieBrowserApp: App {
    @StateObject private var store = ContainerStore()

    var body: some Scene {
        WindowGroup {
            ContainerListView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Color(red: 0.13, green: 0.48, blue: 0.45))
        }
    }
}
