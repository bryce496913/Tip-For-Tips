import Foundation

enum TippingServiceCategory: String, CaseIterable, Identifiable {
    case restaurants, delivery, transportation, hotel, personalCare, tours, other
    var id: String { rawValue }
}

struct TippingService: Identifiable, Equatable {
    let id: String
    let name: String
    let recommendation: String
    let explanation: String
    let minimumPercentage: Decimal?
    let maximumPercentage: Decimal?
    let defaultPercentage: Decimal?
    let fixedAmountGuidance: String?
    let category: TippingServiceCategory
    let symbolName: String
}

enum TippingGuidance {
    static let services: [TippingService] = [
        .init(id: "restaurant", name: "Restaurant with table service", recommendation: "15–20%", explanation: "18–20% is an easy default for good table service.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .restaurants, symbolName: "fork.knife"),
        .init(id: "bar", name: "Bars", recommendation: "$1–$2 per drink or 15–20%", explanation: "Use a flat amount per drink or percentage for a full tab.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: "$1–$2 per drink", category: .restaurants, symbolName: "wineglass"),
        .init(id: "taxi", name: "Yellow Taxi", recommendation: "Around 15–20%.", explanation: "A smaller flat amount may work for short rides; tip more for luggage help.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .transportation, symbolName: "car"),
        .init(id: "rideshare", name: "Uber/Lyft driver", recommendation: "Around 15–20%.", explanation: "Consider the distance, luggage, wait time and overall service.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .transportation, symbolName: "car.fill"),
        .init(id: "food-delivery", name: "Food delivery", recommendation: "Around 10–15%, with more for difficult deliveries.", explanation: "Tip more for bad weather, stairs, distance, traffic, large orders or late-night service.", minimumPercentage: 10, maximumPercentage: 15, defaultPercentage: 15, fixedAmountGuidance: nil, category: .delivery, symbolName: "takeoutbag.and.cup.and.straw"),
        .init(id: "shuttle", name: "Shuttle driver", recommendation: "$2–$5 per person", explanation: "Especially when the driver handles bags.", minimumPercentage: nil, maximumPercentage: nil, defaultPercentage: nil, fixedAmountGuidance: "$2–$5 per person", category: .transportation, symbolName: "bus"),
        .init(id: "doorman", name: "Doorman", recommendation: "$1–$5", explanation: "Consider tipping when they carry bags, find transportation or provide extra help.", minimumPercentage: nil, maximumPercentage: nil, defaultPercentage: nil, fixedAmountGuidance: "$1–$5", category: .hotel, symbolName: "door.left.hand.open"),
        .init(id: "porter", name: "Porter", recommendation: "Around $2 for the first bag and $1 for each additional bag.", explanation: "Use fixed-dollar guidance instead of a bill percentage.", minimumPercentage: nil, maximumPercentage: nil, defaultPercentage: nil, fixedAmountGuidance: "$2 first bag, $1 each additional bag", category: .hotel, symbolName: "suitcase"),
        .init(id: "housekeeping", name: "Housekeeping", recommendation: "$2–$5 per night", explanation: "Leave it each day because staff may change.", minimumPercentage: nil, maximumPercentage: nil, defaultPercentage: nil, fixedAmountGuidance: "$2–$5 per night", category: .hotel, symbolName: "bed.double"),
        .init(id: "room-service", name: "Room Service", recommendation: "15–20%", explanation: "Check whether a gratuity or service charge is already included.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .hotel, symbolName: "tray"),
        .init(id: "tour-guides", name: "Tour Guides", recommendation: "$2–$5 per person locally; 15–20% for day trips", explanation: "Tour tipping varies by length, group size and whether the guide is independent.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: "$2–$5 per person for local tours", category: .tours, symbolName: "map"),
        .init(id: "spa", name: "Spa", recommendation: "Around 15–20%", explanation: "Ask how to split the tip when several people helped.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .personalCare, symbolName: "sparkles"),
        .init(id: "hair", name: "Hairdressers/Barbers", recommendation: "Around 15–20%", explanation: "Ask how to split the tip when several people helped.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .personalCare, symbolName: "scissors"),
        .init(id: "nails", name: "Nail Salon", recommendation: "Around 15–20%", explanation: "Ask how to split the tip when several people helped.", minimumPercentage: 15, maximumPercentage: 20, defaultPercentage: 18, fixedAmountGuidance: nil, category: .personalCare, symbolName: "hand.raised")
    ]
}
