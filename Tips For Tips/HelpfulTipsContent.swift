import Foundation

struct QuickTippingGuideEntry: Identifiable {
    let id: Int
    let service: String
    let recommendation: String
    let explanation: String
    let symbolName: String
}

struct TippingFAQ: Identifiable {
    let id: Int
    let question: String
    let answer: String
    let bulletPoints: [String]
}

enum TippingTipCategory: String, CaseIterable, Identifiable {
    case basics = "Understanding the Basics"
    case restaurantsAndBars = "Restaurants and Bars"
    case takeoutAndDelivery = "Takeout and Delivery"
    case hotelsAndTransportation = "Hotels and Transportation"
    case personalServicesAndTours = "Personal Services and Tours"
    case confidenceAndCulturalAwareness = "Confidence and Cultural Awareness"

    var id: String { rawValue }
}

struct TippingTip: Identifiable {
    let id: Int
    let title: String
    let explanation: String
    let category: TippingTipCategory
}

enum HelpfulTipsContent {
    static let introductionTitle = "Understanding Tipping in the USA"
    static let introductionParagraphs = [
        "Tipping in the United States can feel confusing, especially if you come from a country where service charges are included in the price. The most important thing to remember is that tipping is a cultural custom—not a test.",
        "Use this guide to understand what is expected, what is optional, and how to make a decision that feels fair and comfortable."
    ]

    static let quickGuideFooter = "These are guidelines, not fixed rules. Location, service level, order size and personal budget can all affect the amount."
    static let finalReminderParagraphs = [
        "Tipping in the United States is meant to recognize service, but modern tipping screens can make every transaction feel like an obligation.",
        "You do not need to tip every person who presents a payment screen. You also should not feel ashamed if your tip is smaller than someone else’s.",
        "Know the custom, check for included charges, consider the work involved and choose an amount that feels fair."
    ]
    static let footerNote = "Tipping customs and wage rules can vary by location and business. When a bill is unclear, ask the business how its service charges and gratuities work."

    static let quickGuide: [QuickTippingGuideEntry] = [
        .init(id: 1, service: "Sit-down restaurant", recommendation: "15–20%", explanation: "18–20% is an easy default.", symbolName: "fork.knife"),
        .init(id: 2, service: "Buffet", recommendation: "Around 10%", explanation: "Staff may still clear plates and help at the table.", symbolName: "tray"),
        .init(id: 3, service: "Bartender", recommendation: "$1–$2 per drink", explanation: "Or 15–20% of the tab.", symbolName: "wineglass"),
        .init(id: 4, service: "Food delivery", recommendation: "Around 10–15%", explanation: "Tip more for difficult deliveries.", symbolName: "takeoutbag.and.cup.and.straw"),
        .init(id: 5, service: "Takeout", recommendation: "Usually optional", explanation: "Consider up to 10% for large or complicated orders.", symbolName: "bag"),
        .init(id: 6, service: "Taxi", recommendation: "Around 15–20%", explanation: "A smaller flat amount may work for short rides.", symbolName: "car"),
        .init(id: 7, service: "Hotel housekeeping", recommendation: "Around $2–$5", explanation: "Leave it each day.", symbolName: "bed.double"),
        .init(id: 8, service: "Bellhop", recommendation: "Around $2 first bag", explanation: "Then $1 for each additional bag.", symbolName: "suitcase"),
        .init(id: 9, service: "Valet", recommendation: "Around $2–$5", explanation: "Tip when your car is returned.", symbolName: "key"),
        .init(id: 10, service: "Hair, beauty and spa services", recommendation: "Around 15–20%", explanation: "Ask how to split the tip when several people helped.", symbolName: "scissors")
    ]

