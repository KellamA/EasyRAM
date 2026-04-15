//
//  RamMGRApp.swift
//  RamMGR
//
//  Created by Kellam Adams on 4/14/26.
//

import SwiftUI
import CoreData

@main
struct RamMGRApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
