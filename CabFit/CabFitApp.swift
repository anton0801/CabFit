//
//  CabFitApp.swift
//  CabFit
//
//  App entry point. Injects the app-wide stores and applies the persisted theme.
//

import SwiftUI

@main
struct CabFitApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var notifier = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(notifier)
                .accentColor(CF.blue)
                .preferredColorScheme(settings.theme.colorScheme)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background, .inactive:
                        // Writes are debounced while editing, so force one out before
                        // the app can be suspended or killed.
                        store.flush()
                    case .active:
                        notifier.refreshAuthorization()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