    static let faqs: [TippingFAQ] = [
        .init(id: 1, question: "Why is tipping so common in the United States?", answer: "Tipping has become part of how many American service industries operate. In some states, employers may count a portion of an employee’s tips toward minimum-wage requirements. Other states require employers to pay the full state minimum wage before tips.\n\nBecause the rules vary, you should not assume that every server is paid the same hourly wage. Tips remain an important part of the income of many restaurant, hospitality and personal-service workers.", bulletPoints: []),
        .init(id: 2, question: "Is tipping legally required?", answer: "Most tips are voluntary. You normally choose whether to tip and how much to leave.\n\nA mandatory service charge or automatic gratuity is different. It is part of the bill and must usually be paid. Always read the bill before adding another tip.", bulletPoints: []),
        .init(id: 3, question: "What is a service charge?", answer: "A service charge is an amount automatically added by the business. You may see descriptions such as:\n\nA service charge is not legally treated the same way as a voluntary tip. Ask the business whether the charge replaces the tip and whether it is distributed to employees.", bulletPoints: ["Service charge", "Automatic gratuity", "Hospitality charge", "Administrative fee", "Large-party gratuity", "Delivery fee"]),
        .init(id: 4, question: "How much should I tip at a sit-down restaurant?", answer: "A tip of 15–20% of the pre-tax bill is a commonly recognized range. Many customers use 18–20% as a simple default for good table service.\n\nYou can tip more for exceptional service or reduce the amount when the service itself was seriously poor.", bulletPoints: []),
        .init(id: 5, question: "Should I calculate the tip before or after tax?", answer: "Traditionally, restaurant tips are calculated using the pre-tax subtotal.\n\nHowever, many customers calculate the tip using the final total because it is easier. Either method is acceptable. The difference is usually small.", bulletPoints: []),
        .init(id: 6, question: "Should I tip at a buffet?", answer: "Around 10% is a common guideline. Even though you collect your own food, staff may still bring drinks, clear plates, clean the table and assist you during the meal.\n\nConsider tipping more when a server provides significant table service.", bulletPoints: []),
        .init(id: 7, question: "Do I need to tip for takeout?", answer: "Tipping for a simple takeout order is usually optional. A tip may be appropriate when:\n\nYou do not need to feel guilty selecting “No Tip” for a simple counter transaction.", bulletPoints: ["The order is large or complicated.", "Staff carefully packaged many items.", "Staff provided curbside delivery.", "You received extra help.", "You are a regular customer.", "The business went beyond its normal service."]),
        .init(id: 8, question: "Should I tip at coffee shops?", answer: "A coffee-shop tip is usually optional, especially when you order at the counter and collect the drink yourself.\n\nYou might leave a dollar or a small percentage for complicated drinks, exceptional service or a barista who regularly looks after you.", bulletPoints: []),
        .init(id: 9, question: "Why does every payment screen ask for a tip?", answer: "Modern payment systems make it easy for businesses to display a tipping screen. The screen does not automatically mean that a tip is expected.\n\nConsider how much personal service you received. You may choose a suggested percentage, enter a custom amount or select no tip.", bulletPoints: []),
        .init(id: 10, question: "Should I tip a bartender?", answer: "A common guideline is $1–$2 per drink or approximately 15–20% of the total tab.\n\nConsider tipping more for cocktails that require significant preparation, attentive table service or help choosing drinks.", bulletPoints: []),
        .init(id: 11, question: "How much should I tip for food delivery?", answer: "Around 10–15% or a reasonable flat amount is a useful starting point.\n\nTip more when the delivery involves:\n\nA delivery fee is not automatically a tip for the driver.", bulletPoints: ["Bad weather", "Heavy traffic", "A long distance", "Many bags", "Stairs or a difficult entrance", "A large or complicated order", "Late-night service"]),
        .init(id: 12, question: "Should I tip my taxi or rideshare driver?", answer: "Around 15–20% is a common taxi guideline. A smaller flat amount may be reasonable for a short ride.\n\nConsider tipping more when the driver helps with bags, waits for you, handles a difficult route, keeps the vehicle especially clean or provides excellent service.", bulletPoints: []),
        .init(id: 13, question: "Should I tip hotel housekeeping?", answer: "A common guideline is $2–$5 per day. Leave the tip each day rather than waiting until checkout because a different person may clean the room each day.\n\nPlace the money somewhere visible with a note that says “Housekeeping—Thank you.”", bulletPoints: []),
        .init(id: 14, question: "Which other hotel workers should I tip?", answer: "Tipping may be appropriate for:\n\nA smile and a sincere thank-you are enough when someone only opens a door or answers a simple question.", bulletPoints: ["Bellhops: When they carry or store your luggage.", "Valets: When your vehicle is returned.", "Doormen: When they carry bags, find transportation or provide extra help.", "Concierges: When they arrange tickets, reservations or a difficult request.", "Room-service staff: When a gratuity or service charge is not already included."]),
        .init(id: 15, question: "Should I tip at a hair salon, spa or massage appointment?", answer: "Approximately 15–20% is common for hair, nail, facial, waxing and massage services.\n\nAsk whether the tip can be divided when several people helped you.", bulletPoints: []),
        .init(id: 16, question: "Is cash better than tipping by card?", answer: "Both are acceptable.\n\nCash may reach the employee more quickly and can be useful for hotel staff, valets and bellhops. Card tips are convenient and create a clear payment record.\n\nUse whichever method is available and comfortable for you.", bulletPoints: []),
        .init(id: 17, question: "Can I leave a custom amount instead of the suggested percentages?", answer: "Yes. Suggested buttons are only suggestions.\n\nYou can choose a custom dollar amount, calculate your own percentage or select no tip when tipping is optional. The highest button is not automatically the correct choice.", bulletPoints: []),
        .init(id: 18, question: "What should I do if the service was poor?", answer: "First consider what caused the problem.\n\nA server may not control:\n\nIf the employee provided poor service, you may reduce the tip. For serious problems, politely speak with a manager so the business has an opportunity to fix the issue.", bulletPoints: ["Slow kitchen service", "Incorrect restaurant policies", "Sold-out items", "Staffing shortages", "Prices", "Problems caused by another department"]),
        .init(id: 19, question: "Should I leave nothing after terrible service?", answer: "You may leave no tip when service was genuinely unacceptable, but speaking with a manager is often more useful. A zero tip can look accidental or may not explain what went wrong.\n\nA small tip combined with a polite complaint can communicate that you understood the custom but were dissatisfied with the service.", bulletPoints: []),
        .init(id: 20, question: "When should I tip more than usual?", answer: "Consider tipping more when someone:", bulletPoints: ["Provides exceptional or unusually thoughtful service.", "Handles a complicated request.", "Helps with heavy luggage.", "Works in severe weather.", "Accommodates allergies or dietary needs.", "Helps your group after closing time.", "Cleans up an unusually large mess.", "Solves a travel problem.", "Looks after children, older travelers or someone with accessibility needs.", "Makes a special occasion memorable."]),
        .init(id: 21, question: "Is it rude to tip a small amount?", answer: "A small tip is still an expression of appreciation. You should not spend beyond your budget simply because a payment screen creates pressure.\n\nHowever, in situations where tipping is a well-established custom—such as full-service restaurant dining—a very small tip may be understood as a sign that something was wrong.\n\nThe best approach is to know the custom, consider the service and choose an amount you can reasonably afford.", bulletPoints: []),
        .init(id: 22, question: "Should I feel embarrassed about selecting “No Tip”?", answer: "No. A tipping screen is not a judgment screen.\n\nSelecting no tip can be completely reasonable when:\n\nBe polite, make your choice and complete the transaction confidently.", bulletPoints: ["You received no personal service.", "You purchased a packaged product.", "You used self-checkout.", "You collected a simple counter order.", "A service charge was already included.", "The business does not normally rely on tips.", "Tipping would exceed your budget."]),
        .init(id: 23, question: "What if I cannot afford the recommended percentage?", answer: "Tip what you reasonably can. A smaller amount given sincerely is better than feeling pressured into spending money you do not have.\n\nWhen planning a sit-down meal or other traditionally tipped service, try to include the expected tip in your budget before booking or ordering.", bulletPoints: []),
        .init(id: 24, question: "Can I show appreciation without leaving more money?", answer: "Yes. You can also:\n\nThese actions do not always replace an expected tip, but they can provide valuable recognition.", bulletPoints: ["Thank the employee by name.", "Compliment them to a manager.", "Leave a positive review.", "Mention them in a customer survey.", "Write a short thank-you note.", "Be patient and respectful.", "Recommend the business to others."])
    ]

