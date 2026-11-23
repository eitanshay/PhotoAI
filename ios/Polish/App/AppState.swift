import Foundation
import Observation
import SwiftData
import UIKit

/// User settings. Models and options in UserDefaults, the API key in the Keychain.
@Observable
@MainActor
final class SettingsStore {
    private let d = UserDefaults.standard

    var apiKey: String { didSet { KeychainStore.write(apiKey) } }
    var textModel: String { didSet { d.set(textModel, forKey: "es07.text") } }
    var imageModel: String { didSet { d.set(imageModel, forKey: "es07.image") } }
    var peopleModel: String { didSet { d.set(peopleModel, forKey: "es07.people") } }
    var customModels: String { didSet { d.set(customModels, forKey: "es07.custom") } }
    var faceCheck: FaceCheckMode { didSet { d.set(faceCheck.rawValue, forKey: "es07.facecheck") } }

    init() {
        apiKey = KeychainStore.read()
        textModel = d.string(forKey: "es07.text") ?? ModelCatalog.defaultText
        imageModel = d.string(forKey: "es07.image") ?? ModelCatalog.defaultImage
        peopleModel = d.string(forKey: "es07.people") ?? ModelCatalog.defaultImage
        customModels = d.string(forKey: "es07.custom") ?? ""
        faceCheck = FaceCheckMode(rawValue: d.string(forKey: "es07.facecheck") ?? "") ?? .retryOnce
    }

    /// Custom model IDs override the pickers: "text-id, image-id".
    var effective: EnhanceSettings {
        let custom = customModels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let text = custom.count > 0 && !custom[0].isEmpty ? custom[0] : textModel
        let image = custom.count > 1 && !custom[1].isEmpty ? custom[1] : imageModel
        let people = custom.count > 1 && !custom[1].isEmpty ? custom[1] : peopleModel
        return EnhanceSettings(textModel: text, imageModel: image, peopleModel: people, faceCheck: faceCheck)
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct Toast: Equatable {
    var message: String
    var tone: BadgeTone
    var id = UUID()
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

enum AppTab: Hashable { case enhance, library }

/// One photo moving through read, brief, regenerate, check.
@Observable
@MainActor
final class EnhanceSession {
    // Choices, remembered between launches.
    var intensity: Intensity { didSet { UserDefaults.standard.set(intensity.rawValue, forKey: "es07.intensity") } }
    var preset: StylePreset { didSet { UserDefaults.standard.set(preset.rawValue, forKey: "es07.preset") } }
    var retouch: Retouch { didSet { UserDefaults.standard.set(retouch.rawValue, forKey: "es07.retouch") } }

    // Current photo.
    var photo: PreparedPhoto?
    var analysis: Analysis?
    var crops: [Data] = []
    var brief = ""
    var resultData: Data?
    var resultImage: UIImage?
    var verdict: FaceVerdict?
    var renderedWith = ""

    // Progress.
    var stage: EnhanceStage = .idle
    var attempt = 0
    var isBusy = false
    var startedAt: Date?
    var lastDuration: TimeInterval?
    var fromLibrary = false

    // Messages.
    var errorMessage: String?
    var errorPointsToSettings = false
    var toast: Toast?

    var tab: AppTab = .enhance
    var showSettings = false

    let settings: SettingsStore
    var modelContext: ModelContext?
    private var work: Task<Void, Never>?
    /// Bumped whenever a new photo replaces the current one, so late results from old work are dropped.
    private var generation = 0

    init(settings: SettingsStore) {
        self.settings = settings
        let d = UserDefaults.standard
        intensity = Intensity(rawValue: d.string(forKey: "es07.intensity") ?? "") ?? .magazine
        preset = StylePreset(rawValue: d.string(forKey: "es07.preset") ?? "") ?? .editorial
        retouch = Retouch(rawValue: d.string(forKey: "es07.retouch") ?? "") ?? .light
    }

    var hasPeople: Bool { analysis?.hasPeople ?? false }

    // MARK: Entry points

    func start(with data: Data) {
        guard settings.hasKey else {
            showSettings = true
            show("Add your Gemini API key first.", .signal)
            return
        }
        cancel()
        reset()
        let gen = generation
        tab = .enhance
        isBusy = true
        stage = .reading
        startedAt = Date()
        work = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) { try ImageProcessing.prepare(data: data) }.value
                guard let self, gen == self.generation else { return }
                self.photo = prepared
                try await self.readAndRender(gen)
            } catch {
                self?.handle(error, gen)
            }
        }
    }

