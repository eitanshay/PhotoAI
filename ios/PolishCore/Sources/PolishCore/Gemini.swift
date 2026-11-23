import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Request

public struct GeminiPart: Encodable, Equatable, Sendable {
    public var text: String?
    public var inlineData: InlineData?

    public struct InlineData: Codable, Equatable, Sendable {
        public var mimeType: String
        public var data: String
    }

    public static func text(_ s: String) -> GeminiPart { GeminiPart(text: s, inlineData: nil) }
    public static func jpeg(_ d: Data) -> GeminiPart {
        GeminiPart(text: nil, inlineData: InlineData(mimeType: "image/jpeg", data: d.base64EncodedString()))
    }
}

public struct GeminiRequest: Encodable, Equatable, Sendable {
    public struct Content: Encodable, Equatable, Sendable {
        public var role: String
        public var parts: [GeminiPart]
    }
    /// Only these two fields. No temperature, top_p, top_k or thinking_budget: Google deprecated them.
    public struct GenerationConfig: Encodable, Equatable, Sendable {
        public var responseMimeType: String?
        public var responseModalities: [String]?
    }

    public var contents: [Content]
    public var generationConfig: GenerationConfig

    public static func json(parts: [GeminiPart]) -> GeminiRequest {
        GeminiRequest(contents: [Content(role: "user", parts: parts)],
                      generationConfig: GenerationConfig(responseMimeType: "application/json", responseModalities: nil))
    }

    public static func image(parts: [GeminiPart]) -> GeminiRequest {
        GeminiRequest(contents: [Content(role: "user", parts: parts)],
                      generationConfig: GenerationConfig(responseMimeType: nil, responseModalities: ["TEXT", "IMAGE"]))
    }
}

// MARK: - Response

public struct GeminiResponse: Decodable, Sendable {
    public struct Candidate: Decodable, Sendable {
        public var content: Content?
        public var finishReason: String?
    }
    public struct Content: Decodable, Sendable {
        public var parts: [Part]?
    }
    public struct Part: Decodable, Sendable {
        public var text: String?
        public var inlineData: GeminiPart.InlineData?

        enum CodingKeys: String, CodingKey { case text, inlineData, inline_data }
        struct Snake: Decodable { var mime_type: String?; var mimeType: String?; var data: String }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decodeIfPresent(String.self, forKey: .text)
            if let d = try? c.decodeIfPresent(GeminiPart.InlineData.self, forKey: .inlineData) {
                inlineData = d
            } else if let s = try? c.decodeIfPresent(Snake.self, forKey: .inline_data) {
                inlineData = GeminiPart.InlineData(mimeType: s.mime_type ?? s.mimeType ?? "image/png", data: s.data)
            } else {
                inlineData = nil
            }
        }
    }
    public struct PromptFeedback: Decodable, Sendable {
        public var blockReason: String?
    }

    public var candidates: [Candidate]?
    public var promptFeedback: PromptFeedback?

    public var parts: [Part] { candidates?.first?.content?.parts ?? [] }
    public var joinedText: String { parts.compactMap { $0.text }.joined() }
}

// MARK: - Errors

public struct GeminiError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var status: Int
    public var isQuota: Bool

    public init(message: String, status: Int, isQuota: Bool = false) {
        self.message = message
        self.status = status
        self.isQuota = isQuota
    }

    public var errorDescription: String? { message }

    /// Errors where the fix is in Settings (key or model).
    public var pointsToSettings: Bool { isQuota || [400, 401, 403, 404].contains(status) || message.localizedCaseInsensitiveContains("api key") }

    public static let missingKey = GeminiError(message: "Add your Gemini API key in Settings first.", status: 0)
    public static let offline = GeminiError(message: "Could not reach Gemini. Check your connection.", status: 0)

    /// Maps an HTTP error body to a readable error. A free-tier "limit: 0" quota error gets a plain explanation.
    public static func from(status: Int, body: Data, model: String) -> GeminiError {
        var msg = ""
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let err = obj["error"] as? [String: Any], let m = err["message"] as? String {
            msg = m
        }
        if status == 429, isFreeTierQuota(msg) {
            return GeminiError(message: "\(model) has no free tier on your Google project. Turn on billing at aistudio.google.com, then try again, or pick a different model in Settings.", status: 429, isQuota: true)
        }
        return GeminiError(message: "\(status): \(msg.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : msg)", status: status)
    }

    static func isFreeTierQuota(_ msg: String) -> Bool {
        msg.range(of: #"limit:\s*0|free_tier|current quota"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func shouldRetry(_ e: GeminiError) -> Bool {
        !e.isQuota && [429, 500, 502, 503].contains(e.status)
    }
}

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// MARK: - Client

public struct GeminiClient: Sendable {
    public static let base = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    public var apiKey: String
    public var transport: HTTPTransport
    public var retryDelays: [Double]

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport(), retryDelays: [Double] = [1.5, 3.0]) {
        self.apiKey = apiKey
        self.transport = transport
        self.retryDelays = retryDelays
    }

    public func makeRequest(model: String, body: GeminiRequest) throws -> URLRequest {
        let url = GeminiClient.base.appendingPathComponent("models").appendingPathComponent("\(model):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    public func generate(model: String, body: GeminiRequest) async throws -> GeminiResponse {
        guard !apiKey.isEmpty else { throw GeminiError.missingKey }
        let request = try makeRequest(model: model, body: body)
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let data: Data
            let status: Int
            do {
                (data, status) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError where e.code == .cancelled {
                throw CancellationError()
            } catch {
                throw GeminiError.offline
            }
            if (200..<300).contains(status) {
                do { return try JSONDecoder().decode(GeminiResponse.self, from: data) }
                catch { throw GeminiError(message: "Gemini sent a response the app could not read.", status: status) }
            }
            let err = GeminiError.from(status: status, body: data, model: model)
            if GeminiError.shouldRetry(err), attempt < retryDelays.count {
                let delay = retryDelays[attempt]
                attempt += 1
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                continue
            }
            throw err
        }
    }

    /// Cheap call to confirm the key works.
    public func checkKey() async throws {
        guard !apiKey.isEmpty else { throw GeminiError.missingKey }
        var comps = URLComponents(url: GeminiClient.base.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "pageSize", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, status): (Data, Int)
        do { (data, status) = try await transport.send(req) } catch { throw GeminiError.offline }
        guard (200..<300).contains(status) else { throw GeminiError.from(status: status, body: data, model: "key check") }
    }
}
