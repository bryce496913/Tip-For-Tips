import SwiftUI

struct CustomSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var people: [Person] = [Person(name: "", items: [Item(name: "", priceText: "")])]
    @State private var personPendingDelete: Person?

    private var totalAmount: Decimal { people.reduce(0) { $0 + $1.items.reduce(0) { $0 + ($1.parsedPrice ?? 0) } } }

    var body: some View {
        NavigationStack {
            AppScreen { ScrollView { VStack(spacing: 16) { ScreenTitle(text: "Custom Split"); ForEach($people) { $person in PersonRow(person: $person, onDeletePerson: { personPendingDelete = person }) }; PrimaryButton(title: "Add Person", systemImage: "plus") { addPerson() }; ThemedCard { Text("Bill Total: \(totalAmount as NSDecimalNumber, formatter: Self.currencyFormatter)").appFont(.h2).foregroundStyle(AppTheme.highlight) } }.padding(20) } }
            .navigationTitle("Custom Split").toolbar { Button("Close") { dismiss() } }
        }.hideKeyboardToolbar().alert("Delete Person?", isPresented: Binding(get: { personPendingDelete != nil }, set: { if !$0 { personPendingDelete = nil } })) { Button("Delete", role: .destructive) { if let p = personPendingDelete { deletePerson(p) }; personPendingDelete = nil }; Button("Cancel", role: .cancel) { personPendingDelete = nil } } message: { Text("Their item allocations will be removed from this split.") }
    }
    private func addPerson() { people.append(Person(name: "", items: [Item(name: "", priceText: "")])) }
    private func deletePerson(_ person: Person) { people.removeAll { $0.id == person.id }; if people.isEmpty { addPerson() } }
    static let currencyFormatter: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; return f }()
}

struct Person: Identifiable, Equatable { var id = UUID(); var name: String; var items: [Item] }
struct Item: Identifiable, Equatable { var id = UUID(); var name: String; var priceText: String; var parsedPrice: Decimal? { CustomSplitParser.decimal(priceText) }; var hasInvalidPrice: Bool { !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedPrice == nil } }

enum CustomSplitParser { static func decimal(_ text: String, locale: Locale = .current) -> Decimal? { let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines); if trimmed.isEmpty { return 0 }; guard !trimmed.contains("-") else { return nil }; let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.generatesDecimalNumbers = true; if let n = f.number(from: trimmed) as? NSDecimalNumber, n.decimalValue >= 0 { return n.decimalValue }; let fallback = trimmed.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: "."); guard let d = Decimal(string: fallback), d >= 0 else { return nil }; return d } }

struct ItemRow: View { @Binding var item: Item; var onDelete: () -> Void; var body: some View { VStack(alignment: .leading, spacing: 6) { HStack(spacing: 10) { TextField("Item", text: $item.name).textFieldStyle(AppTextFieldStyle()); TextField("Price", text: $item.priceText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).accessibilityLabel("Item price"); Button(role: .destructive, action: onDelete) { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete item \(item.name.isEmpty ? "unnamed" : item.name)") }; if item.hasInvalidPrice { Text("Enter zero or a positive price.").appFont(.paragraph).foregroundStyle(AppTheme.highlight).accessibilityLabel("Invalid price. Enter zero or a positive price.") } } } }

struct PersonRow: View { @Binding var person: Person; var onDeletePerson: () -> Void; private var personTotal: Decimal { person.items.reduce(0) { $0 + ($1.parsedPrice ?? 0) } }
    var body: some View { ThemedCard { HStack { TextField("Name", text: $person.name).textFieldStyle(AppTextFieldStyle()); Button(role: .destructive, action: onDeletePerson) { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete person \(person.name.isEmpty ? "unnamed" : person.name)") }; ForEach($person.items) { $item in ItemRow(item: $item) { person.items.removeAll { $0.id == item.id }; if person.items.isEmpty { person.items.append(Item(name: "", priceText: "")) } } }; Text("Person Total: \(personTotal as NSDecimalNumber, formatter: CustomSplitView.currencyFormatter)").appFont(.paragraph).foregroundStyle(AppTheme.highlight); SecondaryButton(title: "Add Item", systemImage: "plus") { person.items.append(Item(name: "", priceText: "")) } } }
}

#Preview { CustomSplitView() }
