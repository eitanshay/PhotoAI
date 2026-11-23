import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PolishCore

// MARK: - Fakes

final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest, [String: Any]) -> (Int, Data)
    private let lock = NSLock()
    private var _requests: [(URLRequest, [String: Any])] = []
    let handler: Handler

    init(handler: @escaping Handler) { self.handler = handler }

    var requests: [(URLRequest, [String: Any])] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.lock(); _requests.append((request, body)); lock.unlock()
        let (status, data) = handler(request, body)
        return (data, status)
    }
}

struct FakeOps: ImageOps {
    func faceCrops(boxes: [[Double]]) async -> [Data] { boxes.map { _ in Data("crop".utf8) } }
    func jpegForFaceCheck(_ imageData: Data) async -> Data? { Data("small".utf8) }
}

func textResponse(_ text: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": text]]]]]])
}

func imageResponse(_ bytes: Data = Data([1, 2, 3])) -> Data {
    try! JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [
        ["text": "here you go"], ["inlineData": ["mimeType": "image/png", "data": bytes.base64EncodedString()]]
    ]]]]])
}

func firstText(_ body: [String: Any]) -> String {
    let contents = body["contents"] as? [[String: Any]] ?? []
    let parts = contents.first?["parts"] as? [[String: Any]] ?? []
    return parts.first?["text"] as? String ?? ""
}

func partCount(_ body: [String: Any]) -> Int {
    ((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])?.count ?? 0
}

func model(of req: URLRequest) -> String {
    req.url!.lastPathComponent.replacingOccurrences(of: ":generateContent", with: "")
}

let personAnalysisJSON = """
{"category":"portrait","subject":"man in blue shirt","people":1,"faces":[[150,360,600,640]],"identity":"adult man, short dark hair, light stubble","issues":["flat light"],"prompt":"Man in a blue shirt on a seamless warm gray backdrop, large beauty dish key camera left, strip rim light, 85mm at f/2.8, rich grade."}
"""

// MARK: - Tests

final class PromptTests: XCTestCase {
    func testAnalyzeInstructionVariants() {
        let refine = Prompts.analyzeInstruction(intensity: .refine)
        XCTAssertTrue(refine.contains("senior photo retoucher"))
        XCTAssertTrue(refine.contains("70 to 140 words"))
        XCTAssertTrue(refine.contains("\"faces\": array of up to 4 boxes"))
        let studio = Prompts.analyzeInstruction(intensity: .studio)
        XCTAssertTrue(studio.contains("Intensity: STUDIO."))
        let mag = Prompts.analyzeInstruction(intensity: .magazine)
        XCTAssertTrue(mag.contains("Intensity: MAGAZINE."))
        XCTAssertTrue(mag.contains("140 to 210 words"))
        for s in [refine, studio, mag] {
            XCTAssertTrue(s.contains("these rules override everything else"))
            XCTAssertTrue(s.contains("{\"category\": one of \"portrait\""))
        }
    }

    func testNoPeoplePromptIsReimagining() {
        let a = Analysis(category: .food, subject: "ramen", people: 0, faces: [], identity: "", issues: [], prompt: "Ramen brief")
        let p = Prompts.imagePrompt(brief: "  Ramen brief  ", preset: .editorial, intensity: .magazine, retouch: .light,
                                    analysis: a, cropCount: 0, strictDifferences: nil)
        XCTAssertTrue(p.hasPrefix("Use the attached photo as the reference"))
        XCTAssertTrue(p.contains("Ramen brief\n\nStyle direction: Magazine finish"))
        XCTAssertTrue(p.hasSuffix(Prompts.identityLock))
        XCTAssertFalse(p.contains("PEOPLE LOCK"))
        XCTAssertFalse(p.contains("whiten"))
    }

    func testPeoplePromptLightRetouch() {
        let a = ResponseParser.analysis(from: personAnalysisJSON, intensity: .magazine)
        let p = Prompts.imagePrompt(brief: a.prompt, preset: .natural, intensity: .magazine, retouch: .light,
                                    analysis: a, cropCount: 1, strictDifferences: nil)
        XCTAssertTrue(p.hasPrefix("Edit the attached photograph as described below."))
        XCTAssertTrue(p.contains("Image 2 is a close-up of the faces in it"))
        XCTAssertTrue(p.contains("light stubble"))
        XCTAssertTrue(p.contains("whiten them by about one shade"))
        XCTAssertFalse(p.contains("skin tone and texture"))
        XCTAssertTrue(p.hasSuffix("Reminder: the people must look identical to the original photo."))
    }

