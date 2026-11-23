import SwiftUI
import UniformTypeIdentifiers

enum CompareMode: String, CaseIterable { case slide, after, before }

/// Before and after, with a draggable divider. Both images are fitted to the original's aspect ratio.
struct CompareView: View {
    let before: UIImage
    let after: UIImage?
    let aspect: CGFloat
    let mode: CompareMode
    @Binding var position: CGFloat
    var busy: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shown: CGFloat = after == nil ? 1 : (mode == .after ? 0 : (mode == .before ? 1 : position))
            ZStack(alignment: .topLeading) {
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: geo.size.height)
                    .clipped()
                if let after {
                    Image(uiImage: after)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: geo.size.height)
                        .clipped()
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: max(0, w * (1 - shown)))
                        }
                }
                if busy {
                    StripeOverlay().allowsHitTesting(false)
                }
                if after == nil || mode != .after { corner("before", ink: true).padding(12) }
                if after != nil && mode != .before {
                    corner("after", ink: false)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if after != nil && mode == .slide {
                    handle(height: geo.size.height)
                        .offset(x: w * shown - 22)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard after != nil, mode == .slide, w > 0 else { return }
                        position = min(1, max(0, v.location.x / w))
                    }
            )
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(after == nil ? "Original photo" : "Before and after comparison")
        .accessibilityValue(after == nil ? "" : "\(Int((1 - position) * 100)) percent enhanced")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: position = max(0, position - 0.1)
            case .decrement: position = min(1, position + 0.1)
            @unknown default: break
            }
        }
    }

    private func corner(_ text: String, ink: Bool) -> some View {
        Text(text)
            .font(ESFont.mono(11, .medium))
            .foregroundStyle(ink ? Color(hex: 0xF6F5F2) : ES.onSignal)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(ink ? Color(hex: 0x1D1D1B) : ES.signal))
    }

    private func handle(height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color(hex: 0xF6F5F2)).frame(width: 2, height: height)
            Circle().fill(Color(hex: 0x1D1D1B)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "chevron.left.chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xF6F5F2)))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .frame(width: 44, height: height)
    }
}

struct StripeOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.08)))
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 11
            }
            ctx.stroke(path, with: .color(Color.black.opacity(0.16)), lineWidth: 1)
        }
    }
}

