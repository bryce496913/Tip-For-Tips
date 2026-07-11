//
//  CustomSplitView.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 23/4/24.
//

// TODO: Save instance of the saved bill when sheet closes

import SwiftUI

struct CustomSplitView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var people: [Person] = []
    @State private var totalAmount: Double = 0.0 // Initial total
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.appBlack.edgesIgnoringSafeArea(.all)
                
                ScrollView { // Wrap the VStack with ScrollView
                    VStack {
                        ForEach(people.indices, id: \.self) { index in
                            PersonRow(person: $people[index], totalAmount: self.$totalAmount)
                        }
                        
                        Button(action: {
                            self.addPerson()
                        }) {
                            Label("Name", systemImage: "plus")
                                .padding()
                                .background(Color.appDarkBlue)
                                .foregroundColor(.white)
                                .cornerRadius(30)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        
                        Text("Bill Total: \(totalAmount, specifier: "%.2f")") // Display total dynamically
                            .padding()
                            .font(.title)
                            .foregroundColor(Color.appGold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Spacer()
                    }
                    .foregroundColor(.white)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // Recalculate total when the app is about to enter background
                    self.totalAmount = self.calculateTotalAmount()
                }
                .navigationBarTitle("Custom Split", displayMode: .inline)
                .navigationBarItems(trailing:
                                        Button("Close") {
                    // Close the sheet
                    self.presentationMode.wrappedValue.dismiss()
                }
                )
            }
        }
    }
    
    private func addPerson() {
        people.append(Person(name: "", items: []))
    }
    
    private func calculateTotalAmount() -> Double {
        return people.reduce(0.0) { $0 + calculateTotal(for: $1) }
    }
    
    private func calculateTotal(for person: Person) -> Double {
        return person.items.reduce(0.0) { $0 + $1.price }
    }
}

struct CustomSplitView_Previews: PreviewProvider {
    static var previews: some View {
        CustomSplitView()
    }
}

struct Person: Identifiable {
    var id = UUID()
    var name: String
    var items: [Item]
}

struct Item {
    var name: String
    var price: Double
}

struct ItemRow: View {
    @Binding var item: Item
    
    var body: some View {
        HStack {
            TextField("Name of Item", text: $item.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.appBlue, lineWidth: 5)
                )
                .padding()
                .font(.body)
            
            TextField("Price", value: $item.price, formatter: NumberFormatter())
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.appGold, lineWidth: 5)
                )
                .padding()
                .font(.body)
        }
    }
}

struct PersonRow: View {
    @Binding var person: Person
    @Binding var totalAmount: Double // Binding to update total dynamically
    
    var body: some View {
        VStack {
            TextField("Name", text: $person.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.appGreen, lineWidth: 5)
                )
                .padding()
                .font(.headline)
            
            ForEach(person.items.indices, id: \.self) { index in
                ItemRow(item: self.$person.items[index])
            }
            
            Text("Person Total: $\(calculateTotal(), specifier: "%.2f")")
                .padding()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            Button(action: {
                self.addNewItem()
            }) {
                Text("Add Item")
            }
            .padding()
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func calculateTotal() -> Double {
        // Update totalAmount whenever the price changes
        totalAmount = person.items.reduce(0.0) { $0 + $1.price }
        return totalAmount
    }
    
    private func addNewItem() {
        person.items.append(Item(name: "", price: 0.0))
    }
}

