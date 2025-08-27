//
//  AudiobookReaderApp.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 14/08/2025.
//

import SwiftUI

@main
struct AudiobookReaderApp: App {
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, persistenceController.context)
                .environment(\.theme, ThemeManager.shared)
        }
    }
}
