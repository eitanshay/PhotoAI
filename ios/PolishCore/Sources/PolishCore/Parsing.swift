import Foundation

public enum ResponseParser {

    /// Strips code fences and pulls out the outermost JSON object.
    public static func jsonObject(from raw: String) -> [String: Any]? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: #"^```(?:json)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let obj = parse(s) { return obj }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else { return nil }
        return parse(String(s[start...end]))
    }

    private static func parse(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Parses the brief JSON, sanitizes it, and falls back to a generic brief when it is unusable.
    public static func analysis(from raw: String, intensity: Intensity) -> Analysis {
        let obj = jsonObject(from: raw)
        let prompt = (obj?["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let o = obj, prompt.count >= 20 else {
            return Analysis(category: .other, subject: "photo", people: 0, faces: [], identity: "", issues: [],
                            prompt: Prompts.fallbackBrief(intensity: intensity))
        }
        let category = PhotoCategory(rawValue: (o["category"] as? String ?? "").lowercased()) ?? .other
        let subject = (o["subject"] as? String).map { String($0.prefix(80)) } ?? "photo"
        var faces: [[Double]] = []
        if let arr = o["faces"] as? [Any] {
            for item in arr {
                guard let box = item as? [Any], box.count == 4 else { continue }
                let nums = box.compactMap(double)
                if nums.count == 4 { faces.append(nums) }
                if faces.count == 4 { break }
            }
        }
        var people = max(0, int(o["people"]) ?? 0)
        if people == 0 && !faces.isEmpty { people = faces.count }
        let identity = String((o["identity"] as? String ?? "").prefix(300))
        let issues = (o["issues"] as? [Any] ?? []).compactMap { $0 as? String }.prefix(4).map { String($0) }
        return Analysis(category: category, subject: subject.isEmpty ? "photo" : subject, people: people, faces: faces,
                        identity: identity, issues: Array(issues), prompt: prompt)
    }

    /// Parses the face check JSON. Returns nil if unusable, so a bad answer never blocks a result.
    public static func verdict(from raw: String) -> FaceVerdict? {
        guard let o = jsonObject(from: raw) else { return nil }
        let rawScore: Double
        if let n = o["score"] as? NSNumber { rawScore = n.doubleValue }
        else if let s = o["score"] as? String, let d = Double(s) { rawScore = d }
        else { return nil }
        guard rawScore.isFinite else { return nil }
        let score = min(10, max(1, Int(rawScore.rounded())))
        let diffs = (o["differences"] as? [Any] ?? []).prefix(4).map { "\($0)" }
        return FaceVerdict(score: score, differences: Array(diffs))
    }
}

/// Pixel rectangle independent of CoreGraphics so it runs in Linux tests.
public struct PixelRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum FaceGeometry {
    /// Converts 0 to 1000 face boxes into padded crop rectangles in pixel space.
    /// Skips invalid or tiny boxes (under 3% of either side). Pads 45% on each side and clamps to the image.
    public static func cropRects(boxes: [[Double]], imageWidth: Double, imageHeight: Double, padding: Double = 0.45) -> [PixelRect] {
        var out: [PixelRect] = []
        for box in boxes where box.count == 4 {
            let top = box[0] / 1000 * imageHeight, left = box[1] / 1000 * imageWidth
            let bottom = box[2] / 1000 * imageHeight, right = box[3] / 1000 * imageWidth
            guard bottom > top, right > left else { continue }
            guard right - left >= imageWidth * 0.03, bottom - top >= imageHeight * 0.03 else { continue }
            let padX = (right - left) * padding, padY = (bottom - top) * padding
            let l = max(0, left - padX), r = min(imageWidth, right + padX)
            let t = max(0, top - padY), b = min(imageHeight, bottom + padY)
            guard r > l, b > t else { continue }
            out.append(PixelRect(x: l, y: t, width: r - l, height: b - t))
        }
        return out
    }

    /// Scale factor so the longest side is at most maxSide.
    public static func scale(width: Double, height: Double, maxSide: Double) -> Double {
        let longest = max(width, height)
        guard longest > 0 else { return 1 }
        return min(1, maxSide / longest)
    }
}
