import SwiftUI
import PhotosUI

/// The three choices that shape a render. Shown on the start screen and next to the result.
struct ChoiceControls: View {
    @Environment(EnhanceSession.self) private var session
    var showNotes: Bool
    var showRetouch: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("how far to go")
                PillTabs(items: Intensity.allCases.map { ($0, $0.label) }, selection: session.intensity) { session.setIntensity($0) }
                if showNotes { note(session.intensity.note) }
            }
            if showRetouch {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel("retouch people")
                    PillTabs(items: Retouch.allCases.map { ($0, $0.label) }, selection: session.retouch) { session.setRetouch($0) }
                    if showNotes { note(session.retouch.note + " Applies only when people are detected.") }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("style")
                FlowLayout(spacing: 8) {
                    ForEach(StylePreset.allCases) { p in
                        TagChip(title: p.label, selected: session.preset == p) { session.setPreset(p) }
                    }
                }
                if showNotes { note(session.preset.note) }
            }
        }
        .disabled(session.isBusy)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(ESFont.small).foregroundStyle(ES.ink2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Opens the photo picker and hands the original file (HEIC stays HEIC) to the session.
struct PhotoPickButton: View {
    @Environment(EnhanceSession.self) private var session
    var title = "Choose a photo"
    var kind: PillKind = .primary
    var size: PillSize = .lg
    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(kind == .primary ? ES.onSignal : ES.ink)
                } else {
                    Image(systemName: "photo.on.rectangle")
                }
                Text(title)
            }
        }
        .buttonStyle(PillButtonStyle(kind: kind, size: size))
        .disabled(loading)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                loading = false
                item = nil
                if let data {
                    session.start(with: data)
                } else {
                    session.show("Could not load that photo. If it is in iCloud, try again once it has downloaded.", .error)
                }
            }
        }
    }
}

struct StartView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ES.gutter) {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 16) {
                        MonoLabel("ES-07 · photo tool")
                        Text("shot like a pro.")
                            .font(ESFont.display)
                            .tracking(-1.8)
                            .foregroundStyle(ES.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Pick a photo. polish reads what it is, writes the shot brief a magazine photographer would follow, and rebuilds the photo around the same subject.")
                            .font(ESFont.lead)
                            .foregroundStyle(ES.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 14) {
                        MonoLabel("from your library")
                        PhotoPickButton()
                        Text("HEIC, JPEG and PNG. The date and place it was taken carry over when you save.")
                            .font(ESFont.small)
                            .foregroundStyle(ES.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 36)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(StripeFill().clipShape(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous)))
                    .overlay(
                        RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous)
                            .strokeBorder(ES.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    ChoiceControls(showNotes: true)
                }
                .panelSurface(padding: 22)

                VStack(spacing: 10) {
                    step("01", "Read", "A Gemini text model looks at the photo and names what kind it is: portrait, food, car, place and so on.")
                    step("02", "Brief", "It writes the full shot brief for that kind: set, lighting, lens, grade and retouch. You can read it and edit it.")
                    step("03", "Regenerate", "A Gemini image model makes a new photograph from that brief, with the subject's identity locked.")
                }
            }
            .padding(.horizontal, ES.gutter)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(n).font(ESFont.mono(20, .bold)).foregroundStyle(ES.ink)
            Text(title).font(ESFont.h3).tracking(-0.6).foregroundStyle(ES.ink)
            Text(text).font(ESFont.small).foregroundStyle(ES.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous).fill(ES.paper))
    }
}
