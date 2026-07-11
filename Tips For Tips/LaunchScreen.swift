//
//  LaunchScreen.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

import SwiftUI

struct LaunchScreen: View {
    var body: some View {
        ZStack {
            Color.appGold.edgesIgnoringSafeArea(.all)
            
            // Placeholder image in the center
            Image("MainLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300, height: 300)
                .foregroundColor(.white)
        }
    }
}

struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
    }
}
