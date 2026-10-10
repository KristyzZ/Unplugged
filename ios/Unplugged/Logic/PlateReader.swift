import CoreGraphics
import Foundation
#if canImport(UIKit)
import ImageIO
import UIKit
import Vision
#endif

/// A licence plate found in a photo.
struct PlateReading: Equatable {
    /// Formatted the way it's written on the plate, e.g. "ABC 123".
    let plate: String
    /// Where it is in the photo: normalised, origin top-left.
    let box: CGRect
    /// Matched a Lithuanian format rather than a generic one.
    let lithuanian: Bool
}

/// Reads licence plates on the phone with Apple's Vision text recognition.
/// Nothing leaves the device.
///
/// Lithuanian plates: three letters and three digits (ABC 123; EV plates use
/// the same layout), taxis T + five digits. The blue EU band adds "LT".
/// Text recognition mixes up look-alike characters (O/0, I/1, B/8, S/5), so
/// for the standard format each position is corrected to a letter or digit.
enum PlateReader {
    #if canImport(UIKit)
    static func read(_ image: UIImage) async -> PlateReading? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                continuation.resume(returning: best(in: request.results ?? []))
            }
        }
    }

    private static func best(in observations: [VNRecognizedTextObservation]) -> PlateReading? {
        var best: (reading: PlateReading, score: Double)?
        for observation in observations {
            for candidate in observation.topCandidates(3) {
                guard let match = match(candidate.string) else { continue }
                // Lithuanian formats win; then recognition confidence; then size
                // (the plate is usually the biggest text in a plate photo).
                let box = observation.boundingBox
                let score: Double = (match.lithuanian ? 2 : 0) + Double(candidate.confidence) + Double(box.height) * 2
                if best == nil || score > best!.score {
                    let topLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                    best = (PlateReading(plate: match.plate, box: topLeft, lithuanian: match.lithuanian), score)
                }
            }
        }
        return best?.reading
    }
    #endif

    /// Recognised text → a plate, or nil when it doesn't look like one.
    static func match(_ raw: String) -> (plate: String, lithuanian: Bool)? {
        var text = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        // The EU band's country code, read together with the plate.
        if text.count >= 8, text.hasPrefix("LT") { text.removeFirst(2) }

        // Taxi: T + 5 digits.
        if text.count == 6, text.first == "T", text.dropFirst().allSatisfy(\.isNumber) {
            return ("T \(text.dropFirst())", true)
        }

        // Standard (and EV): 3 letters + 3 digits, fixing look-alikes by position.
        if text.count == 6 {
            let letters = String(text.prefix(3).map(asLetter))
            let digits = String(text.suffix(3).map(asDigit))
            if letters.allSatisfy(\.isLetter), digits.allSatisfy(\.isNumber) {
                return ("\(letters) \(digits)", true)
            }
        }

        // Anything else plate-like (foreign or personalised): 4–8 characters
        // with both letters and digits.
        if (4...8).contains(text.count), text.contains(where: \.isLetter), text.contains(where: \.isNumber) {
            return (text, false)
        }
        return nil
    }

    private static func asLetter(_ c: Character) -> Character {
        switch c {
        case "0": "O"
        case "1": "I"
        case "2": "Z"
        case "5": "S"
        case "6": "G"
        case "8": "B"
        default: c
        }
    }

    private static func asDigit(_ c: Character) -> Character {
        switch c {
        case "O", "Q", "D": "0"
        case "I", "L": "1"
        case "Z": "2"
        case "S": "5"
        case "G": "6"
        case "B": "8"
        default: c
        }
    }
}

#if canImport(UIKit)
private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
