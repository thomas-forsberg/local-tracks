import Shared
import SwiftUI

// Small uppercase label above a number.
struct StatLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // textCase rather than uppercased(): VoiceOver keeps reading it as words.
        Text(text)
            .textCase(.uppercase)
            .font(.statLabel)
            .tracking(0.6)
            .foregroundStyle(Theme.inkSecondary)
    }
}

// The app's big rounded buttons: filled for the main action, outlined for the other.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case filled(Color, text: Color)
        case outlined(Color)
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .overlay { if case .outlined(let color) = kind { Capsule().strokeBorder(color, lineWidth: 1.5) } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(.capsule)
    }

    private var foreground: Color {
        switch kind {
        case .filled(_, let text): text
        case .outlined(let color): color
        }
    }

    private var background: Color {
        switch kind {
        case .filled(let color, _): color
        case .outlined: .clear
        }
    }
}

// A card on the paper background.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    // Lists and forms on the paper background instead of system grey.
    func themedList() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
}

extension Sport {
    var color: Color {
        switch self {
        case .hiking: Theme.hiking
        case .cycling: Theme.cycling
        case .running: Theme.running
        }
    }
}

enum Appearance {
    // Navigation titles in the number font, so screen titles match the stats.
    @MainActor
    static func apply() {
        let ink = UIColor(Theme.ink)
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: Font.NumberWeight.bold.fontName, size: 40) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large), .foregroundColor: ink]
        }
        if let inline = UIFont(name: Font.NumberWeight.semibold.fontName, size: 21) {
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline), .foregroundColor: ink]
        }
    }
}

// Stop needs a one-second press, so a pocket tap or a slip can't end an activity. A short tap only
// explains that; VoiceOver users get a plain "Stop" action instead of the hold.
struct HoldToStopButton: View {
    let filled: Bool
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var showsHint = false
    @State private var stopped = 0

    private static let holdDuration = 1.0

    var body: some View {
        Label(showsHint ? "Hold to stop" : "Stop", systemImage: "stop.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? Theme.onAccent : Theme.accent)
            .background {
                ZStack(alignment: .leading) {
                    Capsule().fill(filled ? Theme.accent : .clear)
                    // Fills up while held.
                    GeometryReader { geometry in
                        Capsule()
                            .fill(filled ? Theme.ink.opacity(0.25) : Theme.accent.opacity(0.25))
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .clipShape(.capsule)
            }
            .overlay { if !filled { Capsule().strokeBorder(Theme.accent, lineWidth: 1.5) } }
            .contentShape(.capsule)
            .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40) {
                stopped += 1
                progress = 0
                action()
            } onPressingChanged: { pressing in
                if pressing {
                    showsHint = true
                    withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showsHint = false
                    }
                }
            }
            .sensoryFeedback(.success, trigger: stopped)
            .accessibilityElement()
            .accessibilityLabel("Stop")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
