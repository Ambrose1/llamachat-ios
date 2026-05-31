import SwiftUI
import AppKit

@main
struct LlamaChatApp: App {
    @State private var svm = ChatViewModel()

    init() {
        // This is a proper GUI app, not a background process
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: svm)
                .frame(minWidth: 480, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
