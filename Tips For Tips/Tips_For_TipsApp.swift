import SwiftUI

@main
struct Tips_For_TipsApp: App {
    @State private var showLaunchScreen = true
    @State private var launchTransitionScheduled = false

    var body: some Scene {
        WindowGroup {
            Group {
                if showLaunchScreen {
                    LaunchScreen()
                        .task { scheduleLaunchTransitionIfNeeded() }
                } else {
                    MainMenu()
                }
            }
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.35), value: showLaunchScreen)
        }
    }

    private func scheduleLaunchTransitionIfNeeded() {
        guard !launchTransitionScheduled else { return }
        launchTransitionScheduled = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            showLaunchScreen = false
        }
    }
}
