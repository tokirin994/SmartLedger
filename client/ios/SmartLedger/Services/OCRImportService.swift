import Foundation
import UIKit
import Vision

struct OCRImportService {
  func recognizeText(from image: UIImage) async throws -> String {
    guard let cgImage = image.cgImage else {
      return ""
    }

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        // Vision 不保证 observations 的返回顺序。账单截图通常是双列布局（左侧标题、
        // 右侧金额），必须先按视觉坐标重建阅读顺序，否则标题、日期和金额会错配。
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let fragments = observations.compactMap { observation -> (text: String, box: CGRect)? in
          guard let text = observation.topCandidates(1).first?.string else { return nil }
          return (text, observation.boundingBox)
        }
        .sorted { lhs, rhs in
          if abs(lhs.box.midY - rhs.box.midY) > 0.012 {
            return lhs.box.midY > rhs.box.midY
          }
          return lhs.box.minX < rhs.box.minX
        }

        var visualRows: [(midY: CGFloat, texts: [String])] = []
        for fragment in fragments {
          if let lastIndex = visualRows.indices.last,
             abs(visualRows[lastIndex].midY - fragment.box.midY) <= 0.012 {
            visualRows[lastIndex].texts.append(fragment.text)
          } else {
            visualRows.append((fragment.box.midY, [fragment.text]))
          }
        }
        continuation.resume(returning: visualRows.map { $0.texts.joined(separator: "    ") }.joined(separator: "\n"))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["zh-Hans", "en-US"]

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try handler.perform([request])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
