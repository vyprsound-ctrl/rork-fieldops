//
//  HarbourSouthFieldOpsApp.swift
//  HarbourSouthFieldOps
//

import SwiftUI

@main
struct HarbourSouthFieldOpsApp: App {
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
                // Two kinds of link reopen the app through the registered
                // scheme: Supabase confirmation and password-reset emails, and
                // the invitation hand-off from the join page. This fires for a
                // cold launch from the link as well as for a tap while running.
                .onOpenURL { url in
                    Task { await environmentModel.handleIncomingURL(url) }
                }
        }
    }
}
