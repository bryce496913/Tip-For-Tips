//  MainMenu.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.

import SwiftUI

struct MainMenu: View {
    private var columns: [GridItem] = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.appBlack.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    
                    Image("MainLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        Text("Tips").foregroundColor(Color.appBlue)
                        Text(" for ").foregroundColor(Color.appGold)
                        Text("Tips").foregroundColor(Color.appGreen)
                    }
                    .font(.largeTitle)
                    
                    Spacer()
                    
                    // Grid for menu buttons
                    LazyVGrid(columns: columns, spacing: 20) {
                        NavigationLink(destination: TipCalculator()) {
                            VStack {
                                Image("TipCalculator")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Tip Calculator")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        NavigationLink(destination: SplitBillCalculator()) {
                            VStack {
                                Image("SplitBillCalculator")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Split Bill")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        NavigationLink(destination: CurrencyConverter()) {
                            VStack {
                                Image("CurrencyConverter")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Currency Converter")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        NavigationLink(destination: Receipts()) {
                            VStack {
                                Image("Receipts")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Receipts")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        NavigationLink(destination: NotePad()) {
                            VStack {
                                Image("NotePad")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Note Pad")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        NavigationLink(destination: HelpfulTips()) {
                            VStack {
                                Image("HelpfulTips")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                                Text("Helpful Tips")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
                .foregroundColor(.white)
            }
            .navigationBarTitle("") // Hide navigation bar title
            .navigationBarHidden(true) // Hide navigation bar
        }
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenu()
    }
}
