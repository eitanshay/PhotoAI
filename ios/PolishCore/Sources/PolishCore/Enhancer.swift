import Foundation

/// Image work the pipeline needs but that depends on the platform (UIKit on iOS, fakes in tests).
public protocol ImageOps: Sendable {
    /// JPEG face close-ups, cut from the full-resolution original.
    func faceCrops(boxes: [[Double]]) async -> [Data]
    /// A JPEG of the result downscaled for the face check (longest side about 1536).
    func jpegForFaceCheck(_ imageData: Data) async -> Data?
}

public enum EnhanceStage: String, Equatable, Sendable {
    case idle, reading, brief, rendering, checking, done
}

public struct RenderOutput: Equatable, Sendable {
    public var imageData: Data
    public var mimeType: String
    public var verdict: FaceVerdict?
    public var attempts: Int
    public var model: String
    public var prompt: String
}

/// One render attempt, used when picking the best result.
public struct Attempt: Equatable, Sendable {
    public var imageData: Data
    public var mimeType: String
    public var verdict: FaceVerdict?
    public var prompt: String
}

public enum AttemptPolicy {
    /// Keeps the first attempt, or a later one only if it scored strictly higher.
    public static func better(_ current: Attempt?, _ candidate: Attempt) -> Attempt {
        guard let current else { return candidate }
        guard let v = candidate.verdict else { return current }
        guard let cv = current.verdict else { return candidate }
        return v.score > cv.score ? candidate : current
    }

    /// Stop when there is no verdict (check off or failed) or the faces passed.
    public static func shouldStop(after verdict: FaceVerdict?) -> Bool {
        guard let verdict else { return true }
        return verdict.passes
    }

    public static func strictText(from verdict: FaceVerdict) -> String {
        verdict.differences.isEmpty ? "faces do not match the references" : verdict.differences.joined(separator: "; ")
    }
}

public struct Enhancer: Sendable {
    public var client: GeminiClient
    public var settings: EnhanceSettings

    public init(client: GeminiClient, settings: EnhanceSettings) {
        self.client = client
        self.settings = settings
    }

    /// Step 1 and 2: read the photo and write the brief.
    public func analyze(photoJPEG: Data, intensity: Intensity) async throws -> Analysis {
        let body = GeminiRequest.json(parts: [.text(Prompts.analyzeInstruction(intensity: intensity)), .jpeg(photoJPEG)])
        let res = try await client.generate(model: settings.textModel, body: body)
        return ResponseParser.analysis(from: res.joinedText, intensity: intensity)
    }

    /// One image call. Throws a readable error when no image comes back.
    public func renderOnce(photoJPEG: Data, crops: [Data], analysis: Analysis, brief: String, preset: StylePreset,
                           intensity: Intensity, retouch: Retouch, strict: String?) async throws -> Attempt {
        let prompt = Prompts.imagePrompt(brief: brief.isEmpty ? analysis.prompt : brief, preset: preset, intensity: intensity,
                                         retouch: retouch, analysis: analysis, cropCount: crops.count, strictDifferences: strict)
        var parts: [GeminiPart] = [.text(prompt), .jpeg(photoJPEG)]
        parts.append(contentsOf: crops.map { GeminiPart.jpeg($0) })
        let model = analysis.hasPeople ? settings.peopleModel : settings.imageModel
        let res = try await client.generate(model: model, body: .image(parts: parts))
        guard let inline = res.parts.first(where: { $0.inlineData != nil })?.inlineData,
              let data = Data(base64Encoded: inline.data) else {
            let text = String(res.parts.compactMap { $0.text }.joined(separator: " ").prefix(280))
            let why = !text.isEmpty ? text
                : (res.promptFeedback?.blockReason.map { "Blocked: \($0)" } ?? res.candidates?.first?.finishReason ?? "no image returned")
            throw GeminiError(message: "Gemini returned no image. \(why)", status: 0)
        }
        return Attempt(imageData: data, mimeType: inline.mimeType, verdict: nil, prompt: prompt)
    }

    /// Face check. Returns nil on any failure so a flaky check never blocks a result.
    public func verify(crops: [Data], resultJPEG: Data) async throws -> FaceVerdict? {
        var parts: [GeminiPart] = [.text(Prompts.verifyInstruction(cropCount: crops.count))]
        parts.append(contentsOf: crops.map { GeminiPart.jpeg($0) })
        parts.append(.jpeg(resultJPEG))
        do {
            let res = try await client.generate(model: settings.textModel, body: .json(parts: parts))
            return ResponseParser.verdict(from: res.joinedText)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Step 3 and 4: render, check faces, retry with the differences, keep the best attempt.
    public func render(photoJPEG: Data, crops: [Data], analysis: Analysis, brief: String, preset: StylePreset,
                       intensity: Intensity, retouch: Retouch, ops: ImageOps,
                       onStage: @Sendable (EnhanceStage, Int) async -> Void) async throws -> RenderOutput {
        let canCheck = analysis.hasPeople && settings.faceCheck.isEnabled && !crops.isEmpty
        let retries = canCheck ? settings.faceCheck.retries : 0
        var best: Attempt?
        var strict: String?
        var attempts = 0
        for attempt in 0...retries {
            try Task.checkCancellation()
            await onStage(.rendering, attempt)
            var a = try await renderOnce(photoJPEG: photoJPEG, crops: crops, analysis: analysis, brief: brief, preset: preset,
                                         intensity: intensity, retouch: retouch, strict: strict)
            attempts += 1
            if canCheck {
                await onStage(.checking, attempt)
                if let jpeg = await ops.jpegForFaceCheck(a.imageData) {
                    a.verdict = try await verify(crops: crops, resultJPEG: jpeg)
                }
            }
            best = AttemptPolicy.better(best, a)
            if AttemptPolicy.shouldStop(after: a.verdict) { break }
            strict = AttemptPolicy.strictText(from: a.verdict!)
        }
        guard let chosen = best else { throw GeminiError(message: "Gemini returned no image.", status: 0) }
        return RenderOutput(imageData: chosen.imageData, mimeType: chosen.mimeType, verdict: chosen.verdict,
                            attempts: attempts, model: analysis.hasPeople ? settings.peopleModel : settings.imageModel,
                            prompt: chosen.prompt)
    }
}