    /// Re-reads the photo (new brief) and renders. Used when intensity changes or on retry.
    func rerunFull() {
        guard photo != nil, !isBusy else { return }
        clearError()
        isBusy = true
        startedAt = Date()
        let gen = generation
        work = Task { [weak self] in
            do { try await self?.readAndRender(gen) } catch { self?.handle(error, gen) }
        }
    }

    /// Renders again from the current brief.
    func regenerate() {
        guard photo != nil, analysis != nil, !isBusy else { return }
        clearError()
        isBusy = true
        startedAt = Date()
        let gen = generation
        work = Task { [weak self] in
            do { try await self?.renderCurrent(gen) } catch { self?.handle(error, gen) }
        }
    }

    func retry() {
        if analysis == nil { rerunFull() } else { regenerate() }
    }

    func cancel() {
        work?.cancel()
        work = nil
    }

    func newPhoto() {
        cancel()
        reset()
    }

    func setIntensity(_ v: Intensity) {
        guard v != intensity else { return }
        intensity = v
        if photo != nil && !isBusy { rerunFull() }
    }

    func setPreset(_ v: StylePreset) {
        guard v != preset else { return }
        preset = v
        if analysis != nil && !isBusy { regenerate() }
    }

    func setRetouch(_ v: Retouch) {
        guard v != retouch else { return }
        retouch = v
        if hasPeople && !isBusy { regenerate() }
    }

    // MARK: Pipeline

