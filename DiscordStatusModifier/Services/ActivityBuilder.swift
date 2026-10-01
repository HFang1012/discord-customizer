import Foundation

/// Builds the `activity` object Discord expects inside SET_ACTIVITY.
enum ActivityBuilder {
    static func makeActivity(
        profile: StatusProfile,
        largeImage: String?,
        smallImage: String?,
        countUpStart: Date?,
        countDownEnd: Date?
    ) -> [String: Any] {
        let name = formattedField(profile.titleSource, limit: ProfileLimits.title, fallback: "Untitled")
        var activity: [String: Any] = [
            "type": profile.activityType.rawValue,
            "name": name,
            "status_display_type": profile.statusDisplayType.rawValue,
            "instance": true
        ]

        let details = formattedField(profile.details, limit: ProfileLimits.line, fallback: "")
        if !details.isEmpty {
            activity["details"] = details
            if let url = LinkValidation.httpURL(profile.detailsURL) {
                activity["details_url"] = url.absoluteString
            }
        }

        let state = formattedField(profile.state, limit: ProfileLimits.line, fallback: "")
        if !state.isEmpty {
            activity["state"] = state
            if let url = LinkValidation.httpURL(profile.stateURL) {
                activity["state_url"] = url.absoluteString
            }
        }

        if let timestamps = timestamps(profile: profile, countUpStart: countUpStart, countDownEnd: countDownEnd) {
            activity["timestamps"] = timestamps
        }

        if let assets = assets(profile: profile, largeImage: largeImage, smallImage: smallImage) {
            activity["assets"] = assets
        }

        let buttons: [[String: String]] = profile.buttons.prefix(2).compactMap { button in
            let label = button.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let formatted = DiscordFormatting.discordText(label, limit: ProfileLimits.buttonLabel)
            guard !label.isEmpty, label.count <= ProfileLimits.buttonLabel, !formatted.isEmpty,
                  let url = LinkValidation.httpURL(button.url),
                  url.absoluteString.count <= ProfileLimits.url else {
                return nil
            }
            return ["label": formatted, "url": url.absoluteString]
        }
        if !buttons.isEmpty {
            activity["buttons"] = buttons
        }

        if let current = profile.partyCurrent, let max = profile.partyMax, current >= 1, max >= current {
            let partyID = profile.partyID.isEmpty ? profile.id.uuidString.lowercased() : profile.partyID
            activity["party"] = [
                "id": partyID,
                "size": [current, max]
            ]
        }

        return activity
    }

    private static func timestamps(
        profile: StatusProfile,
        countUpStart: Date?,
        countDownEnd: Date?
    ) -> [String: Int]? {
        switch profile.timerMode {
        case .off:
            // Omitting timestamps makes Discord count up from when the activity was set.
            // An empty timestamps object is stored and still drawn, and JSON null is rejected.
            // An end time already in the past is a finished countdown, which the client does not render.
            return ["end": unixSeconds(Date().addingTimeInterval(-86_400))]
        case .countUpFromApply:
            guard let countUpStart else { return nil }
            return ["start": unixSeconds(countUpStart)]
        case .countUpFromStart:
            guard let start = profile.timerStart else { return nil }
            return ["start": unixSeconds(start)]
        case .countDownDuration:
            guard let countDownEnd else { return nil }
            return ["end": unixSeconds(countDownEnd)]
        case .countDownUntil:
            guard let end = profile.timerEnd else { return nil }
            return ["end": unixSeconds(end)]
        case .custom:
            guard let countDownEnd else { return nil }
            return ["end": unixSeconds(countDownEnd)]
        }
    }

    private static func assets(
        profile: StatusProfile,
        largeImage: String?,
        smallImage: String?
    ) -> [String: String]? {
        var assets: [String: String] = [:]
        if let largeImage, !largeImage.isEmpty {
            assets["large_image"] = largeImage
            let hover = formattedField(profile.largeImageText, limit: ProfileLimits.hover, fallback: "")
            if !hover.isEmpty {
                assets["large_text"] = hover
            }
            if let url = LinkValidation.httpURL(profile.largeImageURL) {
                assets["large_url"] = url.absoluteString
            }
        }
        if let smallImage, !smallImage.isEmpty {
            assets["small_image"] = smallImage
            let hover = formattedField(profile.smallImageText, limit: ProfileLimits.hover, fallback: "")
            if !hover.isEmpty {
                assets["small_text"] = hover
            }
            if let url = LinkValidation.httpURL(profile.smallImageURL) {
                assets["small_url"] = url.absoluteString
            }
        }
        return assets.isEmpty ? nil : assets
    }

    private static func formattedField(_ source: String, limit: Int, fallback: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let formatted = DiscordFormatting.discordText(trimmed, limit: limit)
        return formatted.isEmpty ? fallback : formatted
    }

    private static func unixSeconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }
}

