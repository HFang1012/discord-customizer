import SwiftUI

/// Hours, minutes, and seconds as large tiles. Stepping carries into the next unit, like a kitchen timer.
struct DurationEditor: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    var maxHours: Int

    private static let presets: [(label: String, seconds: Int)] = [
        ("5m", 300), ("15m", 900), ("30m", 1800), ("1h", 3600), ("2h", 7200)
    ]

    private var total: Int { hours * 3600 + minutes * 60 + seconds }
    private var maxTotal: Int { maxHours * 3600 + 59 * 60 + 59 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                TimeUnitTile(
                    value: hours,
                    label: "HRS",
                    digits: String(maxHours).count,
                    onStep: { step(by: 3600 * $0) },
                    onSet: { setTotal($0 * 3600 + minutes * 60 + seconds) }
                )
                TimeSeparator()
                TimeUnitTile(
                    value: minutes,
                    label: "MIN",
                    onStep: { step(by: 60 * $0) },
                    onSet: { setTotal(hours * 3600 + min(59, $0) * 60 + seconds) }
                )
                TimeSeparator()
                TimeUnitTile(
                    value: seconds,
                    label: "SEC",
                    onStep: { step(by: $0) },
                    onSet: { setTotal(hours * 3600 + minutes * 60 + min(59, $0)) }
                )
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.seconds) { preset in
                    TimerChip(title: preset.label, isSelected: total == preset.seconds) {
                        setTotal(preset.seconds)
                    }
                }
            }
        }
    }

    private func step(by delta: Int) {
        setTotal(total + delta)
    }

    private func setTotal(_ value: Int) {
        let clamped = min(maxTotal, max(0, value))
        hours = clamped / 3600
        minutes = (clamped % 3600) / 60
        seconds = clamped % 60
    }
}

/// A day and a time of day as large tiles. Stepping a tile moves the moment itself, so 11 PM + 1 hour lands on the next day.
struct MomentEditor: View {
    enum Kind {
        case start
        case end
    }

    @Binding var date: Date
    var kind: Kind

    private let calendar = Calendar.current
    private let uses12Hour: Bool = {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return format.contains("a")
    }()

    private var presets: [(label: String, offset: TimeInterval)] {
        switch kind {
        case .start:
            return [("Now", 0), ("15m ago", -900), ("1h ago", -3600), ("3h ago", -10_800)]
        case .end:
            return [("In 15m", 900), ("In 1h", 3600), ("In 3h", 10_800), ("Tomorrow", 86_400)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                dayButton("chevron.left", days: -1, help: "Previous day")
                Text(dayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 150)
                dayButton("chevron.right", days: 1, help: "Next day")
            }
            .padding(4)
            .background(DiscordTheme.field, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))

            HStack(alignment: .top, spacing: 6) {
                TimeUnitTile(
                    value: displayHour,
                    label: "HOUR",
                    onStep: { move(by: 3600 * TimeInterval($0)) },
                    onSet: setHour
                )
                TimeSeparator()
                TimeUnitTile(
                    value: calendar.component(.minute, from: date),
                    label: "MIN",
                    onStep: { move(by: 60 * TimeInterval($0)) },
                    onSet: { setComponent(.minute, to: min(59, $0)) }
                )
                if uses12Hour {
                    meridiemToggle
                        .padding(.leading, 6)
                }
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.label) { preset in
                    TimerChip(title: preset.label, isSelected: false) {
                        date = Date().addingTimeInterval(preset.offset)
                    }
                }
            }
        }
    }

    private var hour24: Int { calendar.component(.hour, from: date) }

    private var displayHour: Int {
        guard uses12Hour else { return hour24 }
        let hour = hour24 % 12
        return hour == 0 ? 12 : hour
    }

    private var dayLabel: String {
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated))
        }
        return "\(day), \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var meridiemToggle: some View {
        let isPM = hour24 >= 12
        return VStack(spacing: 4) {
            ForEach(["AM", "PM"], id: \.self) { label in
                let selected = (label == "PM") == isPM
                Button {
                    if !selected { move(by: isPM ? -43_200 : 43_200) }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 30)
                        .foregroundStyle(selected ? .white : DiscordTheme.muted)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? DiscordTheme.accent : DiscordTheme.field)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
    }

    private func dayButton(_ symbol: String, days: Int, help: String) -> some View {
        Button {
            date = calendar.date(byAdding: .day, value: days, to: date) ?? date
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .foregroundStyle(DiscordTheme.secondary)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func move(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }

    private func setHour(_ value: Int) {
        if uses12Hour {
            let hour = min(12, max(1, value)) % 12
            setComponent(.hour, to: hour24 >= 12 ? hour + 12 : hour)
        } else {
            setComponent(.hour, to: min(23, value))
        }
    }

    private func setComponent(_ component: Calendar.Component, to value: Int) {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        switch component {
        case .hour: parts.hour = value
        case .minute: parts.minute = value
        default: return
        }
        date = calendar.date(from: parts) ?? date
    }
}

/// One digit group with step arrows. Click the number to type, or use the arrow keys while it is focused.
private struct TimeUnitTile: View {
    var value: Int
    var label: String
    var digits = 2
    var onStep: (Int) -> Void
    var onSet: (Int) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    init(
        value: Int,
        label: String,
        digits: Int = 2,
        onStep: @escaping (Int) -> Void,
        onSet: @escaping (Int) -> Void
    ) {
        self.value = value
        self.label = label
        self.digits = max(2, digits)
        self.onStep = onStep
        self.onSet = onSet
    }

    var body: some View {
        VStack(spacing: 2) {
            arrow("chevron.up", delta: 1)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: CGFloat(digits) * 20 + 8)
                .focused($focused)
                .onSubmit { focused = false }
                .onKeyPress(.upArrow) {
                    onStep(1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onStep(-1)
                    return .handled
                }
            arrow("chevron.down", delta: -1)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(DiscordTheme.muted)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DiscordTheme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? DiscordTheme.accent : Color.white.opacity(0.08), lineWidth: focused ? 1.5 : 1)
        )
        .onAppear(perform: sync)
        .onChange(of: value) { _, _ in
            if !focused { sync() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
    }

    private func arrow(_ symbol: String, delta: Int) -> some View {
        Button {
            focused = false
            onStep(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DiscordTheme.secondary)
    }

    private func sync() {
        text = String(format: "%0\(digits == 2 ? 2 : 1)d", value)
    }

    private func commit() {
        if let typed = Int(text.filter(\.isNumber)), typed != value {
            onSet(typed)
        }
        sync()
    }
}

private struct TimeSeparator: View {
    var body: some View {
        Text(":")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(DiscordTheme.muted)
            .padding(.top, 22)
    }
}

private struct TimerChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? .white : DiscordTheme.secondary)
                .background(Capsule().fill(isSelected ? DiscordTheme.accent : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}
