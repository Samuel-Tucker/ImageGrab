import AppKit
import Foundation
import ImageIO
import Vision

public enum TextRecognizerError: Error, Equatable {
    case noImage
    case noTextFound
    case visionFailed
}

public enum TextRecognizer {
    /// Run Apple Vision OCR on the image at `url` and return the recognized text
    /// joined by newlines. Returns `.noTextFound` when Vision succeeds but
    /// finds no readable text.
    public static func recognizeText(at url: URL, languages: [String] = ["en-US"]) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextRecognizerError.noImage
        }
        return try await recognizeText(in: cgImage, languages: languages)
    }

    public static func recognizeText(in nsImage: NSImage, languages: [String] = ["en-US"]) async throws -> String {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw TextRecognizerError.noImage
        }
        return try await recognizeText(in: cgImage, languages: languages)
    }

    public static func recognizeText(in cgImage: CGImage, languages: [String] = ["en-US"]) async throws -> String {
        let box = CGImageBox(image: cgImage)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if lines.isEmpty {
                        continuation.resume(throwing: TextRecognizerError.noTextFound)
                    } else {
                        continuation.resume(returning: lines.joined(separator: "\n"))
                    }
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: box.image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// CGImage is not Sendable; wrap it in an @unchecked Sendable box so we can
// safely hand it across the dispatch queue boundary above. CGImage is
// immutable once constructed, so this is safe in practice.
private final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}
