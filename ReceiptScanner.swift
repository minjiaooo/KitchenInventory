import SwiftUI
import UIKit
import Vision

// MARK: - 本地 OCR（Vision 系统框架，纯设备端，隐私优先）

/// 把一张小票图片识别成文本行。与 SpeechManager 同性质：调用 Apple 系统能力，
/// 不接本地模型、不上云。
enum ReceiptOCR {
    /// nonisolated：项目默认 MainActor 隔离，这里必须离开主线程，
    /// 否则 perform 的同步识别会卡住 UI（识别会跑在协作线程池里）。
    nonisolated static func recognize(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = image.cgOrientation
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                // boundingBox 原点在左下：maxY 越大越靠上 → 降序即「从上到下」
                let lines = observations
                    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            do {
                try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

private extension UIImage {
    /// UIImage.imageOrientation → CGImagePropertyOrientation，喂给 Vision 才不会识别歪。
    nonisolated var cgOrientation: CGImagePropertyOrientation {
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

// MARK: - 取图（拍照；模拟器或无相机时自动回退到相册）

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
