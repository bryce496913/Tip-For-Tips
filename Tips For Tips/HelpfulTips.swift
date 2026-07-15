import SwiftUI

struct HelpfulTips: View {
    init(initialSectionID: String? = nil) { _searchText = State(initialValue: initialSectionID?.replacingOccurrences(of: "-", with: " ") ?? "") }
    @State private var expandedSectionIDs: Set<HelpfulTipsSection> = []
    @State private var expandedFAQIDs: Set<Int> = []
    @State private var selectedTipCategory: TippingTipCategory? = nil
    @State private var searchText = ""
    @AppStorage("guide.bookmarks") private var bookmarkStorage = ""
    @AppStorage("guide.recent") private var recentStorage = ""
    @State private var showBookmarkedOnly = false
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
    }

    private var introductionSection: some View {
        AccordionSection(title: HelpfulTipsContent.introductionTitle, isExpanded: binding(for: .introduction)) {
            ForEach(HelpfulTipsContent.introductionParagraphs, id: \.self) { paragraph in
                Text(paragraph).appFont(.paragraph).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchSection: some View {
        AccordionSection(title: "Search FAQs and Tips", isExpanded: binding(for: .search)) {
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
        AccordionSection(title: "Quick Tipping Guide", isExpanded: binding(for: .quickGuide)) {
            ForEach(HelpfulTipsContent.quickGuide) { entry in QuickGuideRow(entry: entry) }
            Text(HelpfulTipsContent.quickGuideFooter).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var faqSection: some View {
        AccordionSection(title: "Frequently Asked Questions", isExpanded: binding(for: .faq)) {
            if filteredFAQs.isEmpty { EmptySearchCard(kind: "FAQ", clearAction: { searchText = "" }) }
            ForEach(filteredFAQs.filter { !showBookmarkedOnly || bookmarks.contains("faq-\($0.id)") }) { faq in
                HStack { FAQRow(faq: faq, isExpanded: expandedFAQIDs.contains(faq.id)) {
                    if expandedFAQIDs.contains(faq.id) { expandedFAQIDs.remove(faq.id) } else { expandedFAQIDs.insert(faq.id); trackRecent(id: "faq-\(faq.id)", title: faq.question) }
                }
                BookmarkButton(isBookmarked: bookmarks.contains("faq-\(faq.id)")) { toggleBookmark("faq-\(faq.id)") }
                }
            }
        }
    }

    private var travelerTipsSection: some View {
        AccordionSection(title: "Helpful Tipping Tips for Travelers", isExpanded: binding(for: .travelerTips)) {
            HStack { TipCategoryChips(selectedCategory: $selectedTipCategory); Toggle("Bookmarked", isOn: $showBookmarkedOnly).labelsHidden().accessibilityLabel("Show bookmarked guide items only") }
            let visibleTips = filteredTips.filter { !showBookmarkedOnly || bookmarks.contains("tip-\($0.id)") }
            if visibleTips.isEmpty { EmptySearchCard(kind: "traveler tip", clearAction: { searchText = ""; selectedTipCategory = nil; showBookmarkedOnly = false }) }
            ForEach(visibleTips) { tip in HStack(alignment: .top) { Button { trackRecent(id: "tip-\(tip.id)", title: tip.title) } label: { TipCard(tip: tip) }.buttonStyle(.plain); BookmarkButton(isBookmarked: bookmarks.contains("tip-\(tip.id)")) { toggleBookmark("tip-\(tip.id)") } } }
        }
    }

    private var finalReminderSection: some View {
        ThemedCard {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "heart.circle.fill").accessibilityHidden(true)
                Text("Final Reminder").appFont(.h2).multilineTextAlignment(.leading)
                Spacer(minLength: AppSpacing.small)
            }
            .foregroundStyle(AppTheme.highlight)
            .accessibilityAddTraits(.isHeader)

            ForEach(HelpfulTipsContent.finalReminderParagraphs, id: \.self) { paragraph in
                Text(paragraph).appFont(.paragraph).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bookmarks: Set<String> { Set(bookmarkStorage.split(separator: ",").map(String.init)) }
    private func toggleBookmark(_ id: String) { var set = bookmarks; if set.contains(id) { set.remove(id) } else { set.insert(id) }; bookmarkStorage = set.sorted().joined(separator: ",") }
    private func trackRecent(id: String, title: String) { var parts = recentStorage.split(separator: "|").map(String.init).filter { !$0.hasPrefix(id + ":") }; parts.insert("\(id):\(title)", at: 0); recentStorage = parts.prefix(20).joined(separator: "|") }

    private func binding(for section: HelpfulTipsSection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section)
                } else {
                    expandedSectionIDs.remove(section)
                }
            }
        )
    }
}

private enum HelpfulTipsSection: CaseIterable, Hashable {
    case introduction
    case search
    case quickGuide
    case faq
    case travelerTips
}

private struct AccordionSection<Content: View>: View {
    let title: String
    let systemImage: String?
    @Binding var isExpanded: Bool
    let content: Content

    init(title: String, systemImage: String? = nil, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        ThemedCard {
            Button {
                withAnimation(.easeInOut) { isExpanded.toggle() }
            } label: {
                HStack(spacing: AppSpacing.small) {
                    if let systemImage {
                        Image(systemName: systemImage).accessibilityHidden(true)
                    }
                    Text(title).appFont(.h2).multilineTextAlignment(.leading)
                    Spacer(minLength: AppSpacing.small)
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AppTheme.highlight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") this section")

            if isExpanded {
                content
            }
        }
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


private struct BookmarkButton: View { let isBookmarked: Bool; let action: () -> Void; var body: some View { Button(action: action) { Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark").foregroundStyle(AppTheme.highlight).frame(width: 44, height: 44) }.accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark guide item").accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked") } }
