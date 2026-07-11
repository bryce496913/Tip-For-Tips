import SwiftUI

struct SplitBillCalculator: View {
    @State private var showEvenSplitSheet = false
    @State private var showCustomSplitSheet = false

    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Image("SplitBillCalculator")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 190, height: 190)
                    .accessibilityHidden(true)
                ScreenTitle(text: "Split Bill Calculator")
                ThemedCard {
                    PrimaryButton(title: "Even Split") { showEvenSplitSheet = true }
                    SecondaryButton(title: "Custom Split") { showCustomSplitSheet = true }
                }
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("Split Bill")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEvenSplitSheet) { EvenSplitView() }
        .sheet(isPresented: $showCustomSplitSheet) { CustomSplitView() }
    }
}

#Preview { SplitBillCalculator() }
