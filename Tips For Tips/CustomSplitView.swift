import SwiftUI

struct CustomSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var people: [Person] = []

    private var totalAmount: Double { people.reduce(0) { $0 + $1.items.reduce(0) { $0 + max($1.price, 0) } } }

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView {
                    VStack(spacing: 16) {
                        ScreenTitle(text: "Custom Split")
                        if people.isEmpty {
                            ThemedCard { Text("Add a person to start a custom split.").appFont(.paragraph) }
                        }
                        ForEach($people) { $person in
                            PersonRow(person: $person)
                        }
                        PrimaryButton(title: "Add Person", systemImage: "plus") { addPerson() }
                        ThemedCard {
                            Text("Bill Total: \(totalAmount, format: .currency(code: "USD"))")
                                .appFont(.h2)
                                .foregroundStyle(AppTheme.highlight)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Custom Split")
            .toolbar { Button("Close") { dismiss() } }
        }
        .hideKeyboardToolbar()
    }

    private func addPerson() { people.append(Person(name: "", items: [])) }
}

struct Person: Identifiable {
    var id = UUID()
    var name: String
    var items: [Item]
}

struct Item: Identifiable {
    var id = UUID()
    var name: String
    var price: Double
}

struct ItemRow: View {
    @Binding var item: Item

    var body: some View {
        HStack(spacing: 10) {
            TextField("Item", text: $item.name)
                .textFieldStyle(AppTextFieldStyle())
            TextField("Price", value: $item.price, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(AppTextFieldStyle())
        }
    }
}

struct PersonRow: View {
    @Binding var person: Person
    private var personTotal: Double { person.items.reduce(0) { $0 + max($1.price, 0) } }

    var body: some View {
        ThemedCard {
            TextField("Name", text: $person.name)
                .textFieldStyle(AppTextFieldStyle())
            ForEach($person.items) { $item in ItemRow(item: $item) }
            Text("Person Total: \(personTotal, format: .currency(code: "USD"))")
                .appFont(.paragraph)
                .foregroundStyle(AppTheme.highlight)
            SecondaryButton(title: "Add Item", systemImage: "plus") { person.items.append(Item(name: "", price: 0)) }
        }
    }
}

#Preview { CustomSplitView() }
