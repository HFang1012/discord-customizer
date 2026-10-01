import SwiftUI

/// Discord chat formatting: `**bold**`, `*italic*`, `_italic_`, `__underline__`, `~~strike~~`, `` `code` ``, `||spoiler||`.
/// The preview uses real fonts. The string sent to Discord uses Unicode styled letters, because Rich Presence shows plain text.
enum DiscordFormatting {
    struct Style: OptionSet {
        let rawValue: Int
        static let bold = Style(rawValue: 1 << 0)
        static let italic = Style(rawValue: 1 << 1)
        static let underline = Style(rawValue: 1 << 2)
        static let strikethrough = Style(rawValue: 1 << 3)
        static let code = Style(rawValue: 1 << 4)
        static let spoiler = Style(rawValue: 1 << 5)
    }

    struct Run {
        var text: String
        var style: Style
    }

    static func plain(_ source: String) -> String {
        runs(in: source).map(\.text).joined()
    }

    static func attributed(
        _ source: String,
        size: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs(in: source) {
            var piece = AttributedString(run.text)
            let resolvedWeight: Font.Weight = run.style.contains(.bold) ? .bold : weight
            var font = Font.system(
                size: size,
                weight: resolvedWeight,
                design: run.style.contains(.code) ? .monospaced : .default
            )
            if run.style.contains(.italic) {
                font = font.italic()
            }
            piece.font = font
            piece.foregroundColor = color
            if run.style.contains(.underline) {
                piece.underlineStyle = .single
            }
            if run.style.contains(.strikethrough) {
                piece.strikethroughStyle = .single
            }
            if run.style.contains(.code) {
                piece.backgroundColor = Color.white.opacity(0.08)
            }
            if run.style.contains(.spoiler) {
                piece.backgroundColor = Color.white.opacity(0.14)
            }
            result.append(piece)
        }
        return result
    }

    /// Styled text Discord can display in a presence field.
    static func discordText(_ source: String, limit: Int) -> String {
        var output = ""
        for run in runs(in: source) {
            for character in run.text {
                let styled = styledCharacter(character, style: run.style)
                if output.count + styled.count > limit {
                    return output
                }
                output.append(styled)
            }
        }
        return output
    }

    static func runs(in source: String) -> [Run] {
        var index = source.startIndex
        let parsed = parse(source, index: &index, style: [], closer: nil)
        if parsed.isEmpty {
            return [Run(text: "", style: [])]
        }
        return parsed
    }

    private struct Marker {
        var token: String
        var style: Style
    }

    private static let markers: [Marker] = [
        Marker(token: "```", style: .code),
        Marker(token: "||", style: .spoiler),
        Marker(token: "~~", style: .strikethrough),
        Marker(token: "***", style: [.bold, .italic]),
        Marker(token: "___", style: [.underline, .italic]),
        Marker(token: "**", style: .bold),
        Marker(token: "__", style: .underline),
        Marker(token: "`", style: .code),
        Marker(token: "*", style: .italic),
        Marker(token: "_", style: .italic)
    ]

    private static func parse(
        _ source: String,
        index: inout String.Index,
        style: Style,
        closer: String?
    ) -> [Run] {
        var runs: [Run] = []
        var buffer = ""
        let literal = style.contains(.code)

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(Run(text: buffer, style: style))
            buffer.removeAll(keepingCapacity: true)
        }

        while index < source.endIndex {
            if !literal, source[index] == "\\" {
                let next = source.index(after: index)
                if next < source.endIndex {
                    buffer.append(source[next])
                    index = source.index(after: next)
                    continue
                }
            }

            if let closer,
               source[index...].hasPrefix(closer),
               canClose(source, at: index, token: closer) {
                flush()
                index = source.index(index, offsetBy: closer.count)
                return runs
            }

            if !literal,
               let marker = openingMarker(source, at: index) {
                flush()
                index = source.index(index, offsetBy: marker.token.count)
                runs.append(contentsOf: parse(
                    source,
                    index: &index,
                    style: style.union(marker.style),
                    closer: marker.token
                ))
                continue
            }

            buffer.append(source[index])
            index = source.index(after: index)
        }

        flush()
        return runs
    }

    private static func openingMarker(_ source: String, at index: String.Index) -> Marker? {
        for marker in markers {
            guard source[index...].hasPrefix(marker.token) else { continue }
            guard canOpen(source, at: index, token: marker.token) else { continue }
            let contentStart = source.index(index, offsetBy: marker.token.count)
            guard findClose(source, from: contentStart, token: marker.token) != nil else { continue }
            return marker
        }
        return nil
    }

    private static func findClose(_ source: String, from start: String.Index, token: String) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index] == "\\" {
                let next = source.index(after: index)
                if next < source.endIndex {
                    index = source.index(after: next)
                    continue
                }
            }
            if source[index...].hasPrefix(token), canClose(source, at: index, token: token) {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func canOpen(_ source: String, at index: String.Index, token: String) -> Bool {
        let after = source.index(index, offsetBy: token.count)
        guard after < source.endIndex else { return false }
        if source[after].isWhitespace || source[after].isNewline { return false }
        if token.contains("_"), index > source.startIndex {
            let previous = source[source.index(before: index)]
            if previous.isLetter || previous.isNumber { return false }
        }
        return true
    }

    private static func canClose(_ source: String, at index: String.Index, token: String) -> Bool {
        guard index > source.startIndex else { return false }
        let previous = source[source.index(before: index)]
        if previous.isWhitespace || previous.isNewline { return false }
        if token.contains("_") {
            let after = source.index(index, offsetBy: token.count)
            if after < source.endIndex {
                let next = source[after]
                if next.isLetter || next.isNumber { return false }
            }
        }
        return true
    }

    private static func styledCharacter(_ character: Character, style: Style) -> String {
        let base: Character
        if style.contains(.code) {
            base = mapped(character, upper: 0x1D670, lower: 0x1D68A, digit: 0x1D7F6) ?? character
        } else if style.contains(.bold), style.contains(.italic) {
            base = mapped(character, upper: 0x1D63C, lower: 0x1D656, digit: 0x1D7EC) ?? character
        } else if style.contains(.bold) {
            base = mapped(character, upper: 0x1D5D4, lower: 0x1D5EE, digit: 0x1D7EC) ?? character
        } else if style.contains(.italic) {
            base = mapped(character, upper: 0x1D434, lower: 0x1D44E, digit: nil, italicH: true) ?? character
        } else {
            base = character
        }
        var result = String(base)
        if style.contains(.underline) {
            result.append("\u{0332}")
        }
        if style.contains(.strikethrough) {
            result.append("\u{0336}")
        }
        return result
    }

    private static func mapped(
        _ character: Character,
        upper: UInt32,
        lower: UInt32,
        digit: UInt32?,
        italicH: Bool = false
    ) -> Character? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return nil
        }
        let value = scalar.value
        let mappedValue: UInt32
        if value >= 65 && value <= 90 {
            mappedValue = upper + (value - 65)
        } else if value >= 97 && value <= 122 {
            if italicH && value == 104 {
                mappedValue = 0x210E
            } else {
                mappedValue = lower + (value - 97)
            }
        } else if let digit, value >= 48 && value <= 57 {
            mappedValue = digit + (value - 48)
        } else {
            return nil
        }
        guard let unicode = UnicodeScalar(mappedValue) else { return nil }
        return Character(unicode)
    }
}
