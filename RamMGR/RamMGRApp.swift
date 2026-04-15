//
//  RamMGRApp.swift
//  RamMGR
//
//  Created by Kellam Adams on 4/14/26.
//

import AppKit
import SwiftUI

@main
struct RamMGRApp: App {
    init() {
        if let iconImage = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 309, height: 320)
        .windowResizability(.contentSize)
    }
}
