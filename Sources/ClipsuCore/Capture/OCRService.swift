import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Runs on-device text recognition (Vision) over images so they become searchable.
public final class OCRService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.clipsu.ocr", qos: .utility)

    public init() {}

    /// Recognises text asynchronously. `completion` is called on an arbitrary background queue.
    public func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            let text = try? Self.recognizeSync(imageData: imageData)
            completion(text)
        }
    }

    /// Synchronous recognition. Returns joined recognised lines, or nil when nothing is found.
    public static func recognizeSync(imageData: Data) throws -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
