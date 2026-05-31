import SwiftUI

@main
struct LlamaChatApp: App {
    @State private var viewModel: ChatViewModel = {
        ChatViewModel()
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