    func testPeoplePromptRetouchOffAndRetry() {
        let a = ResponseParser.analysis(from: personAnalysisJSON, intensity: .refine)
        let p = Prompts.imagePrompt(brief: a.prompt, preset: .film, intensity: .refine, retouch: .off,
                                    analysis: a, cropCount: 3, strictDifferences: "nose is narrower")
        XCTAssertTrue(p.contains(Prompts.guardRefine))
        XCTAssertTrue(p.contains("Images 2 to 4 are close-ups"))
        XCTAssertTrue(p.contains("skin tone and texture"))
        XCTAssertTrue(p.contains("Do not beautify, slim, smooth skin"))
        XCTAssertTrue(p.contains("Differences found: nose is narrower."))
        XCTAssertFalse(p.contains("Light retouch"))
    }

    func testPolishedRetouch() {
        let a = ResponseParser.analysis(from: personAnalysisJSON, intensity: .studio)
        let p = Prompts.imagePrompt(brief: a.prompt, preset: .bright, intensity: .studio, retouch: .polished,
                                    analysis: a, cropCount: 0, strictDifferences: nil)
        XCTAssertTrue(p.contains("Polished retouch"))
        XCTAssertFalse(p.contains("close-up"))
    }
}

final class ParsingTests: XCTestCase {
    func testParsesFencedJSON() {
        let a = ResponseParser.analysis(from: "```json\n" + personAnalysisJSON + "\n```", intensity: .magazine)
        XCTAssertEqual(a.category, .portrait)
        XCTAssertEqual(a.people, 1)
        XCTAssertEqual(a.faces, [[150, 360, 600, 640]])
        XCTAssertEqual(a.identity, "adult man, short dark hair, light stubble")
        XCTAssertEqual(a.issues, ["flat light"])
    }

    func testJSONWithChatter() {
        let a = ResponseParser.analysis(from: "Sure! Here it is: " + personAnalysisJSON + " Hope that helps.", intensity: .magazine)
        XCTAssertEqual(a.subject, "man in blue shirt")
    }

