import SwiftUI

struct HelpfulTips: View {
    @State private var selectedServiceIndex = 0
    @State private var showPicker = false
    @State private var expandedFAQIDs: Set<Int> = []
    @State private var selectedTipCategory: TippingTipCategory? = nil
    @State private var searchText = ""

    private let services = ["Restaurant with table service", "Bars", "Yellow Taxi", "Uber/Lyft driver", "Food delivery", "Shuttle driver", "Doorman", "Porter", "Housekeeping", "Room Service", "Tour Guides", "Tour Bus Drivers", "Spa", "Hairdressers/Barbers", "Nail Salon"]
    private let recommendedTips: [String: String] = ["Restaurant with table service": "15-20%", "Bars": "15-20% or $1-$2 per drink", "Yellow Taxi": "10-20%", "Uber/Lyft driver": "10-20%", "Food delivery": "15-20%", "Shuttle driver": "$2-$5 per person", "Doorman": "$1-$5", "Porter": "$1-$2 per bag", "Housekeeping": "$2-$5 per night", "Room Service": "15-20%", "Tour Guides": "$2-$5 per participating person for local tours. 15-20% of the ticket price for a day trip", "Tour Bus Drivers": "$2-$5 per person", "Spa": "15-20%", "Hairdressers/Barbers": "15-20%", "Nail Salon": "15-20%"]

