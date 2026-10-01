import SwiftUI

enum DiscordTheme {
    static let background = Color(hex: 0x111214)
    static let elevated = Color(hex: 0x1E1F22)
    static let card = Color(hex: 0x2B2D31)
    static let button = Color(hex: 0x4E5058)
    static let field = Color.white.opacity(0.04)
    static let secondary = Color(hex: 0xB5BAC1)
    static let muted = Color(hex: 0x949BA4)
    static let timer = Color(hex: 0x23A559)
    static let accent = Color(hex: 0x5865F2)
    static let danger = Color(hex: 0xDA373C)
    static let dangerFill = Color(hex: 0x3A1719)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

enum ClockFormat {
    /// Discord-style elapsed time, such as `1:26:34`.
    static func string(from interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

enum ProfileLimits {
    static let title = 128
    static let line = 128
    static let hover = 128
    static let buttonLabel = 32
    static let url = 512
}
