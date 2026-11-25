// Config.swift - Generated when this project was exported from Rork.
//
// Rork fills in only its public URLs and IDs for this project: the Rork Auth URL, project ID, and the
// toolkit and functions URLs. Every other value is empty, because Rork exports no credentials and
// none of your environment variables.
//
// Rork Auth and push need EXPO_PUBLIC_RORK_APP_KEY (from the project's Envs in Rork), and toolkit calls
// need EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY. This file is tracked in your repository: supply both keys
// at build time from a file git does not track, and never commit them.

import Foundation

enum Config {
    nonisolated static let EXPO_PUBLIC_RORK_FUNCTIONS_URL = "https://field-ops-backend.rork.app"
    nonisolated static let EXPO_PUBLIC_SUPABASE_ANON_KEY = ""
    nonisolated static let EXPO_PUBLIC_SUPABASE_URL = ""

    nonisolated static let allValues: [String: String] = [
        "EXPO_PUBLIC_RORK_FUNCTIONS_URL": EXPO_PUBLIC_RORK_FUNCTIONS_URL,
        "EXPO_PUBLIC_SUPABASE_ANON_KEY": EXPO_PUBLIC_SUPABASE_ANON_KEY,
        "EXPO_PUBLIC_SUPABASE_URL": EXPO_PUBLIC_SUPABASE_URL,
    ]
}
