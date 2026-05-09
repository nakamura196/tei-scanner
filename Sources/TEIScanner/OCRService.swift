import Foundation
import Vision
import AppKit
import CoreGraphics

struct OCRLine: Identifiable, Hashable {
    let id = UUID()
    var text: String
    /// Bounding box in pixel coordinates with origin at top-left.
    var box: CGRect
}

struct OCRPageResult {
    var imageSize: CGSize
    var lines: [OCRLine]
}

enum OCRError: Error {
    case cannotLoadImage(URL)
    case visionFailed(Error)
}

enum OCRLanguage: String, CaseIterable, Identifiable {
    case auto
    case english = "en-US"
    case japanese = "ja-JP"
    case chineseTraditional = "zh-Hant"
    case chineseSimplified = "zh-Hans"
    case korean = "ko-KR"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Auto-detect")
        case .english: return "English"
        case .japanese: return "日本語"
        case .chineseTraditional: return "繁體中文"
        case .chineseSimplified: return "简体中文"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }
}

enum OCRService {
    static func recognize(imageURL: URL, language: OCRLanguage) throws -> OCRPageResult {
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cannotLoadImage(imageURL)
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        switch language {
        case .auto:
            request.automaticallyDetectsLanguage = true
        default:
            request.recognitionLanguages = [language.rawValue]
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.visionFailed(error)
        }

        let observations = request.results ?? []
        let lines: [OCRLine] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            // Vision uses bottom-left origin, normalized 0..1. Convert to pixel, top-left origin.
            let bb = obs.boundingBox
            let x = bb.origin.x * imageSize.width
            let y = (1.0 - bb.origin.y - bb.size.height) * imageSize.height
            let w = bb.size.width * imageSize.width
            let h = bb.size.height * imageSize.height
            return OCRLine(text: candidate.string, box: CGRect(x: x, y: y, width: w, height: h))
        }

        return OCRPageResult(imageSize: imageSize, lines: lines)
    }
}
