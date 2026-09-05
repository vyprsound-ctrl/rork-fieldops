//
//  TradeDeskHVACApp.swift
//  TradeDeskHVAC
//

import SwiftUI

@main
struct TradeDeskHVACApp: App {
    /// Receives the two APNs callbacks that have no SwiftUI equivalent: the
    /// device token, and a tapped notification. Adopting a delegate does not
    /// register for anything or prompt for anything on its own — registration
    /// only happens when an authenticated user asks for it.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    @State private var environmentModel = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environmentModel)
                .preferredColorScheme(.light)
        }
    }
}