struct WorkView: View {
    @Environment(EnhanceSession.self) private var session
    @State private var mode: CompareMode = .slide
    @State private var position: CGFloat = 0.5
    @State private var saving = false
    @FocusState private var briefFocused: Bool

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(spacing: ES.gutter) {
                stagePanel
                infoCard
                if let message = session.errorMessage { errorBox(message) }
                actions
            }
            .padding(.horizontal, ES.gutter)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .onChange(of: session.resultData) { _, _ in
            mode = .slide
            position = 0.5
        }
    }

    // MARK: Stage

    private var stagePanel: some View {
        VStack(spacing: 12) {
            HStack {
                if session.resultImage != nil {
                    PillTabs(items: CompareMode.allCases.map { ($0, $0.rawValue) }, selection: mode) { m in
                        withAnimation(ES.ease) { mode = m }
                    }
                }
                Spacer()
                elapsed
            }
            if let photo = session.photo {
                CompareView(before: photo.preview, after: session.resultImage,
                            aspect: CGFloat(photo.width) / CGFloat(max(1, photo.height)),
                            mode: mode, position: $position, busy: session.isBusy)
                    .frame(maxHeight: 560)
            }
            if session.isBusy { SignalProgress() }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: ES.radius2xl, style: .continuous).fill(ES.panel))
    }

    private var elapsed: some View {
        Group {
            if session.isBusy, let start = session.startedAt {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    MonoLabel("\(Int(ctx.date.timeIntervalSince(start)))s · \(stageWord)")
                }
            } else if session.fromLibrary {
                MonoLabel("from library")
            } else if let d = session.lastDuration {
                MonoLabel(String(format: "%.1fs · done", d))
            }
        }
    }

    private var stageWord: String {
        switch session.stage {
        case .reading: return "reading"
        case .brief: return "writing brief"
        case .rendering: return session.attempt > 0 ? "retry \(session.attempt)" : "regenerating"
        case .checking: return "checking faces"
        case .done, .idle: return ""
        }
    }

    // MARK: Info

    private var infoCard: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 6) {
                if let a = session.analysis {
                    Badge(text: a.category.rawValue, tone: .signal)
                }
                if let v = session.verdict {
                    Badge(text: "face match \(v.score)/10", tone: v.passes ? .ok : .warn)
                        .help(v.differences.joined(separator: "; "))
                }
                Spacer(minLength: 8)
                if let a = session.analysis {
                    MonoLabel(a.subject).lineLimit(1).truncationMode(.tail)
                }
            }
            statusList
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("prompt")
                TextEditor(text: $session.brief)
                    .font(ESFont.body)
                    .foregroundStyle(ES.ink)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).fill(ES.paper))
                    .overlay(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).strokeBorder(briefFocused ? ES.signal : ES.line, lineWidth: 1))
                    .focused($briefFocused)
                    .disabled(session.isBusy || session.analysis == nil)
                    .overlay(alignment: .topLeading) {
                        if session.brief.isEmpty {
                            Text("The brief appears here once the photo is read.")
                                .font(ESFont.body).foregroundStyle(ES.ink3)
                                .padding(.horizontal, 15).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                HStack(alignment: .top) {
                    Text("Edit it, then regenerate. A lock on the subject's identity is always added.")
                        .font(ESFont.mono(11, .regular)).foregroundStyle(ES.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if briefFocused {
                        Spacer(minLength: 8)
                        Button("Done") { briefFocused = false }
                            .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                    }
                }
            }
            ChoiceControls(showNotes: false, showRetouch: session.hasPeople)
        }
        .raisedSurface()
    }

    private var statusList: some View {
        var steps: [(EnhanceStage, String)] = [(.reading, "read the photo"), (.brief, "write the brief"), (.rendering, "regenerate")]
        if session.hasPeople && session.settings.faceCheck.isEnabled { steps.append((.checking, "check the faces")) }
        let order: [EnhanceStage] = [.reading, .brief, .rendering, .checking]
        let current = order.firstIndex(of: session.stage)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                let idx = order.firstIndex(of: pair.element.0) ?? 0
                let done = session.stage == .done || (current != nil && idx < current!)
                let on = current == idx && session.isBusy
                HStack(spacing: 10) {
                    Circle().fill(done ? ES.ok : (on ? ES.signal : ES.ink4)).frame(width: 8, height: 8)
                    Text(pair.element.1)
                        .font(ESFont.mono(12, .medium))
                        .foregroundStyle(on ? ES.ink : ES.ink2)
                }
            }
        }
    }

    // MARK: Errors and actions

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Badge(text: "error", tone: .error)
            Text(message).font(ESFont.small).foregroundStyle(ES.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try again") { session.retry() }.buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                if session.errorPointsToSettings {
                    Button("Settings") { session.showSettings = true }.buttonStyle(PillButtonStyle(kind: .ghost, size: .sm))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous).fill(ES.paper))
        .overlay(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous).strokeBorder(ES.error, lineWidth: 1))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    saving = true
                    Task {
                        await session.saveToPhotos()
                        saving = false
                    }
                } label: {
                    Label(saving ? "Saving" : "Save to Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, size: .md, full: true))
                .disabled(session.resultData == nil || session.isBusy || saving)

                Button {
                    briefFocused = false
                    session.regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(kind: .ink, size: .md, full: true))
                .disabled(session.analysis == nil || session.isBusy)
            }
            HStack(spacing: 10) {
                if session.isBusy {
                    Button("Cancel") { session.cancel() }
                        .buttonStyle(PillButtonStyle(kind: .secondary, size: .md, full: true))
                }
                if let data = session.resultData, let photo = session.photo, !session.isBusy {
                    ShareLink(item: ShareableImage(data: data, metadata: photo.metadata), preview: SharePreview("polish", image: Image(systemName: "photo"))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary, size: .md, full: true))
                }
                Button("New photo") { session.newPhoto() }
                    .buttonStyle(PillButtonStyle(kind: .ghost, size: .md, full: true))
            }
        }
    }
}

/// The result as a JPEG with the original's date and place, for the share sheet.
struct ShareableImage: Transferable {
    let data: Data
    let metadata: PhotoMetadata
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            ImageProcessing.libraryJPEG(from: item.data, metadata: item.metadata) ?? item.data
        }
    }
}
