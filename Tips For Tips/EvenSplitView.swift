//
//  EvenSplitView.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 23/4/24.
//

//TODO: The math is wrong with the tip %

import SwiftUI

struct EvenSplitView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var totalBill = ""
    @State private var numberOfPeople = ""
    @State private var tipAmount = ""
    @State private var splitAmount = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                
                TextField("Total Bill", text: $totalBill)
                    .padding(2)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appBlue, lineWidth: 5)
                    )
                    .padding(.horizontal, 30)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .toolbar {
                        ToolbarItem(placement: .keyboard) {
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                
                    .padding(20)
                
                TextField("Number of People", text: $numberOfPeople)
                    .padding(2)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appBlue, lineWidth: 5)
                    )
                    .padding(.horizontal, 40)
                    .font(.title)
                    .multilineTextAlignment(.center)
                
                    .padding(10)
                
                TextField("Tip % Amount", text: $tipAmount)
                    .padding(2)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appBlue, lineWidth: 5)
                    )
                    .padding(.horizontal, 30)
                    .font(.title)
                    .multilineTextAlignment(.center)
                
                    .padding(20)
                
                
                Button(action: {
                    calculateSplit()
                }) {
                    Text("Split")
                        .padding()
                        .background(Color.appDarkBlue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                
                Text("Split Amount: $\(splitAmount)")
                    .padding()
                    .font(.title)
                    .foregroundColor(Color.appGold)
                
                Spacer()
            }
            .navigationBarTitle("Even Split", displayMode: .inline)
            .foregroundColor(Color.appWhite)
            .navigationBarItems(trailing:
                Button("Close") {
                    self.presentationMode.wrappedValue.dismiss()
                }
            )
            .background(Color.appBlack)
        }
    }
    
    private func calculateSplit() {
        guard let bill = Double(totalBill),
              let people = Double(numberOfPeople),
              let tip = Double(tipAmount) else {
            return
        }
        
        let totalAmount = bill + tip
        let individualAmount = totalAmount / people
        splitAmount = String(format: "%.2f", individualAmount)
    }
}

struct EvenSplitView_Previews: PreviewProvider {
    static var previews: some View {
        EvenSplitView()
    }
}
