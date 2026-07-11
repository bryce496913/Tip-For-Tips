import SwiftUI

struct LaunchScreen: View {
    var body: some View {
        AppScreen {
            Image("MainLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300, height: 300)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    LaunchScreen()
}
