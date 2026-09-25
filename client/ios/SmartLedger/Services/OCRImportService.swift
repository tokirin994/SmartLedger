import Foundation
import UIKit
import Vision
import ImageIO

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

        // Vision 不保证 observations 的返回顺序。不要依赖任何支付平台的固定坐标，
        // 只依据每个文本块自身的边界框重建视觉阅读顺序。行高不同的截图使用
        // 自适应阈值，避免把标题、日期和金额错误地合并到同一行。
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let fragments = observations.compactMap { observation -> (text: String, box: CGRect)? in
          // Vision occasionally returns an empty/low-confidence first candidate
          // for small amounts. Prefer the highest-confidence non-empty candidate
          // from the short candidate list, then normalize common OCR punctuation
          // artifacts before the parser sees the text.
          let candidate = observation.topCandidates(3)
            .filter { !$0.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { lhs, rhs in lhs.confidence < rhs.confidence }
          guard let candidate else { return nil }
          let text = Self.normalizeOCRArtifacts(candidate.string)
          return (text, observation.boundingBox)
        }
        .sorted { lhs, rhs in
          if abs(lhs.box.midY - rhs.box.midY) > 0.012 {
            return lhs.box.midY > rhs.box.midY
          }
          return lhs.box.minX < rhs.box.minX
        }

        var visualRows: [(midY: CGFloat, height: CGFloat, texts: [String])] = []
        for fragment in fragments {
          if let lastIndex = visualRows.indices.last,
             abs(visualRows[lastIndex].midY - fragment.box.midY) <= max(0.012, max(visualRows[lastIndex].height, fragment.box.height) * 0.55) {
            visualRows[lastIndex].texts.append(fragment.text)
          } else {
            visualRows.append((fragment.box.midY, fragment.box.height, [fragment.text]))
          }
        }
        continuation.resume(returning: visualRows.map { $0.texts.joined(separator: "    ") }.joined(separator: "\n"))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
      request.minimumTextHeight = 0.008
      if #available(iOS 16.0, *) {
        request.automaticallyDetectsLanguage = true
      }

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation, options: [:])
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try handler.perform([request])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Normalizes punctuation that Vision commonly substitutes in payment
  /// screenshots. This is deliberately context-aware: bullets in ordinary
  /// labels remain untouched while bullets/colons adjacent to digits become
  /// parseable amount separators.
  private static func normalizeOCRArtifacts(_ text: String) -> String {
    var normalized = text
      .replacingOccurrences(of: "−", with: "-")
      .replacingOccurrences(of: "‑", with: "-")
      .replacingOccurrences(of: "–", with: "-")
      .replacingOccurrences(of: "—", with: "-")
      .replacingOccurrences(of: "﹣", with: "-")
      .replacingOccurrences(of: "－", with: "-")
      .replacingOccurrences(of: "：", with: ":")
      .replacingOccurrences(of: "．", with: ".")

    // A colon between digits is usually a decimal point in an amount such as
    // “¥21:00”, not the field-label separator.
    normalized = normalized.replacingOccurrences(
      of: #"(?<=\d):(?=\d{1,2}(?:\D|$))"#,
      with: ".",
      options: .regularExpression
    )
    // “-·6.00” and “·22.00” are frequent amount renderings in list pages.
    normalized = normalized.replacingOccurrences(
      of: #"(?<!\d)[·•∙﹒](?=\d)"#,
      with: "",
      options: .regularExpression
    )
    normalized = normalized.replacingOccurrences(
      of: #"(?<=\d)[·•∙﹒](?=\d)"#,
      with: ".",
      options: .regularExpression
    )
    return normalized
  }
}

private extension UIImage {
  var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
