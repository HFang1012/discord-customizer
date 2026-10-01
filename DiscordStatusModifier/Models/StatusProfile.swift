import Foundation

struct ProfileValidationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private func profileValidationFailure(_ message: String) -> Result<StatusProfile, ProfileValidationError> {
    .failure(ProfileValidationError(message))
}

enum ActivityType: Int, CaseIterable, Identifiable, Hashable {
    case playing = 0
    case listening = 2
    case watching = 3
    case competing = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .playing: return "Playing"
        case .listening: return "Listening"
        case .watching: return "Watching"
        case .competing: return "Competing"
        }
    }
}

extension ActivityType: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = ActivityType(rawValue: raw) ?? .playing
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StatusDisplayType: Int, Codable, CaseIterable, Identifiable, Hashable {
    case name = 0
    case state = 1
    case details = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .name: return "Title"
        case .state: return "State"
        case .details: return "Details"
        }
    }
}

enum TimerMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case off
    case countUpFromApply
    case countUpFromStart
    case countDownDuration
    case countDownUntil
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            return "Off"
        case .countUpFromApply:
            return "Count up from when applied"
        case .countUpFromStart:
            return "Count up from a chosen start"
        case .countDownDuration:
            return "Count down for a duration"
        case .countDownUntil:
            return "Count down to a time"
        case .custom:
            return "Custom timer"
        }
    }
}

