//
//  SplitBillCalculator.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

import SwiftUI

struct SplitBillCalculator: View {
    @State private var showEvenSplitSheet = false
    @State private var showCustomSplitSheet = false
    
    var body: some View {
        ZStack {
            Color.appBlack.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image("SplitBillCalculator")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 250)
                
                HStack(spacing: 0) {
                    Text("Split").foregroundColor(Color.appBlue)
                    Text(" Calculator ").foregroundColor(Color.appGold)
                    Text("Calculator").foregroundColor(Color.appGreen)
                }
                .font(.largeTitle)
                
                Spacer()
                
                Button(action: {
                    self.showEvenSplitSheet = true
                }) {
                    Text("Even Split")
                        .foregroundColor(Color.appBlue)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                .sheet(isPresented: $showEvenSplitSheet) {
                    EvenSplitView()
                }
                
                Button(action: {
                    self.showCustomSplitSheet = true
                }) {
                    Text("Custom Split")
                        .foregroundColor(Color.appGreen)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                .sheet(isPresented: $showCustomSplitSheet) {
                    CustomSplitView()
                }
                
                Spacer()
            }
        }
    }
}

struct SplitBillCalculator_Previews: PreviewProvider {
    static var previews: some View {
        SplitBillCalculator()
    }
}
