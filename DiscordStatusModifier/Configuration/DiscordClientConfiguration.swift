import Foundation

/// Discord Rich Presence always uses a registered application `client_id` over IPC.
/// This app ships with one built in so you only need the Discord desktop client running.
enum DiscordClientConfiguration {
    /// Same application ID as the homework-discord-rpc / discord-rpc IPC example (local client login).
    static let applicationID = "1555027753546420285"
}
