//
//  Color.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

// Colors.swift

import SwiftUI

extension Color {
    static let appBlack = Color.black
    static let appWhite = Color.white
    static let appBlue = Color(hex: "#bddff9")
    static let appDarkBlue = Color(hex: "#1e72bf")
    static let appGold = Color(hex: "#ead1ab")
    static let appGreen = Color(hex: "#a2dbc5")
    
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.remove(at: hexString.startIndex)
        }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

