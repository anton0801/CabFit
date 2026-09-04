//
//  ContentView.swift
//  CabFit
//
//  Root flow controller: Splash → (first launch) Onboarding → Main App.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                LaunchView {
                    withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
                }
                .transition(.opacity)
            } else if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataStore())
            .environmentObject(AppSettings())
            .environmentObject(NotificationManager.shared)
    }
}
