import UIKit
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

/// Date and place the original photo was taken, read from its EXIF and GPS data.
struct PhotoMetadata {
    var date: Date?
    var location: CLLocation?
    var timeZoneOffset: String?
}

/// A picked photo, ready for Gemini.
struct PreparedPhoto {
    /// JPEG, oriented upright, longest side at most 2048. This is what Gemini sees.
    let uploadJPEG: Data
    let width: Int
    let height: Int
    /// Oriented upright, longest side at most 4096. Face close-ups are cut from this.
    let cropSource: CGImage
    let preview: UIImage
    let metadata: PhotoMetadata
}

enum ImageError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This photo could not be read. Try another one." }
}

enum ImageProcessing {
    static let uploadMaxSide = 2048
    static let cropMaxSide = 4096

    /// Works for HEIC, JPEG, PNG and anything else ImageIO can decode. Applies the EXIF orientation.
    static func prepare(data: Data) throws -> PreparedPhoto {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let upload = thumbnail(src, maxSide: uploadMaxSide),
              let uploadData = jpeg(upload, quality: 0.92) else { throw ImageError.unreadable }
        let crop = thumbnail(src, maxSide: cropMaxSide) ?? upload
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        return PreparedPhoto(uploadJPEG: uploadData, width: upload.width, height: upload.height, cropSource: crop,
                             preview: UIImage(cgImage: upload), metadata: metadata(from: props))
    }

    /// Decodes any image data, oriented upright, downscaled to maxSide if larger.
    static func thumbnail(_ src: CGImageSource, maxSide: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func cgImage(from data: Data, maxSide: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(src, maxSide: maxSide)
    }

    static func jpeg(_ image: CGImage, quality: Double, properties: [CFString: Any] = [:]) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var props = properties
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func resized(_ image: CGImage, maxSide: Double) -> CGImage {
        let k = FaceGeometry.scale(width: Double(image.width), height: Double(image.height), maxSide: maxSide)
        guard k < 1 else { return image }
        let w = max(1, Int((Double(image.width) * k).rounded()))
        let h = max(1, Int((Double(image.height) * k).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Face close-ups for the identity lock: padded crops, longest side at most 768, JPEG.
    static func faceCrops(from source: CGImage, boxes: [[Double]]) -> [Data] {
        let rects = FaceGeometry.cropRects(boxes: boxes, imageWidth: Double(source.width), imageHeight: Double(source.height))
        return rects.compactMap { r in
            let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height).integral
            guard let cropped = source.cropping(to: rect) else { return nil }
            return jpeg(resized(cropped, maxSide: 768), quality: 0.92)
        }
    }

    // MARK: Metadata

    /// A fresh formatter per call: these run on background tasks and DateFormatter is not thread-safe.
    private static func exifFormatter(_ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = zone
        return f
    }

    static func metadata(from props: [CFString: Any]) -> PhotoMetadata {
        var meta = PhotoMetadata()
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        meta.timeZoneOffset = offset
        if let dateString {
            let f = exifFormatter(offset.flatMap(timeZone(fromOffset:)) ?? .current)
            meta.date = f.date(from: dateString)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
           var lon = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { lon = -lon }
            var alt = (gps[kCGImagePropertyGPSAltitude] as? NSNumber)?.doubleValue ?? 0
            if (gps[kCGImagePropertyGPSAltitudeRef] as? NSNumber)?.intValue == 1 { alt = -alt }
            meta.location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: alt,
                                       horizontalAccuracy: 0, verticalAccuracy: 0, timestamp: meta.date ?? Date())
        }
        return meta
    }

    static func timeZone(fromOffset s: String) -> TimeZone? {
        // "+02:00" or "-07:00"
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let sign = parts[0].hasPrefix("-") ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (abs(h) * 3600 + m * 60))
    }

    /// Final JPEG for the photo library: full quality, with the original's capture date and GPS embedded.
    static func libraryJPEG(from resultData: Data, metadata: PhotoMetadata) -> Data? {
        guard let image = cgImage(from: resultData, maxSide: 8192) else { return nil }
        var props: [CFString: Any] = [:]
        var exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "Enhanced with polish ES-07"]
        var tiff: [CFString: Any] = [kCGImagePropertyTIFFSoftware: "polish ES-07"]
        if let date = metadata.date {
            let f = exifFormatter(metadata.timeZoneOffset.flatMap(timeZone(fromOffset:)) ?? .current)
            let s = f.string(from: date)
            exif[kCGImagePropertyExifDateTimeOriginal] = s
            exif[kCGImagePropertyExifDateTimeDigitized] = s
            tiff[kCGImagePropertyTIFFDateTime] = s
            if let off = metadata.timeZoneOffset { exif[kCGImagePropertyExifOffsetTimeOriginal] = off }
        }
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyTIFFDictionary] = tiff
        if let loc = metadata.location {
            let c = loc.coordinate
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(c.latitude),
                kCGImagePropertyGPSLatitudeRef: c.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(c.longitude),
                kCGImagePropertyGPSLongitudeRef: c.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSAltitude: abs(loc.altitude),
                kCGImagePropertyGPSAltitudeRef: loc.altitude >= 0 ? 0 : 1
            ] as [CFString: Any]
        }
        return jpeg(image, quality: 0.95, properties: props)
    }
}

/// The iOS side of the pipeline's image work.
struct UIKitImageOps: ImageOps, @unchecked Sendable {
    let source: CGImage

    func faceCrops(boxes: [[Double]]) async -> [Data] {
        ImageProcessing.faceCrops(from: source, boxes: boxes)
    }

    func jpegForFaceCheck(_ imageData: Data) async -> Data? {
        guard let img = ImageProcessing.cgImage(from: imageData, maxSide: 1536) else { return nil }
        return ImageProcessing.jpeg(img, quality: 0.9)
    }
}
