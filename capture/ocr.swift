import Vision
import Foundation
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: ocr <image-path>\n", stderr)
    exit(1)
}

let imagePath = CommandLine.arguments[1]
let url = URL(fileURLWithPath: imagePath)

guard let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Error: could not load image\n", stderr)
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var resultText = ""

let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation] else {
        semaphore.signal()
        return
    }
    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
    resultText = lines.joined(separator: "\n")
    semaphore.signal()
}

request.recognitionLevel = .accurate
request.recognitionLanguages = ["pt-BR", "en-US"]
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])
semaphore.wait()

print(resultText)