    private func enhancer() -> Enhancer {
        Enhancer(client: GeminiClient(apiKey: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)), settings: settings.effective)
    }

    private func ensureCurrent(_ gen: Int) throws {
        if gen != generation || Task.isCancelled { throw CancellationError() }
    }

    private func readAndRender(_ gen: Int) async throws {
        guard let photo else { return }
        stage = .reading
        let a = try await enhancer().analyze(photoJPEG: photo.uploadJPEG, intensity: intensity)
        try ensureCurrent(gen)
        analysis = a
        brief = a.prompt
        stage = .brief
        var newCrops: [Data] = []
        if a.hasPeople {
            newCrops = await UIKitImageOps(source: photo.cropSource).faceCrops(boxes: a.faces)
        }
        crops = newCrops
        try await renderCurrent(gen)
    }

    private func renderCurrent(_ gen: Int) async throws {
        guard let photo, let analysis else { return }
        if analysis.hasPeople && crops.isEmpty && !analysis.faces.isEmpty {
            let restored = await UIKitImageOps(source: photo.cropSource).faceCrops(boxes: analysis.faces)
            crops = restored
        }
        verdict = nil
        let currentBrief = brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? analysis.prompt : brief
        let out = try await enhancer().render(
            photoJPEG: photo.uploadJPEG, crops: crops, analysis: analysis, brief: currentBrief, preset: preset,
            intensity: intensity, retouch: retouch, ops: UIKitImageOps(source: photo.cropSource)
        ) { [weak self] stage, attempt in
            await MainActor.run {
                self?.stage = stage
                self?.attempt = attempt
            }
        }
        try ensureCurrent(gen)
        guard let cg = ImageProcessing.cgImage(from: out.imageData, maxSide: 4096) else {
            throw GeminiError(message: "Gemini sent an image the app could not open.", status: 0)
        }
        resultData = out.imageData
        resultImage = UIImage(cgImage: cg)
        verdict = out.verdict
        renderedWith = out.model
        stage = .done
        isBusy = false
        fromLibrary = false
        lastDuration = startedAt.map { Date().timeIntervalSince($0) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        saveToLibrary(brief: currentBrief)
    }

    private func handle(_ error: Error, _ gen: Int) {
        guard gen == generation else { return }
        isBusy = false
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            stage = resultData == nil ? .idle : .done
            show("Cancelled.", .signal)
            return
        }
        stage = resultData == nil ? .idle : .done
        if let g = error as? GeminiError {
            errorMessage = g.message
            errorPointsToSettings = g.pointsToSettings
        } else {
            errorMessage = error.localizedDescription
            errorPointsToSettings = false
        }
    }

    func clearError() {
        errorMessage = nil
        errorPointsToSettings = false
    }

    private func reset() {
        generation += 1
        photo = nil
        analysis = nil
        crops = []
        brief = ""
        resultData = nil
        resultImage = nil
        verdict = nil
        stage = .idle
        attempt = 0
        isBusy = false
        startedAt = nil
        lastDuration = nil
        fromLibrary = false
        clearError()
    }

    func show(_ message: String, _ tone: BadgeTone) {
        toast = Toast(message: message, tone: tone)
    }

    // MARK: Save

    func saveToPhotos() async {
        guard let resultData, let photo else { return }
        let meta = photo.metadata
        let jpeg = await Task.detached(priority: .userInitiated) { ImageProcessing.libraryJPEG(from: resultData, metadata: meta) }.value
        guard let jpeg else { show(SaveError.encoding.localizedDescription, .error); return }
        do {
            let inAlbum = try await PhotoSaver.save(jpeg: jpeg, metadata: meta)
            show(inAlbum ? "Saved to Photos, in the polish album." : "Saved to Photos.", .ok)
        } catch {
            show(error.localizedDescription, .error)
        }
    }

    // MARK: Library

    private func saveToLibrary(brief: String) {
        guard let context = modelContext, let photo, let analysis, let resultData else { return }
        let id = UUID()
        let originalName = "\(id.uuidString)-original.jpg"
        let resultName = "\(id.uuidString)-result.\(resultExtension(resultData))"
        do {
            try LibraryFiles.write(photo.uploadJPEG, name: originalName)
            try LibraryFiles.write(resultData, name: resultName)
        } catch { return }
        let faces = (try? String(data: JSONEncoder().encode(analysis.faces), encoding: .utf8)) ?? "[]"
        let item = LibraryItem(id: id, category: analysis.category.rawValue, subject: analysis.subject, preset: preset.rawValue,
                               intensity: intensity.rawValue, retouch: retouch.rawValue, brief: brief, people: analysis.people,
                               facesJSON: faces, identity: analysis.identity, faceScore: verdict?.score, model: renderedWith,
                               originalFile: originalName, resultFile: resultName, metadata: photo.metadata)
        context.insert(item)
        try? context.save()
    }

    private func resultExtension(_ data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
    }

    /// Reopens a library item so it can be compared, saved or regenerated.
    func open(_ item: LibraryItem) {
        cancel()
        reset()
        guard let original = LibraryFiles.read(item.originalFile),
              let result = LibraryFiles.read(item.resultFile),
              let resultCG = ImageProcessing.cgImage(from: result, maxSide: 4096),
              let prepared = try? ImageProcessing.prepare(data: original) else {
            show("That item's files are missing.", .error)
            return
        }
        // The stored original has no EXIF; restore the capture date and place from the row.
        photo = PreparedPhoto(uploadJPEG: prepared.uploadJPEG, width: prepared.width, height: prepared.height,
                              cropSource: prepared.cropSource, preview: prepared.preview, metadata: item.metadata)
        let category = PhotoCategory(rawValue: item.category) ?? .other
        analysis = Analysis(category: category, subject: item.subject, people: item.people, faces: item.faces,
                            identity: item.identity, issues: [], prompt: item.brief)
        brief = item.brief
        if let i = Intensity(rawValue: item.intensity) { intensity = i }
        if let p = StylePreset(rawValue: item.preset) { preset = p }
        if let r = Retouch(rawValue: item.retouch) { retouch = r }
        resultData = result
        resultImage = UIImage(cgImage: resultCG)
        verdict = item.faceScore.map { FaceVerdict(score: $0, differences: []) }
        renderedWith = item.model
        stage = .done
        fromLibrary = true
        tab = .enhance
    }

    func delete(_ item: LibraryItem) {
        LibraryFiles.delete([item.originalFile, item.resultFile])
        modelContext?.delete(item)
        try? modelContext?.save()
    }

    func clearLibrary() {
        guard let context = modelContext else { return }
        let items = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        for item in items {
            LibraryFiles.delete([item.originalFile, item.resultFile])
            context.delete(item)
        }
        try? context.save()
        show("Library cleared.", .ok)
    }
}