struct ProfileButton: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var url: String

    var isBlank: Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StatusProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var activityType: ActivityType
    var details: String
    var state: String
    var detailsURL: String
    var stateURL: String
    var largeImageFilename: String?
    var largeImageRemoteURL: String
    var largeImageText: String
    var largeImageURL: String
    var smallImageFilename: String?
    var smallImageRemoteURL: String
    var smallImageText: String
    var smallImageURL: String
    var largeFingerprint: String?
    var largePublicURL: String?
    var largeAssetKey: String?
    var smallFingerprint: String?
    var smallPublicURL: String?
    var smallAssetKey: String?
    var buttons: [ProfileButton]
    var timerMode: TimerMode
    var timerStart: Date?
    var timerEnd: Date?
    var countdownHours: Int
    var countdownMinutes: Int
    var countdownSeconds: Int
    /// Remaining time typed on the card when `timerMode` is `.custom`. Optional so older saves still load.
    var customHours: Int?
    var customMinutes: Int?
    var customSeconds: Int?
    var partyCurrent: Int?
    var partyMax: Int?
    var partyID: String
    var statusDisplayType: StatusDisplayType
    var createdAt: Date
    var updatedAt: Date

    var titleSource: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var listTitle: String {
        let plain = DiscordFormatting.plain(titleSource)
        return plain.isEmpty ? "Untitled" : plain
    }

    var countdownDuration: TimeInterval {
        let hours = max(0, countdownHours)
        let minutes = max(0, countdownMinutes)
        let seconds = max(0, countdownSeconds)
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var customHoursValue: Int { min(999, max(0, customHours ?? 0)) }
    var customMinutesValue: Int { min(59, max(0, customMinutes ?? 0)) }
    var customSecondsValue: Int { min(59, max(0, customSeconds ?? 0)) }

    var customDuration: TimeInterval {
        TimeInterval(customHoursValue * 3600 + customMinutesValue * 60 + customSecondsValue)
    }

    var visibleButtons: [ProfileButton] {
        buttons.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func makeNew() -> StatusProfile {
        let now = Date()
        return StatusProfile(
            id: UUID(),
            title: "",
            activityType: .playing,
            details: "",
            state: "",
            detailsURL: "",
            stateURL: "",
            largeImageFilename: nil,
            largeImageRemoteURL: "",
            largeImageText: "",
            largeImageURL: "",
            smallImageFilename: nil,
            smallImageRemoteURL: "",
            smallImageText: "",
            smallImageURL: "",
            largeFingerprint: nil,
            largePublicURL: nil,
            largeAssetKey: nil,
            smallFingerprint: nil,
            smallPublicURL: nil,
            smallAssetKey: nil,
            buttons: [],
            timerMode: .off,
            timerStart: nil,
            timerEnd: nil,
            countdownHours: 0,
            countdownMinutes: 30,
            countdownSeconds: 0,
            customHours: 0,
            customMinutes: 0,
            customSeconds: 0,
            partyCurrent: nil,
            partyMax: nil,
            partyID: UUID().uuidString.lowercased(),
            statusDisplayType: .name,
            createdAt: now,
            updatedAt: now
        )
    }

    func preparedForSave(partyEnabled: Bool, partyCurrent: Int, partyMax: Int) -> Result<StatusProfile, ProfileValidationError> {
        var profile = self
        profile.title = profile.title.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.details = profile.details.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.state = profile.state.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.detailsURL = profile.detailsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.stateURL = profile.stateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.largeImageRemoteURL = profile.largeImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.largeImageText = profile.largeImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.largeImageURL = profile.largeImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.smallImageRemoteURL = profile.smallImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.smallImageText = profile.smallImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.smallImageURL = profile.smallImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.buttons = profile.buttons.compactMap { button in
            var copy = button
            copy.label = copy.label.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.url = copy.url.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy.isBlank ? nil : copy
        }

        if profile.title.isEmpty {
            return profileValidationFailure("Give the profile a title. That line is the bold name on the card, for example “homework”.")
        }
        if profile.title.count > ProfileLimits.title {
            return profileValidationFailure("The title can be at most \(ProfileLimits.title) characters.")
        }
        if profile.details.count > ProfileLimits.line || profile.state.count > ProfileLimits.line {
            return profileValidationFailure("Details and state can each be at most \(ProfileLimits.line) characters.")
        }
        if let message = LinkValidation.message(for: profile.detailsURL, allowingEmpty: true, httpsOnly: false, label: "Details link") {
            return profileValidationFailure(message)
        }
        if !profile.detailsURL.isEmpty && profile.details.isEmpty {
            return profileValidationFailure("Add details text before attaching a details link.")
        }
        if let message = LinkValidation.message(for: profile.stateURL, allowingEmpty: true, httpsOnly: false, label: "State link") {
            return profileValidationFailure(message)
        }
        if !profile.stateURL.isEmpty && profile.state.isEmpty {
            return profileValidationFailure("Add state text before attaching a state link.")
        }
        if let message = LinkValidation.message(for: profile.largeImageRemoteURL, allowingEmpty: true, httpsOnly: true, label: "Large image link") {
            return profileValidationFailure(message)
        }
        if let message = LinkValidation.message(for: profile.smallImageRemoteURL, allowingEmpty: true, httpsOnly: true, label: "Small image link") {
            return profileValidationFailure(message)
        }
        if let message = LinkValidation.message(for: profile.largeImageURL, allowingEmpty: true, httpsOnly: false, label: "Large image click link") {
            return profileValidationFailure(message)
        }
        if let message = LinkValidation.message(for: profile.smallImageURL, allowingEmpty: true, httpsOnly: false, label: "Small image click link") {
            return profileValidationFailure(message)
        }
        if profile.largeImageText.count > ProfileLimits.hover || profile.smallImageText.count > ProfileLimits.hover {
            return profileValidationFailure("Image hover text can be at most \(ProfileLimits.hover) characters.")
        }

        if profile.buttons.count > 2 {
            return profileValidationFailure("Discord accepts at most two buttons.")
        }
        for (index, button) in profile.buttons.enumerated() {
            let label = "Button \(index + 1)"
            if button.label.isEmpty || button.url.isEmpty {
                return profileValidationFailure("\(label) needs both a label and an http or https link.")
            }
            if button.label.count > ProfileLimits.buttonLabel {
                return profileValidationFailure("\(label)’s label can be at most \(ProfileLimits.buttonLabel) characters.")
            }
            if let message = LinkValidation.message(for: button.url, allowingEmpty: false, httpsOnly: false, label: label) {
                return profileValidationFailure(message)
            }
        }

        switch profile.timerMode {
        case .off, .countUpFromApply:
            break
        case .countUpFromStart:
            if profile.timerStart == nil {
                return profileValidationFailure("Choose the time the counter should start from.")
            }
        case .countDownDuration:
            if profile.countdownDuration < 1 {
                return profileValidationFailure("Set a countdown of at least one second.")
            }
        case .countDownUntil:
            if profile.timerEnd == nil {
                return profileValidationFailure("Choose the time the countdown should reach.")
            }
        case .custom:
            profile.customHours = profile.customHoursValue
            profile.customMinutes = profile.customMinutesValue
            profile.customSeconds = profile.customSecondsValue
        }

        if partyEnabled {
            if partyCurrent < 1 || partyMax < 1 {
                return profileValidationFailure("Party size needs a current and a max of at least 1.")
            }
            if partyCurrent > partyMax {
                return profileValidationFailure("Party size can’t be larger than the party max.")
            }
            profile.partyCurrent = partyCurrent
            profile.partyMax = partyMax
        } else {
            profile.partyCurrent = nil
            profile.partyMax = nil
        }

        if profile.partyID.isEmpty {
            profile.partyID = profile.id.uuidString.lowercased()
        }
        profile.updatedAt = Date()
        return .success(profile)
    }
}

enum TimerDisplay: Equatable {
    case hidden
    case countUp(from: Date)
    case countDown(to: Date)
    case fixed(TimeInterval)
}

enum LinkValidation {
    static func httpsURL(_ raw: String) -> URL? {
        normalized(raw, httpsOnly: true)
    }

    static func httpURL(_ raw: String) -> URL? {
        normalized(raw, httpsOnly: false)
    }

    static func message(for raw: String, allowingEmpty: Bool, httpsOnly: Bool, label: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return allowingEmpty ? nil : "\(label) needs an http or https link."
        }
        if trimmed.count > ProfileLimits.url {
            return "\(label) can be at most \(ProfileLimits.url) characters."
        }
        if normalized(trimmed, httpsOnly: httpsOnly) == nil {
            if httpsOnly {
                return "\(label) needs to start with https://."
            }
            return "\(label) needs to start with http:// or https://."
        }
        return nil
    }

    private static func normalized(_ raw: String, httpsOnly: Bool) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        if httpsOnly {
            guard scheme == "https" else { return nil }
        } else {
            guard scheme == "http" || scheme == "https" else { return nil }
        }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