    static let tips: [TippingTip] = [
        .init(id: 1, title: "Think of the tip as part of your travel budget.", explanation: "When planning restaurant meals, taxis, hotels and personal services, leave room in your budget for gratuities.", category: .basics),
        .init(id: 2, title: "Check the bill before adding anything.", explanation: "Look for service charges, hospitality fees, delivery fees and automatic gratuities.", category: .basics),
        .init(id: 3, title: "Do not tip twice by accident.", explanation: "A restaurant may automatically add gratuity for large groups or certain tourist areas.", category: .basics),
        .init(id: 4, title: "A service charge and a tip are not always the same.", explanation: "Ask whether an included charge replaces the tip when the bill is unclear.", category: .basics),
        .init(id: 5, title: "Suggested percentages are not commands.", explanation: "You are allowed to select a custom amount or no tip.", category: .basics),
        .init(id: 6, title: "Consider the amount of personal service.", explanation: "More time, attention, physical effort and expertise usually make a tip more appropriate.", category: .basics),
        .init(id: 7, title: "Local customs can vary.", explanation: "Expect slightly different practices between cities, states, resorts and types of businesses.", category: .basics),
        .init(id: 8, title: "Not every tipped worker earns the same hourly wage.", explanation: "Federal, state and local wage rules differ significantly.", category: .basics),
        .init(id: 9, title: "A tip is usually voluntary.", explanation: "Mandatory charges are listed on the bill; voluntary tips are chosen by the customer.", category: .basics),
        .init(id: 10, title: "Do not let embarrassment make the decision for you.", explanation: "Pause, check the bill and choose the amount that makes sense.", category: .basics),
        .init(id: 11, title: "Use 18–20% as an easy restaurant default.", explanation: "This works well for good service at most full-service restaurants.", category: .restaurantsAndBars),
        .init(id: 12, title: "Calculate 20% quickly by moving the decimal point.", explanation: "For a $50 bill, 10% is $5 and 20% is $10.", category: .restaurantsAndBars),
        .init(id: 13, title: "For 15%, calculate 10% and add half.", explanation: "For a $60 bill, 10% is $6, half of that is $3, and 15% is $9.", category: .restaurantsAndBars),
        .init(id: 14, title: "You can round the tip.", explanation: "There is no need to calculate the amount to the exact cent.", category: .restaurantsAndBars),
        .init(id: 15, title: "Tip based on the original value of discounted meals.", explanation: "When using a coupon or complimentary item, consider the service provided for the full meal.", category: .restaurantsAndBars),
        .init(id: 16, title: "Large groups may already have gratuity included.", explanation: "Review the bill carefully before adding an additional amount.", category: .restaurantsAndBars),
        .init(id: 17, title: "Separate bills do not remove the need to tip.", explanation: "Each person should calculate a tip using their own portion of the bill.", category: .restaurantsAndBars),
        .init(id: 18, title: "Do not blame the server for everything.", explanation: "Kitchen delays, menu prices and restaurant policies may be outside the server’s control.", category: .restaurantsAndBars),
        .init(id: 19, title: "Tell someone when there is a problem.", explanation: "A calm conversation gives the business a chance to correct the issue.", category: .restaurantsAndBars),
        .init(id: 20, title: "Tip more when your group requires extra work.", explanation: "Large parties, repeated requests, major spills and long stays can create additional work.", category: .restaurantsAndBars),
        .init(id: 21, title: "Tip your bartender as you go or when closing the tab.", explanation: "Either method is normal.", category: .restaurantsAndBars),
        .init(id: 22, title: "A tip jar is usually optional.", explanation: "Leave something when you receive extra attention, have a complicated order or want to support a regular barista.", category: .restaurantsAndBars),
        .init(id: 23, title: "Simple takeout does not always require a tip.", explanation: "A quick pickup of a small order can reasonably receive no tip.", category: .takeoutAndDelivery),
        .init(id: 24, title: "Consider tipping for complicated takeout orders.", explanation: "Large catering orders, special packaging and curbside delivery require more work.", category: .takeoutAndDelivery),
        .init(id: 25, title: "Delivery fees may not go to the driver.", explanation: "Treat the driver’s tip as a separate decision unless the app clearly says otherwise.", category: .takeoutAndDelivery),
        .init(id: 26, title: "Weather matters.", explanation: "Rain, snow, extreme heat and dangerous road conditions justify a larger delivery tip.", category: .takeoutAndDelivery),
        .init(id: 27, title: "Distance and difficulty matter.", explanation: "Long walks, stairs, confusing buildings and limited parking add time and effort.", category: .takeoutAndDelivery),
        .init(id: 28, title: "Do not reduce a driver’s tip because the restaurant was slow.", explanation: "The driver may have spent extra unpaid time waiting for the order.", category: .takeoutAndDelivery),
        .init(id: 29, title: "Give useful delivery instructions.", explanation: "Clear directions, working access codes and a visible address make the delivery safer and easier.", category: .takeoutAndDelivery),
        .init(id: 30, title: "A small order still requires a trip.", explanation: "Consider using a reasonable minimum tip rather than calculating a tiny percentage.", category: .takeoutAndDelivery),
        .init(id: 31, title: "Leave housekeeping tips daily.", explanation: "The same housekeeper may not clean your room throughout the entire stay.", category: .hotelsAndTransportation),
        .init(id: 32, title: "Label housekeeping money clearly.", explanation: "A note helps employees understand that the cash was intentionally left as a tip.", category: .hotelsAndTransportation),
        .init(id: 33, title: "Tip when the service is completed.", explanation: "Tip a valet when your car is returned and a bellhop after your luggage reaches the room.", category: .hotelsAndTransportation),
        .init(id: 34, title: "Keep small bills available.", explanation: "One-dollar and five-dollar bills are useful for hotel and transportation tips.", category: .hotelsAndTransportation),
        .init(id: 35, title: "Tip more for heavy or numerous bags.", explanation: "Physical effort and extra trips deserve consideration.", category: .hotelsAndTransportation),
        .init(id: 36, title: "A doorman does not need a tip for simply opening a door.", explanation: "A verbal thank-you is appropriate.", category: .hotelsAndTransportation),
        .init(id: 37, title: "Consider a tip when a doorman provides real assistance.", explanation: "Examples include handling luggage, finding a taxi in bad weather or solving a transportation problem.", category: .hotelsAndTransportation),
        .init(id: 38, title: "Tip a concierge for completed special arrangements.", explanation: "Simple directions do not normally require a tip. Difficult reservations, tickets or special arrangements may.", category: .hotelsAndTransportation),
        .init(id: 39, title: "Check room-service receipts carefully.", explanation: "A delivery charge, service charge and tip line may all appear on the same bill.", category: .hotelsAndTransportation),
        .init(id: 40, title: "Tip transportation workers for extra help.", explanation: "Luggage assistance, waiting, accessibility support and exceptional care may justify a larger amount.", category: .hotelsAndTransportation),
        .init(id: 41, title: "Plan for a tip when booking salon or spa services.", explanation: "The listed price may not include gratuity.", category: .personalServicesAndTours),
        .init(id: 42, title: "Ask how to divide a salon tip.", explanation: "Several employees may wash, cut, color or style your hair.", category: .personalServicesAndTours),
        .init(id: 43, title: "Check whether a massage is medical or hospitality-based.", explanation: "Tipping is common at spas but may not be appropriate in a medical or physical-therapy setting.", category: .personalServicesAndTours),
        .init(id: 44, title: "Follow the tour company’s guidance.", explanation: "Tour tipping varies by the length of the tour, group size and whether the guide is independent.", category: .personalServicesAndTours),
        .init(id: 45, title: "Reward guides who add genuine value.", explanation: "Local knowledge, safety assistance, personalized recommendations and excellent storytelling may deserve recognition.", category: .personalServicesAndTours),
        .init(id: 46, title: "Do not apologize for using a custom amount.", explanation: "Entering your own amount is a normal part of the payment process.", category: .confidenceAndCulturalAwareness),
        .init(id: 47, title: "Zero can be appropriate in optional situations.", explanation: "Self-service kiosks, packaged retail products and ordinary counter purchases do not always require tips.", category: .confidenceAndCulturalAwareness),
        .init(id: 48, title: "Never offer money to police, immigration officers or airport security.", explanation: "Tipping public officials may be inappropriate and could be seriously misunderstood.", category: .confidenceAndCulturalAwareness),
        .init(id: 49, title: "Kindness matters alongside money.", explanation: "Patience, eye contact and a sincere thank-you are important parts of respectful service interactions.", category: .confidenceAndCulturalAwareness),
        .init(id: 50, title: "Make a reasonable choice and move on.", explanation: "Tipping customs are guidelines, not a perfect mathematical system. Check the bill, consider the service, respect your budget and avoid letting a few dollars create unnecessary stress.", category: .confidenceAndCulturalAwareness)
    ]
}
