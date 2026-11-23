import Foundation
import CoreLocation
import Photos
import Security
import SwiftData
import UIKit

// MARK: - Photo library

enum SaveError: LocalizedError {
    case denied
    case encoding
    var errorDescription: String? {
        switch self {
        case .denied: return "polish needs permission to add photos. Turn it on in Settings, Privacy, Photos."
        case .encoding: return "Could not prepare the image for saving."
        }
    }
}

enum PhotoSaver {
    static let albumName = "polish"

    /// Saves into Photos with the original capture date and location. With full access it also files
    /// the photo in a "polish" album; with limited or add-only access it saves to Recents only.
    /// Returns true when it went into the album.
    @discardableResult
    static func save(jpeg: Data, metadata: PhotoMetadata) async throws -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized:
            let album = findAlbum()
            try await PHPhotoLibrary.shared().performChanges {
                let request = makeRequest(jpeg: jpeg, metadata: metadata)
                guard let placeholder = request.placeholderForCreatedAsset else { return }
                if let album, let change = PHAssetCollectionChangeRequest(for: album) {
                    change.addAssets([placeholder] as NSArray)
                } else {
                    let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    create.addAssets([placeholder] as NSArray)
                }
            }
            return true
        case .limited:
            try await PHPhotoLibrary.shared().performChanges { _ = makeRequest(jpeg: jpeg, metadata: metadata) }
            return false
        default:
            let addOnly = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard addOnly == .authorized || addOnly == .limited else { throw SaveError.denied }
            try await PHPhotoLibrary.shared().performChanges { _ = makeRequest(jpeg: jpeg, metadata: metadata) }
            return false
        }
    }

    private static func makeRequest(jpeg: Data, metadata: PhotoMetadata) -> PHAssetCreationRequest {
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = "polish-\(Int(Date().timeIntervalSince1970)).jpg"
        request.addResource(with: .photo, data: jpeg, options: options)
        if let date = metadata.date { request.creationDate = date }
        if let location = metadata.location { request.location = location }
        return request
    }

    private static func findAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.eitanshay.polish"
    private static let account = "gemini-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func write(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = baseQuery
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Library

/// One enhanced photo. Image bytes live in files; this row holds everything needed to reopen and re-render it.
@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var category: String
    var subject: String
    var preset: String
    var intensity: String
    var retouch: String
    var brief: String
    var people: Int
    var facesJSON: String
    var identity: String
    var faceScore: Int?
    var model: String
    var originalFile: String
    var resultFile: String
    var takenAt: Date?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var timeZoneOffset: String?

    init(id: UUID = UUID(), createdAt: Date = .now, category: String, subject: String, preset: String, intensity: String,
         retouch: String, brief: String, people: Int, facesJSON: String, identity: String, faceScore: Int?, model: String,
         originalFile: String, resultFile: String, metadata: PhotoMetadata) {
        self.id = id
        self.createdAt = createdAt
        self.category = category
        self.subject = subject
        self.preset = preset
        self.intensity = intensity
        self.retouch = retouch
        self.brief = brief
        self.people = people
        self.facesJSON = facesJSON
        self.identity = identity
        self.faceScore = faceScore
        self.model = model
        self.originalFile = originalFile
        self.resultFile = resultFile
        self.takenAt = metadata.date
        self.latitude = metadata.location?.coordinate.latitude
        self.longitude = metadata.location?.coordinate.longitude
        self.altitude = metadata.location?.altitude
        self.timeZoneOffset = metadata.timeZoneOffset
    }

    var metadata: PhotoMetadata {
        var m = PhotoMetadata(date: takenAt, location: nil, timeZoneOffset: timeZoneOffset)
        if let latitude, let longitude {
            m.location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                    altitude: altitude ?? 0, horizontalAccuracy: 0, verticalAccuracy: 0, timestamp: takenAt ?? createdAt)
        }
        return m
    }

    var faces: [[Double]] {
        (try? JSONDecoder().decode([[Double]].self, from: Data(facesJSON.utf8))) ?? []
    }
}

/// Image files for the library, in Application Support so iOS does not purge them.
enum LibraryFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ data: Data, name: String) throws {
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func read(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func image(_ name: String, maxSide: Int = 800) -> UIImage? {
        guard let data = read(name), let cg = ImageProcessing.cgImage(from: data, maxSide: maxSide) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func delete(_ names: [String]) {
        for n in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(n)) }
    }
}
