import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(EnhanceSession.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var session = session
        ZStack(alignment: .bottom) {
            ES.base.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, ES.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                Group {
                    switch session.tab {
                    case .library:
                        LibraryView()
                    case .enhance:
                        if session.photo == nil {
                            StartView()
                        } else {
                            WorkView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let toast = session.toast {
                ToastView(message: toast.message, tone: toast.tone)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .id(toast.id)
                    .task(id: toast.id) { [session] in
                        try? await Task.sleep(nanoseconds: 3_400_000_000)
                        if session.toast?.id == toast.id {
                            withAnimation(ES.easeSlow) { session.toast = nil }
                        }
                    }
            }
        }
        .animation(ES.easeSlow, value: session.toast)
        .sheet(isPresented: $session.showSettings) {
            SettingsView()
                .environment(settings)
                .environment(session)
        }
        .onAppear { session.modelContext = modelContext }
        .tint(ES.signal)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if !session.isBusy { session.tab = .enhance }
            } label: {
                HStack(spacing: 8) {
                    LogoMark(size: 18)
                    Text("polish")
                        .font(ESFont.sans(18, .semibold))
                        .tracking(-0.7)
                        .foregroundStyle(ES.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("polish, home")
            ModelTag(code: "ES-07")
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                navPill("enhance", .enhance)
                navPill("library", .library)
            }
            IconCircleButton(systemName: "slider.horizontal.3", label: "Settings") {
                session.showSettings = true
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous).fill(ES.paper))
    }

    private func navPill(_ title: String, _ tab: AppTab) -> some View {
        let on = session.tab == tab
        return Button {
            withAnimation(ES.ease) { session.tab = tab }
        } label: {
            Text(title)
                .font(ESFont.mono(12, .medium))
                .foregroundStyle(on ? ES.panel : ES.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Capsule().fill(on ? ES.ink : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
