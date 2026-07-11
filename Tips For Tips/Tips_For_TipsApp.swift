//
//  Tips_For_TipsApp.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 4/4/24.
//


import SwiftUI

@main
struct Tips_For_TipsApp: App {
    @State private var showLaunchScreen = true
    
    var body: some Scene {
        WindowGroup {
            if showLaunchScreen {
                LaunchScreen()
                    .onAppear {
                        // Show launch screen for 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.showLaunchScreen = false
                        }
                    }
            } else {
                MainMenu()
            }
        }
    }
}
