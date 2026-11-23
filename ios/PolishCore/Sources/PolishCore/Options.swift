import Foundation

/// How far the rebuild goes.
public enum Intensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case refine, studio, magazine

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var note: String {
        switch self {
        case .refine: return "Light touch. Same scene, better light and color."
        case .studio: return "Full relight, new backdrop, premium retouch. Same composition."
        case .magazine: return "Full reimagining for a cover shoot. Only the subject stays."
        }
    }
}

/// Color grade direction appended to every image prompt.
public enum StylePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case natural, editorial, cinematic, bright, film

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var note: String {
        switch self {
        case .natural: return "True-to-life color and honest tones, expertly lit."
        case .editorial: return "Magazine finish. Crisp micro-contrast, refined color, clean retouching."
        case .cinematic: return "Film-still grade. Warm highlights, cooler shadows, soft roll-off."
        case .bright: return "Light and airy. Lifted exposure, clean whites, soft color."
        case .film: return "Analog look. Fine grain, faded blacks, warm midtones."
        }
    }

    public var clause: String {
        switch self {
        case .natural: return "True-to-life color, gentle contrast, honest skin and material tones, expertly lit and finished."
        case .editorial: return "Magazine finish: crisp micro-contrast, refined clean color, controlled highlights and subtle polished retouching."
        case .cinematic: return "Cinematic grade: slightly teal-leaning shadows, warm highlights, soft contrast roll-off and a touch of atmospheric depth."
        case .bright: return "Bright and airy: lifted exposure, soft luminous light, clean whites, gentle contrast and slightly pastel-leaning color."
        case .film: return "Analog film look: fine grain, gentle halation, rich but slightly faded color and warm midtones."
        }
    }
}

/// Skin and teeth retouching, applied only when people are detected.
public enum Retouch: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, light, polished

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var note: String {
        switch self {
        case .off: return "No skin or teeth retouching. Faces stay exactly as shot."
        case .light: return "Evens skin tone, clears blemishes, whitens teeth about one shade. Texture stays."
        case .polished: return "Beauty-grade smoothing and brighter teeth. Features and age stay."
        }
    }

    public var instruction: String {
        switch self {
        case .off: return ""
        case .light: return "Light retouch: remove temporary blemishes, shine and under-eye fatigue, and even out the skin tone. Keep pores, freckles, moles, scars, wrinkles and natural skin texture clearly visible. If teeth are visible, whiten them by about one shade to a natural tone, keeping tooth shape, spacing and edges exactly as they are."
        case .polished: return "Polished retouch: smooth the skin evenly in the style of high-end beauty retouching, keeping fine texture visible so it never looks plastic. Freckles, moles and scars stay. If teeth are visible, whiten them to a bright but natural shade, keeping tooth shape, spacing and edges exactly as they are. Brighten the whites of the eyes slightly. This must never change face shape, features or the apparent age."
        }
    }
}

/// Face check after each render, for photos with people.
public enum FaceCheckMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case scoreOnly = "0"
    case retryOnce = "1"
    case retryTwice = "2"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .scoreOnly: return "Check and show a score"
        case .retryOnce: return "Check, retry once if it fails"
        case .retryTwice: return "Check, retry up to twice"
        }
    }

    public var isEnabled: Bool { self != .off }

    public var retries: Int {
        switch self {
        case .off, .scoreOnly: return 0
        case .retryOnce: return 1
        case .retryTwice: return 2
        }
    }
}

public enum PhotoCategory: String, CaseIterable, Codable, Sendable {
    case portrait, group, food, car, landscape, architecture, product, pet, street, other
}

public enum ModelCatalog {
    public static let textModels = ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.1-flash-lite", "gemini-2.5-flash"]
    public static let imageModels = ["gemini-nano-banana-2.1", "gemini-3.1-flash-image", "gemini-3-pro-image", "gemini-3.1-flash-lite-image", "gemini-2.5-flash-image"]
    public static let defaultText = textModels[0]
    public static let defaultImage = imageModels[0]
}

/// Everything the pipeline needs to know about the user's choices.
public struct EnhanceSettings: Equatable, Sendable {
    public var textModel: String
    public var imageModel: String
    public var peopleModel: String
    public var faceCheck: FaceCheckMode

    public init(textModel: String = ModelCatalog.defaultText,
                imageModel: String = ModelCatalog.defaultImage,
                peopleModel: String = ModelCatalog.defaultImage,
                faceCheck: FaceCheckMode = .retryOnce) {
        self.textModel = textModel
        self.imageModel = imageModel
        self.peopleModel = peopleModel
        self.faceCheck = faceCheck
    }
}

/// What the text model returns about a photo.
public struct Analysis: Codable, Equatable, Sendable {
    public var category: PhotoCategory
    public var subject: String
    public var people: Int
    /// Boxes as [ymin, xmin, ymax, xmax], each 0 to 1000.
    public var faces: [[Double]]
    public var identity: String
    public var issues: [String]
    public var prompt: String

    public init(category: PhotoCategory, subject: String, people: Int, faces: [[Double]], identity: String, issues: [String], prompt: String) {
        self.category = category
        self.subject = subject
        self.people = people
        self.faces = faces
        self.identity = identity
        self.issues = issues
        self.prompt = prompt
    }

    public var hasPeople: Bool { people > 0 }
}

public struct FaceVerdict: Codable, Equatable, Sendable {
    public var score: Int
    public var differences: [String]

    public init(score: Int, differences: [String]) {
        self.score = score
        self.differences = differences
    }

    public var passes: Bool { score >= FaceVerdict.passScore }
    public static let passScore = 7
}
