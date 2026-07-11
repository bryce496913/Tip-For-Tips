//
//  HelpfulTips.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

import SwiftUI

struct HelpfulTips: View {

    var body: some View {
        ZStack {
            Color.appBlack.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image("HelpfulTips")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 250)
                
                HStack(spacing: 0) {
                    Text("Helpful ").foregroundColor(Color.appBlue)
                    Text("Tips").foregroundColor(Color.appGold)
                }
                .font(.largeTitle)
                
                Spacer()
            }
        }
    }
}

struct HelpfulTips_Previews: PreviewProvider {
    static var previews: some View {
        HelpfulTips()
    }
}