    func testFallbackWhenUnusable() {
        let a = ResponseParser.analysis(from: "not json", intensity: .refine)
        XCTAssertEqual(a.category, .other)
        XCTAssertEqual(a.prompt, Prompts.fallbackBrief(intensity: .refine))
        let b = ResponseParser.analysis(from: #"{"prompt":"too short"}"#, intensity: .magazine)
        XCTAssertEqual(b.prompt, Prompts.fallbackBrief(intensity: .magazine))
    }

    func testSanitizesFields() {
        let raw = #"{"category":"Spaceship","subject":"x","people":"0","faces":[[1,2,3],[10,10,500,500],["a",1,2,3],[20,20,600,600],[1,1,900,900],[2,2,800,800],[3,3,700,700]],"prompt":"A long enough prompt to pass the length check here."}"#
        let a = ResponseParser.analysis(from: raw, intensity: .studio)
        XCTAssertEqual(a.category, .other)
        XCTAssertEqual(a.faces.count, 4)
        XCTAssertEqual(a.people, 4, "people inferred from faces when model says 0")
    }

    func testVerdict() {
        XCTAssertEqual(ResponseParser.verdict(from: #"{"score": 8.4, "differences": ["a","b","c","d","e"]}"#),
                       FaceVerdict(score: 8, differences: ["a", "b", "c", "d"]))
        XCTAssertEqual(ResponseParser.verdict(from: #"{"score": 14}"#)?.score, 10)
        XCTAssertEqual(ResponseParser.verdict(from: #"{"score": "3"}"#)?.score, 3)
        XCTAssertNil(ResponseParser.verdict(from: "nope"))
        XCTAssertNil(ResponseParser.verdict(from: #"{"differences": []}"#))
    }
}

final class GeometryTests: XCTestCase {
    func testCropRects() {
        let r = FaceGeometry.cropRects(boxes: [[150, 360, 600, 640]], imageWidth: 1600, imageHeight: 1200)
        XCTAssertEqual(r.count, 1)
        // face: left 576, right 1024, top 180, bottom 720; pad 45%: 201.6 x, 243 y
        XCTAssertEqual(r[0].x, 374.4, accuracy: 0.01)
        XCTAssertEqual(r[0].y, 0, accuracy: 0.01)
        XCTAssertEqual(r[0].width, 1225.6 - 374.4, accuracy: 0.01)
        XCTAssertEqual(r[0].height, 963, accuracy: 0.01)
    }

    func testSkipsBadBoxes() {
        let r = FaceGeometry.cropRects(boxes: [[500, 500, 400, 600], [10, 10, 15, 15], [0, 0, 1000, 1000]], imageWidth: 100, imageHeight: 100)
        XCTAssertEqual(r, [PixelRect(x: 0, y: 0, width: 100, height: 100)])
    }

    func testScale() {
        XCTAssertEqual(FaceGeometry.scale(width: 4096, height: 3072, maxSide: 2048), 0.5)
        XCTAssertEqual(FaceGeometry.scale(width: 800, height: 600, maxSide: 2048), 1)
    }
}

final class ClientTests: XCTestCase {
    func testRequestShapeHasNoSamplingParams() throws {
        let t = MockTransport { _, _ in (200, textResponse("{}")) }
        let c = GeminiClient(apiKey: "K", transport: t, retryDelays: [])
        let req = try c.makeRequest(model: "gemini-3.8-flash", body: .json(parts: [.text("hi"), .jpeg(Data([9]))]))
        XCTAssertEqual(req.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "K")
        let json = String(data: req.httpBody!, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"responseMimeType\":\"application\\/json\"") || json.contains("\"responseMimeType\":\"application/json\""))
        XCTAssertTrue(json.contains("\"inlineData\""))
        for banned in ["temperature", "topP", "topK", "thinking", "responseModalities"] {
            XCTAssertFalse(json.contains(banned), banned)
        }
    }

    func testQuotaErrorIsNotRetried() async {
        let body = #"{"error":{"message":"Quota exceeded for metric: generate_content_free_tier_requests, limit: 0"}}"#
        let t = MockTransport { _, _ in (429, Data(body.utf8)) }
        let c = GeminiClient(apiKey: "K", transport: t, retryDelays: [0, 0])
        do {
            _ = try await c.generate(model: "gemini-nano-banana-2.1", body: .image(parts: [.text("x")]))
            XCTFail("should throw")
        } catch let e as GeminiError {
            XCTAssertTrue(e.isQuota)
            XCTAssertTrue(e.message.contains("no free tier"))
            XCTAssertTrue(e.pointsToSettings)
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(t.requests.count, 1)
    }

    func testRetriesTransientThenSucceeds() async throws {
        var calls = 0
        let t = MockTransport { _, _ in
            calls += 1
            return calls < 3 ? (503, Data(#"{"error":{"message":"overloaded"}}"#.utf8)) : (200, textResponse("ok"))
        }
        let c = GeminiClient(apiKey: "K", transport: t, retryDelays: [0, 0])
        let r = try await c.generate(model: "m", body: .json(parts: [.text("x")]))
        XCTAssertEqual(r.joinedText, "ok")
        XCTAssertEqual(t.requests.count, 3)
    }

    func testMissingKey() async {
        let c = GeminiClient(apiKey: "", transport: MockTransport { _, _ in (200, Data()) })
        do { _ = try await c.generate(model: "m", body: .json(parts: [])); XCTFail() }
        catch let e as GeminiError { XCTAssertEqual(e, .missingKey) }
        catch { XCTFail() }
    }

    func testSnakeCaseInlineData() throws {
        let d = Data(#"{"candidates":[{"content":{"parts":[{"inline_data":{"mime_type":"image/jpeg","data":"AQID"}}]}}]}"#.utf8)
        let r = try JSONDecoder().decode(GeminiResponse.self, from: d)
        XCTAssertEqual(r.parts.first?.inlineData?.mimeType, "image/jpeg")
    }
}

final class PipelineTests: XCTestCase {
    func makeEnhancer(_ t: MockTransport, face: FaceCheckMode = .retryOnce) -> Enhancer {
        Enhancer(client: GeminiClient(apiKey: "K", transport: t, retryDelays: []),
                 settings: EnhanceSettings(textModel: "text-m", imageModel: "img-m", peopleModel: "people-m", faceCheck: face))
    }

    func testPortraitRetriesWithDifferencesAndKeepsBest() async throws {
        var scores = [4, 8]
        let t = MockTransport { req, body in
            let m = model(of: req)
            if m == "people-m" { return (200, imageResponse(Data([UInt8(10 + partCount(body))]))) }
            let text = firstText(body)
            if text.contains("forensic") {
                let s = scores.removeFirst()
                return (200, textResponse(#"{"score":\#(s),"differences":["nose is narrower","eyes are larger"]}"#))
            }
            return (200, textResponse(personAnalysisJSON))
        }
        let e = makeEnhancer(t)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .magazine)
        XCTAssertTrue(a.hasPeople)
        let crops = await FakeOps().faceCrops(boxes: a.faces)
        let out = try await e.render(photoJPEG: Data([0]), crops: crops, analysis: a, brief: a.prompt, preset: .editorial,
                                     intensity: .magazine, retouch: .light, ops: FakeOps()) { _, _ in }
        XCTAssertEqual(out.attempts, 2)
        XCTAssertEqual(out.verdict?.score, 8)
        XCTAssertEqual(out.model, "people-m")
        let calls = t.requests.map { model(of: $0.0) }
        XCTAssertEqual(calls, ["text-m", "people-m", "text-m", "people-m", "text-m"])
        let imageBodies = t.requests.filter { model(of: $0.0) == "people-m" }.map { $0.1 }
        XCTAssertEqual(partCount(imageBodies[0]), 3, "text + photo + 1 crop")
        XCTAssertFalse(firstText(imageBodies[0]).contains("nose is narrower"))
        XCTAssertTrue(firstText(imageBodies[1]).contains("Differences found: nose is narrower; eyes are larger"))
        let verifyBody = t.requests[2].1
        XCTAssertEqual(partCount(verifyBody), 3, "instruction + 1 crop + result")
    }

    func testKeepsFirstWhenRetryScoresLower() async throws {
        var scores = [5, 3]
        var renders = 0
        let t = MockTransport { req, body in
            if model(of: req) == "people-m" { renders += 1; return (200, imageResponse(Data([UInt8(renders)]))) }
            if firstText(body).contains("forensic") { return (200, textResponse(#"{"score":\#(scores.removeFirst())}"#)) }
            return (200, textResponse(personAnalysisJSON))
        }
        let e = makeEnhancer(t)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .studio)
        let out = try await e.render(photoJPEG: Data([0]), crops: [Data([1])], analysis: a, brief: "", preset: .natural,
                                     intensity: .studio, retouch: .off, ops: FakeOps()) { _, _ in }
        XCTAssertEqual(out.imageData, Data([1]))
        XCTAssertEqual(out.verdict?.score, 5)
        XCTAssertEqual(out.attempts, 2)
    }

    func testFaceCheckOffMakesOneImageCall() async throws {
        let t = MockTransport { req, _ in
            model(of: req) == "people-m" ? (200, imageResponse()) : (200, textResponse(personAnalysisJSON))
        }
        let e = makeEnhancer(t, face: .off)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .magazine)
        let out = try await e.render(photoJPEG: Data([0]), crops: [Data([1])], analysis: a, brief: a.prompt, preset: .film,
                                     intensity: .magazine, retouch: .polished, ops: FakeOps()) { _, _ in }
        XCTAssertNil(out.verdict)
        XCTAssertEqual(t.requests.map { model(of: $0.0) }, ["text-m", "people-m"])
    }

    func testNonPeopleUsesImageModelAndNoCheck() async throws {
        let food = #"{"category":"food","subject":"ramen","people":0,"faces":[],"identity":"","issues":[],"prompt":"Ramen on dark slate, softbox back left, 90mm at f/4, steam, rich color."}"#
        let t = MockTransport { req, _ in
            model(of: req) == "img-m" ? (200, imageResponse()) : (200, textResponse(food))
        }
        let e = makeEnhancer(t)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .magazine)
        let out = try await e.render(photoJPEG: Data([0]), crops: [], analysis: a, brief: a.prompt, preset: .editorial,
                                     intensity: .magazine, retouch: .light, ops: FakeOps()) { _, _ in }
        XCTAssertEqual(out.model, "img-m")
        XCTAssertEqual(t.requests.count, 2)
        XCTAssertTrue(out.prompt.hasPrefix("Use the attached photo"))
    }

    func testNoImageReturnedExplains() async throws {
        let t = MockTransport { req, _ in
            model(of: req) == "img-m"
                ? (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"I can't help with that."}]},"finishReason":"SAFETY"}]}"#.utf8))
                : (200, textResponse(#"{"category":"car","people":0,"prompt":"A red car on wet asphalt at blue hour, strip lights, low camera."}"#))
        }
        let e = makeEnhancer(t)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .studio)
        do {
            _ = try await e.render(photoJPEG: Data([0]), crops: [], analysis: a, brief: "", preset: .natural,
                                   intensity: .studio, retouch: .off, ops: FakeOps()) { _, _ in }
            XCTFail()
        } catch let err as GeminiError {
            XCTAssertTrue(err.message.contains("I can't help with that."))
        }
    }

    func testFailedVerifyDoesNotBlock() async throws {
        let t = MockTransport { req, body in
            if model(of: req) == "people-m" { return (200, imageResponse()) }
            if firstText(body).contains("forensic") { return (500, Data()) }
            return (200, textResponse(personAnalysisJSON))
        }
        let e = makeEnhancer(t, face: .retryTwice)
        let a = try await e.analyze(photoJPEG: Data([0]), intensity: .magazine)
        let out = try await e.render(photoJPEG: Data([0]), crops: [Data([1])], analysis: a, brief: a.prompt, preset: .natural,
                                     intensity: .magazine, retouch: .light, ops: FakeOps()) { _, _ in }
        XCTAssertNil(out.verdict)
        XCTAssertEqual(out.attempts, 1)
    }
}
