import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(EnhanceSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var checking = false
    @State private var confirmClear = false
    @State private var keyStatus: (String, Bool)?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("gemini api key")
                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("Paste your key", text: $keyDraft)
                                } else {
                                    SecureField("Paste your key", text: $keyDraft)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ESFont.body)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).fill(ES.paper))
                            .overlay(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).strokeBorder(ES.line, lineWidth: 1))
                            Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                                .buttonStyle(PillButtonStyle(kind: .secondary, size: .md))
                        }
                        hint("Stored in this iPhone's Keychain. Photos go from here straight to Google. Get a key at aistudio.google.com.")
                        Button {
                            Task { await checkKey() }
                        } label: {
                            Text(checking ? "Checking" : "Check key")
                        }
                        .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                        .disabled(checking || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let keyStatus {
                            Badge(text: keyStatus.0, tone: keyStatus.1 ? .ok : .error)
                        }
                    }

                    picker("text model (reads the photo and writes the brief)", selection: $settings.textModel, options: ModelCatalog.textModels)
                    picker("image model", selection: $settings.imageModel, options: ModelCatalog.imageModels)
                    VStack(alignment: .leading, spacing: 8) {
                        picker("image model for photos with people", selection: $settings.peopleModel, options: ModelCatalog.imageModels)
                        hint("Try gemini-3-pro-image here if faces drift. It costs more per photo.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("face check")
                        Menu {
                            Picker("Face check", selection: $settings.faceCheck) {
                                ForEach(FaceCheckMode.allCases) { Text($0.label).tag($0) }
                            }
                        } label: {
                            menuLabel(settings.faceCheck.label)
                        }
                        hint("A Gemini text model compares faces before and after. Retries cost extra image calls.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("custom model ids (optional)")
                        TextField("text-model-id, image-model-id", text: $settings.customModels)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ESFont.mono(13, .regular))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).fill(ES.paper))
                            .overlay(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).strokeBorder(ES.line, lineWidth: 1))
                        hint("Overrides the pickers above if Google renames a model. The image id applies to all photos.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("library")
                        Button("Clear library", role: .destructive) { confirmClear = true }
                            .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                        hint("Deletes the enhanced copies kept inside polish. Photos you saved to your photo library stay.")
                    }

                    MonoLabel("ES-07 → polish · soft to use. sharp underneath.", color: ES.ink3)
                        .padding(.top, 6)
                }
                .padding(ES.gutter)
            }
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveAndClose() }.font(ESFont.sans(16, .semibold))
                }
            }
            .confirmationDialog("Delete every photo in the polish library?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear library", role: .destructive) { session.clearLibrary() }
            }
        }
        .onAppear { keyDraft = settings.apiKey }
        .onDisappear { commitKey() }
    }

    private func commitKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != settings.apiKey { settings.apiKey = trimmed }
    }

    private func saveAndClose() {
        commitKey()
        dismiss()
    }

    private func checkKey() async {
        commitKey()
        checking = true
        defer { checking = false }
        do {
            try await GeminiClient(apiKey: settings.apiKey).checkKey()
            keyStatus = ("key works", true)
        } catch {
            keyStatus = (String(error.localizedDescription.prefix(90)), false)
        }
    }

    private func picker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(title)
            Menu {
                Picker(title, selection: selection) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    if !options.contains(selection.wrappedValue) {
                        Text(selection.wrappedValue).tag(selection.wrappedValue)
                    }
                }
            } label: {
                menuLabel(selection.wrappedValue)
            }
        }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(ESFont.mono(13, .medium)).foregroundStyle(ES.ink)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(ES.ink2)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).fill(ES.paper))
        .overlay(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).strokeBorder(ES.line, lineWidth: 1))
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(ESFont.small).foregroundStyle(ES.ink2).fixedSize(horizontal: false, vertical: true)
    }
}
