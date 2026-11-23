import SwiftUI

// MARK: - Text styles

struct MonoLabel: View {
    let text: String
    var color: Color = ES.ink2
    init(_ text: String, color: Color = ES.ink2) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(ESFont.label)
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

// MARK: - Buttons

enum PillKind { case primary, ink, secondary, ghost }
enum PillSize { case sm, md, lg }

/// Pill button. Solid kinds get the inset bottom edge that makes them feel like keys.
struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .primary
    var size: PillSize = .md
    var full = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let height: CGFloat = size == .sm ? 32 : (size == .md ? 44 : 52)
        let hPad: CGFloat = size == .sm ? 14 : (size == .md ? 18 : 24)
        let fontSize: CGFloat = size == .sm ? 13 : (size == .md ? 15 : 17)
        configuration.label
            .font(ESFont.sans(fontSize, .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, hPad)
            .frame(height: height)
            .frame(maxWidth: full ? .infinity : nil)
            .background(background(pressed: pressed))
            .overlay(
                Capsule().strokeBorder(kind == .secondary ? ES.line : Color.clear, lineWidth: 1)
            )
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(ES.easeFast, value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return ES.onSignal
        case .ink: return ES.panel
        case .secondary, .ghost: return ES.ink
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch kind {
        case .primary:
            keyed(pressed ? ES.signalPress : ES.signal)
        case .ink:
            keyed(ES.ink.opacity(pressed ? 0.85 : 1))
        case .secondary:
            Capsule().fill(pressed ? ES.panel : ES.paper)
        case .ghost:
            Capsule().fill(pressed ? ES.ink.opacity(0.08) : Color.clear)
        }
    }

    private func keyed(_ fill: Color) -> some View {
        ZStack {
            Capsule().fill(fill)
            Capsule().fill(Color.black.opacity(0.14))
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: 3)
                }
        }
    }
}

/// Circle icon button, used for soft actions like settings.
struct IconCircleButton: View {
    let systemName: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ES.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(ES.panel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips, tabs, badges

/// Selectable chip (the Tag component).
struct TagChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ESFont.sans(14, .medium))
                .foregroundStyle(selected ? ES.panel : ES.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? ES.ink : ES.paper))
                .overlay(Capsule().strokeBorder(selected ? ES.ink : ES.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(ES.ease, value: selected)
    }
}

/// Segmented pill tabs in mono type.
struct PillTabs<Value: Hashable>: View {
    let items: [(Value, String)]
    let selection: Value
    var onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                let item = pair.element
                let on = item.0 == selection
                Button { onSelect(item.0) } label: {
                    Text(item.1)
                        .font(ESFont.mono(12, on ? .bold : .medium))
                        .foregroundStyle(on ? ES.ink : ES.ink2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(on ? ES.paper : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(ES.base))
        .animation(ES.ease, value: selection)
    }
}

enum BadgeTone { case neutral, signal, ok, warn, error }

struct Badge: View {
    let text: String
    var tone: BadgeTone = .neutral
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text.lowercased())
                .font(ESFont.mono(11, .medium))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(bg))
    }
    private var bg: Color {
        switch tone {
        case .neutral: return ES.base
        case .signal: return ES.signalSoft
        case .ok: return ES.badgeOKBG
        case .warn: return ES.badgeWarnBG
        case .error: return ES.badgeErrorBG
        }
    }
    private var fg: Color {
        switch tone {
        case .neutral: return ES.ink2
        case .signal: return ES.badgeSignalFG
        case .ok: return ES.badgeOKFG
        case .warn: return ES.badgeWarnFG
        case .error: return ES.badgeErrorFG
        }
    }
    private var dot: Color {
        switch tone {
        case .neutral: return ES.ink4
        case .signal: return ES.signal
        case .ok: return ES.ok
        case .warn: return ES.warn
        case .error: return ES.error
        }
    }
}

// MARK: - Brand

/// The mark: ink circle left, signal rounded square right, gap 14% of the shape size.
struct LogoMark: View {
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: size * 0.14) {
            Circle().fill(ES.ink).frame(width: size, height: size)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(ES.signal).frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

struct ModelTag: View {
    let code: String
    var body: some View {
        Text(code)
            .font(ESFont.mono(11, .bold))
            .foregroundStyle(ES.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(ES.panel))
    }
}

// MARK: - Surfaces

extension View {
    /// Outer panel on base: radius 20, generous padding.
    func panelSurface(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ES.radius2xl, style: .continuous).fill(ES.panel))
    }

    /// Raised card on a panel or base: radius 16.
    func raisedSurface(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous).fill(ES.paper))
    }
}

/// Fine diagonal stripe used for image placeholders.
struct StripeFill: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 11
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(path, with: .color(ES.line.opacity(0.55)), lineWidth: 1)
        }
        .background(ES.paper)
    }
}

/// Indeterminate progress bar in signal.
struct SignalProgress: View {
    @State private var phase: CGFloat = -0.34
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ES.base)
                Capsule().fill(ES.signal)
                    .frame(width: geo.size.width * 0.34)
                    .offset(x: geo.size.width * phase)
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Working")
    }
}

/// Ink pill notification at the bottom of the screen.
struct ToastView: View {
    let message: String
    var tone: BadgeTone = .signal
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(tone == .error ? ES.error : (tone == .ok ? ES.ok : ES.signal)).frame(width: 8, height: 8)
            Text(message).font(ESFont.small).foregroundStyle(ES.panel).lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Capsule().fill(ES.ink))
        .shadow(color: Color.black.opacity(0.14), radius: 20, y: 12)
        .padding(.horizontal, 16)
    }
}
