import SwiftUI

struct HelpfulTips: View {
    @State private var selectedServiceIndex = 0
    @State private var showPicker = false
    private let services = ["Restaurant with table service", "Bars", "Yellow Taxi", "Uber/Lyft driver", "Food delivery", "Shuttle driver", "Doorman", "Porter", "Housekeeping", "Room Service", "Tour Guides", "Tour Bus Drivers", "Spa", "Hairdressers/Barbers", "Nail Salon"]
    private let recommendedTips: [String: String] = ["Restaurant with table service": "15-20%", "Bars": "15-20% or $1-$2 per drink", "Yellow Taxi": "10-20%", "Uber/Lyft driver": "10-20%", "Food delivery": "15-20%", "Shuttle driver": "$2-$5 per person", "Doorman": "$1-$5", "Porter": "$1-$2 per bag", "Housekeeping": "$2-$5 per night", "Room Service": "15-20%", "Tour Guides": "$2-$5 per participating person for local tours. 15-20% of the ticket price for a day trip", "Tour Bus Drivers": "$2-$5 per person", "Spa": "15-20%", "Hairdressers/Barbers": "15-20%", "Nail Salon": "15-20%"]
    private var selectedService: String { services.indices.contains(selectedServiceIndex) ? services[selectedServiceIndex] : services[0] }

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    ScreenTitle(text: "Helpful Tips", subtitle: "Review common tipping guidance by service type.")
                    ThemedCard {
                        Text("Service").appFont(.h2)
                        SecondaryButton(title: selectedService, systemImage: "list.bullet") { showPicker = true }
                            .accessibilityValue(selectedService)
                    }
                    ThemedCard {
                        Text("Recommendation").appFont(.h2)
                        Text(recommendedTips[selectedService] ?? "No recommendation available.")
                            .appFont(.h2)
                            .foregroundStyle(AppTheme.highlight)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Tip amounts can vary by location, service quality, and included fees. Check your bill before adding gratuity.")
                            .appFont(.paragraph)
                            .foregroundStyle(AppTheme.text.opacity(0.85))
                    }
                }
                .padding(AppSpacing.screen)
            }
        }
        .navigationTitle("Helpful Tips")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { ServicePicker(selectedServiceIndex: $selectedServiceIndex, services: services) }
    }
}

#Preview { HelpfulTips() }
