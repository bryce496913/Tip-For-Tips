//
//  TipCalculator.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

// TODO: Fix the font size and placement in the UI

import SwiftUI

struct TipCalculator: View {
    @State private var selectedServiceIndex = 0
    @State private var totalBill = ""
    @State private var tipAmount = ""
    @State private var isPercentageSelected = true
    @State private var isServicePickerPresented = false

    // Array of service types
    let services = [
        "Restaurant with table service",
        "Bars",
        "Yellow Taxi",
        "Uber/Lyft driver",
        "Food delivery",
        "Shuttle driver",
        "Doorman",
        "Porter",
        "Housekeeping",
        "Room Service",
        "Tour Guides",
        "Tour Bus Drivers",
        "Spa",
        "Hairdressers/Barbers",
        "Nail Salon"
    ]

    // Dictionary to store recommended tip amounts
    let recommendedTips: [String: String] = [
        "Restaurant with table service": "15-20%",
        "Bars": "15-20% or $1-$2 per drink",
        "Yellow Taxi": "10-20%",
        "Uber/Lyft driver": "10-20%",
        "Food delivery": "15-20%",
        "Shuttle driver": "$2-$5 per person",
        "Doorman": "$1-$5",
        "Porter": "$1-$2 per bag",
        "Housekeeping": "$2-$5 per night",
        "Room Service": "15-20%",
        "Tour Guides": "$2-$5 per participating person for local tours. 15-20% of the ticket price for a day trip",
        "Tour Bus Drivers": "$2-$5 per person",
        "Spa": "15-20%",
        "Hairdressers/Barbers": "15-20%",
        "Nail Salon": "15-20%"
    ]

    var selectedService: String {
        services[selectedServiceIndex]
    }

    var recommendedTip: String {
        recommendedTips[selectedService] ?? ""
    }

    var tipAmountSummary: String {
        let tipPercentage = Double(tipAmount) ?? 0
        let billAmount = Double(totalBill) ?? 0

        if isPercentageSelected {
            let calculatedTip = (billAmount * tipPercentage) / 100
            return String(format: "$%.2f", calculatedTip)
        } else {
            return "$" + tipAmount
        }
    }

    var totalAmount: String {
        let billAmount = Double(totalBill) ?? 0
        let tip = Double(tipAmountSummary.dropFirst()) ?? 0
        let total = billAmount + tip
        return String(format: "$%.2f", total)
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                VStack {
                    Image("TipCalculator")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                    
                    HStack(spacing: 0) {
                        Text("Tip ").foregroundColor(Color.appBlue)
                        Text("Calculator").foregroundColor(Color.appGold)
                    }
                    .font(.largeTitle)
                }
                Button(action: {
                    isServicePickerPresented.toggle()
                }) {
                    Text("Select Service: \(services[selectedServiceIndex])")
                        .foregroundColor(.white)
                        .font(.title)
                }
                .padding()

                Text("Recommended Tip: \(recommendedTip)")
                    .foregroundColor(.white)
                    .padding()
                    .font(.body)

                TextField("Bill Amount", text: $totalBill)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appBlue, lineWidth: 5)
                    )
                    .padding(.horizontal, 50)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .toolbar {
                        ToolbarItem(placement: .keyboard) {
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                    .padding()

                HStack {
                    RadioButton(title: "%", isSelected: isPercentageSelected) {
                        isPercentageSelected = true
                    }
                    RadioButton(title: "$", isSelected: !isPercentageSelected) {
                        isPercentageSelected = false
                    }
                }
                .padding()

                TextField(isPercentageSelected ? "Tip (%)" : "Tip ($)", text: $tipAmount)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appGreen, lineWidth: 5)
                    )
                    .padding(.horizontal, 50)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding()

                Text("Tip Amount: \(tipAmountSummary)")
                    .foregroundColor(.white)
                    .padding()
                    .font(.title)

                Text("Bill Total: \(totalAmount)")
                    .foregroundColor(.white)
                    .padding()
                    .font(.title)

                Spacer()
            }
        }
        .sheet(isPresented: $isServicePickerPresented) {
            ServicePicker(selectedServiceIndex: $selectedServiceIndex, isPresented: $isServicePickerPresented, services: services)
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                    .font(.title)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.white)
                }
            }
        }
    }
}

struct ServicePicker: View {
    @Binding var selectedServiceIndex: Int
    @Binding var isPresented: Bool // Added binding to control sheet presentation
    let services: [String]

    var body: some View {
        VStack {
            Picker(selection: $selectedServiceIndex, label: Text("Service")) {
                ForEach(0..<services.count, id: \.self) { index in
                    Text(self.services[index])
                }
            }
            .pickerStyle(WheelPickerStyle())
            .labelsHidden()

            Button("Done") {
                isPresented = false // Dismiss the sheet
            }
            .padding()
        }
        .frame(height: UIScreen.main.bounds.height / 2)
        .padding()
    }
}

struct TipCalculator_Previews: PreviewProvider {
    static var previews: some View {
        TipCalculator()
    }
}