    private var selectedService: String { services.indices.contains(selectedServiceIndex) ? services[selectedServiceIndex] : services[0] }
    private var searchQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !searchQuery.isEmpty }
    private var filteredFAQs: [TippingFAQ] {
        guard isSearching else { return HelpfulTipsContent.faqs }
        return HelpfulTipsContent.faqs.filter { $0.question.localizedCaseInsensitiveContains(searchQuery) || $0.answer.localizedCaseInsensitiveContains(searchQuery) || $0.bulletPoints.contains { $0.localizedCaseInsensitiveContains(searchQuery) } }
    }
    private var filteredTips: [TippingTip] {
        HelpfulTipsContent.tips.filter { tip in
            let matchesCategory = selectedTipCategory == nil || tip.category == selectedTipCategory
            let matchesSearch = !isSearching || tip.title.localizedCaseInsensitiveContains(searchQuery) || tip.explanation.localizedCaseInsensitiveContains(searchQuery) || tip.category.rawValue.localizedCaseInsensitiveContains(searchQuery)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        AppScreen {
            ScrollView {
                LazyVStack(spacing: AppSpacing.section) {
                    ScreenTitle(text: "Helpful Tips", subtitle: "Review common tipping guidance by service type.")
                    introductionSection
                    recommendationSection
                    searchSection
                    quickGuideSection
                    faqSection
                    travelerTipsSection
                    finalReminderSection
                    Text(HelpfulTipsContent.footerNote)
                        .appFont(.paragraph)
                        .foregroundStyle(AppTheme.text.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.screen)
            }
        }
        .navigationTitle("Helpful Tips")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { ServicePicker(selectedServiceIndex: $selectedServiceIndex, services: services) }
    }

    private var introductionSection: some View {
        ThemedCard {
            Text(HelpfulTipsContent.introductionTitle).appFont(.h2).accessibilityAddTraits(.isHeader)
            ForEach(HelpfulTipsContent.introductionParagraphs, id: \.self) { paragraph in
                Text(paragraph).appFont(.paragraph).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recommendationSection: some View {
        ThemedCard {
            Text("Find a Recommended Tip").appFont(.h2).accessibilityAddTraits(.isHeader)
            Text("Selected service").appFont(.h3).foregroundStyle(AppTheme.text.opacity(0.8))
            SecondaryButton(title: selectedService, systemImage: "list.bullet") { showPicker = true }
                .accessibilityLabel("Select service")
                .accessibilityValue(selectedService)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Recommendation").appFont(.h3)
                Text(recommendedTips[selectedService] ?? "No recommendation available.")
                    .appFont(.h1)
                    .foregroundStyle(AppTheme.highlight)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tip amounts can vary by location, service quality, and included fees. Check your bill before adding gratuity.")
                    .appFont(.paragraph)
                    .foregroundStyle(AppTheme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.standard)
            .background(AppTheme.background.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var searchSection: some View {
        ThemedCard {
            Text("Search FAQs and Tips").appFont(.h2).accessibilityAddTraits(.isHeader)
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                TextField("Search questions, answers, and tips", text: $searchText)
                    .appFont(.paragraph)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Search FAQs and tips")
                if isSearching {
                    Button("Clear") { searchText = "" }
                        .appFont(.h3)
                        .foregroundStyle(AppTheme.highlight)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(AppTheme.background.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.accent.opacity(0.7), lineWidth: 1))
        }
    }

    private var quickGuideSection: some View {
        SectionContainer(title: "Quick Tipping Guide") {
            ForEach(HelpfulTipsContent.quickGuide) { entry in QuickGuideRow(entry: entry) }
            Text(HelpfulTipsContent.quickGuideFooter).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var faqSection: some View {
        SectionContainer(title: "Frequently Asked Questions") {
            if filteredFAQs.isEmpty { EmptySearchCard(kind: "FAQ", clearAction: { searchText = "" }) }
            ForEach(filteredFAQs) { faq in
                FAQRow(faq: faq, isExpanded: expandedFAQIDs.contains(faq.id)) {
                    if expandedFAQIDs.contains(faq.id) { expandedFAQIDs.remove(faq.id) } else { expandedFAQIDs.insert(faq.id) }
                }
            }
        }
    }

    private var travelerTipsSection: some View {
        SectionContainer(title: "50 Helpful Tipping Tips for Travelers") {
            TipCategoryChips(selectedCategory: $selectedTipCategory)
            if filteredTips.isEmpty { EmptySearchCard(kind: "traveler tip", clearAction: { searchText = ""; selectedTipCategory = nil }) }
            ForEach(filteredTips) { tip in TipCard(tip: tip) }
        }
    }

    private var finalReminderSection: some View {
        ThemedCard {
            Label("Final Reminder", systemImage: "heart.circle.fill").appFont(.h2).foregroundStyle(AppTheme.highlight).accessibilityAddTraits(.isHeader)
            ForEach(HelpfulTipsContent.finalReminderParagraphs, id: \.self) { paragraph in
                Text(paragraph).appFont(.paragraph).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SectionContainer<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(title).appFont(.h2).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickGuideRow: View {
    let entry: QuickTippingGuideEntry
    var body: some View {
        ThemedCard {
            HStack(alignment: .top, spacing: AppSpacing.standard) {
                Image(systemName: entry.symbolName).font(.headline).foregroundStyle(AppTheme.accent).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(entry.service).appFont(.h3)
                    Text(entry.recommendation).appFont(.h2).foregroundStyle(AppTheme.highlight)
                    Text(entry.explanation).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FAQRow: View {
    let faq: TippingFAQ
    let isExpanded: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                HStack(alignment: .top) {
                    Text("\(faq.id). \(faq.question)").appFont(.h3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AppSpacing.small)
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle").foregroundStyle(isExpanded ? AppTheme.accent : AppTheme.text.opacity(0.8)).accessibilityHidden(true)
                }
                if isExpanded {
                    FAQAnswer(faq: faq)
                }
            }
            .padding(AppSpacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppSpacing.corner, style: .continuous).stroke(isExpanded ? AppTheme.accent : AppTheme.accent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") the answer")
    }
}

private struct FAQAnswer: View {
    let faq: TippingFAQ
    private var paragraphs: [String] { faq.answer.components(separatedBy: "\n\n") }
    var body: some View {
        if faq.bulletPoints.isEmpty {
            AnswerParagraphs(paragraphs)
        } else if paragraphs.count > 1 {
            AnswerParagraphs(Array(paragraphs.dropLast()))
            BulletList(items: faq.bulletPoints)
            AnswerParagraphs([paragraphs.last ?? ""])
        } else {
            AnswerParagraphs(paragraphs)
            BulletList(items: faq.bulletPoints)
        }
    }
}

private struct AnswerParagraphs: View {
    let paragraphs: [String]
    init(_ paragraphs: [String]) { self.paragraphs = paragraphs.filter { !$0.isEmpty } }
    var body: some View {
        ForEach(paragraphs, id: \.self) { paragraph in
            Text(paragraph).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.9)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BulletList: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: AppSpacing.small) {
                        Text("•").appFont(.paragraph).foregroundStyle(AppTheme.highlight)
                        Text(item).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct TipCategoryChips: View {
    @Binding var selectedCategory: TippingTipCategory?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                CategoryChip(title: "All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(TippingTipCategory.allCases) { category in
                    CategoryChip(title: category.rawValue, isSelected: selectedCategory == category) { selectedCategory = category }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Tip categories")
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .appFont(.h3)
                .padding(.horizontal, AppSpacing.section)
                .frame(minHeight: 44)
        }
        .foregroundStyle(AppTheme.text)
        .background(isSelected ? AppTheme.accent : AppTheme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.accent.opacity(isSelected ? 1 : 0.45), lineWidth: 1))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct TipCard: View {
    let tip: TippingTip
    var body: some View {
        ThemedCard {
            Text(tip.category.rawValue).appFont(.paragraph).foregroundStyle(AppTheme.accent)
            Text("Tip \(tip.id): \(tip.title)").appFont(.h3).fixedSize(horizontal: false, vertical: true)
            Text(tip.explanation).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.86)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip \(tip.id), \(tip.title), category \(tip.category.rawValue). \(tip.explanation)")
    }
}

private struct EmptySearchCard: View {
    let kind: String
    let clearAction: () -> Void
    var body: some View {
        ThemedCard {
            Text("No matching \(kind)s found.").appFont(.h3)
            Text("Try another search term or clear the search and category filters.").appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.8))
            SecondaryButton(title: "Clear Filters", systemImage: "xmark.circle", action: clearAction)
        }
    }
}

#Preview { HelpfulTips() }