/// Compares a SET_ACTIVITY payload with the activity Discord sends back.
enum ActivityConfirmation {
    static func problem(
        sent: [String: Any],
        confirmed: [String: Any],
        ignoreMissingLargeImage: Bool = false
    ) -> String? {
        var missed: [String] = []
        if !sameText(sent["name"], confirmed["name"]) {
            missed.append("title")
        }
        if !sameInt(sent["type"], confirmed["type"]) {
            missed.append("type")
        }
        if !sameInt(sent["status_display_type"], confirmed["status_display_type"]) {
            missed.append("text beside your name")
        }
        if !sameOptionalText(sent["details"], confirmed["details"]) {
            missed.append("details")
        }
        if !sameOptionalText(sent["state"], confirmed["state"]) {
            missed.append("state")
        }
        if !sameOptionalText(sent["details_url"], confirmed["details_url"]) {
            missed.append("details link")
        }
        if !sameOptionalText(sent["state_url"], confirmed["state_url"]) {
            missed.append("state link")
        }

        let sentAssets = sent["assets"] as? [String: Any]
        let confirmedAssets = confirmed["assets"] as? [String: Any]
        if !sameOptionalText(sentAssets?["large_text"], confirmedAssets?["large_text"]) {
            missed.append("large image text")
        }
        if !sameOptionalText(sentAssets?["small_text"], confirmedAssets?["small_text"]) {
            missed.append("small image text")
        }
        if !sameOptionalText(sentAssets?["large_url"], confirmedAssets?["large_url"]) {
            missed.append("large image link")
        }
        if !sameOptionalText(sentAssets?["small_url"], confirmedAssets?["small_url"]) {
            missed.append("small image link")
        }
        if !sameImagePresence(sentAssets?["large_image"], confirmedAssets?["large_image"]) {
            let blankWasDropped = ignoreMissingLargeImage
                && text(sentAssets?["large_image"]) != nil
                && text(confirmedAssets?["large_image"]) == nil
            if !blankWasDropped {
                missed.append("large image")
            }
        }
        if !sameImagePresence(sentAssets?["small_image"], confirmedAssets?["small_image"]) {
            missed.append("small image")
        }
        if !sameButtons(sent: sent["buttons"], confirmed: confirmed) {
            missed.append("buttons")
        }
        if !sameParty(sent: sent["party"], confirmed: confirmed["party"]) {
            missed.append("party size")
        }
        if !sameTimestamps(sent: sent["timestamps"], confirmed: confirmed["timestamps"]) {
            missed.append("timer")
        }

        guard !missed.isEmpty else { return nil }
        if missed == ["timer"] {
            return "Discord kept a timer on this activity. Choose a timer, or click the profile again."
        }
        return "Discord didn’t keep the \(missed.joined(separator: ", ")) from this activity."
    }

    private static func sameText(_ sent: Any?, _ confirmed: Any?) -> Bool {
        text(sent) == text(confirmed)
    }

    private static func sameOptionalText(_ sent: Any?, _ confirmed: Any?) -> Bool {
        text(sent) == text(confirmed)
    }

    private static func sameInt(_ sent: Any?, _ confirmed: Any?) -> Bool {
        integer(sent) == integer(confirmed)
    }

    /// Discord rewrites image keys to `mp:external/...`, so presence is the check that matters.
    private static func sameImagePresence(_ sent: Any?, _ confirmed: Any?) -> Bool {
        let left = text(sent)
        let right = text(confirmed)
        if left == nil { return right == nil }
        return right != nil
    }

    private static func sameButtons(sent: Any?, confirmed: [String: Any]) -> Bool {
        let sentButtons = (sent as? [[String: Any]]) ?? []
        let labels = stringList(confirmed["buttons"])
        let urls = stringList((confirmed["metadata"] as? [String: Any])?["button_urls"])
        if sentButtons.isEmpty {
            return labels.isEmpty
        }
        guard labels.count == sentButtons.count, urls.count == sentButtons.count else { return false }
        for (index, button) in sentButtons.enumerated() {
            if text(button["label"]) != labels[index] || text(button["url"]) != urls[index] {
                return false
            }
        }
        return true
    }

    private static func sameParty(sent: Any?, confirmed: Any?) -> Bool {
        let sentSize = integerList((sent as? [String: Any])?["size"])
        let confirmedSize = integerList((confirmed as? [String: Any])?["size"])
        if sentSize == nil { return confirmedSize == nil }
        return sentSize == confirmedSize
    }

    private static func sameTimestamps(sent: Any?, confirmed: Any?) -> Bool {
        let sentMap = sent as? [String: Any]
        let confirmedMap = confirmed as? [String: Any]
        let sentStart = integer(sentMap?["start"])
        let sentEnd = integer(sentMap?["end"])
        let confirmedStart = integer(confirmedMap?["start"])
        let confirmedEnd = integer(confirmedMap?["end"])
        if sentStart == nil && sentEnd == nil {
            return confirmedStart == nil && confirmedEnd == nil
        }
        // Off sends only an end time in the past so Discord draws no timer.
        // A start Discord attaches beside that end does not bring the timer back.
        if sentStart == nil, let sentEnd, isInThePast(sentEnd) {
            guard let confirmedEnd else { return false }
            return sameInstant(sentEnd, confirmedEnd)
        }
        if !sameInstant(sentStart, confirmedStart) { return false }
        if !sameInstant(sentEnd, confirmedEnd) { return false }
        return true
    }

    private static func isInThePast(_ value: Int) -> Bool {
        milliseconds(value) < Int(Date().timeIntervalSince1970 * 1000) - 500
    }

    private static func sameInstant(_ sent: Int?, _ confirmed: Int?) -> Bool {
        switch (sent, confirmed) {
        case (nil, nil):
            return true
        case let (sent?, confirmed?):
            return abs(milliseconds(sent) - milliseconds(confirmed)) <= 2_000
        default:
            return false
        }
    }

    private static func milliseconds(_ value: Int) -> Int {
        value < 10_000_000_000 ? value * 1000 : value
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return Int(value.int64Value) }
        return nil
    }

    private static func integerList(_ value: Any?) -> [Int]? {
        guard let values = value as? [Any] else { return nil }
        let numbers = values.compactMap(integer)
        return numbers.count == values.count ? numbers : nil
    }

    private static func stringList(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { item in
            if let string = item as? String { return string }
            return nil
        }
    }
}
