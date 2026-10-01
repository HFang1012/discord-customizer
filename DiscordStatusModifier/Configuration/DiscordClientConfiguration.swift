import Foundation

/// Discord Rich Presence always uses a registered application `client_id` over IPC.
/// Discord keeps one activity per application, so each live card uses its own id.
enum DiscordClientConfiguration {
    /// The first id is this app. The rest are additional registered applications,
    /// one per extra card that can be live at the same time.
    static let applicationIDs = [
        "1555027753546420285",
        "1216403632283582496",
        "880218394199220334",
        "911790844204437504",
        "503557087041683458"
    ]

    static var applicationID: String { applicationIDs[0] }
}
