import Foundation

struct DiscordUser: Equatable, Identifiable {
    var id: String
    var username: String
    var globalName: String?
    var discriminator: String
    var avatar: String?

    var displayName: String {
        if let globalName, !globalName.isEmpty {
            return globalName
        }
        if !username.isEmpty {
            return username
        }
        return "Discord user"
    }

    var avatarURL: URL {
        if let avatar, !avatar.isEmpty,
           let url = URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png") {
            return url
        }
        let index = defaultAvatarIndex
        return URL(string: "https://cdn.discordapp.com/embed/avatars/\(index).png")
            ?? URL(string: "https://cdn.discordapp.com/embed/avatars/0.png")!
    }

    private var defaultAvatarIndex: Int {
        if discriminator == "0" || discriminator.isEmpty {
            let snowflake = UInt64(id) ?? 0
            return Int((snowflake >> 22) % 6)
        }
        return (Int(discriminator) ?? 0) % 5
    }
}
