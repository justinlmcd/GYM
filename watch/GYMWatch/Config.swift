import Foundation

// The same two public settings the GYM web app uses (Supabase → Connect).
// The publishable key is safe to ship in an app; never put a secret or service-role key here.
nonisolated enum Config {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let publishableKey = "sb_publishable_YOUR_KEY"
}
