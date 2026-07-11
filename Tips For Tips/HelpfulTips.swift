import SwiftUI

struct HelpfulTips: View {
    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Image("HelpfulTips")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 190, height: 190)
                    .accessibilityHidden(true)
                ScreenTitle(text: "Helpful Tips")
                ThemedCard {
                    Text("Select a service in Tip Calculator to view the existing tip recommendations for restaurants, rides, deliveries, hotels, salons, tours, and spa visits.")
                        .appFont(.paragraph)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("Helpful Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { HelpfulTips() }
