import Foundation
import Combine
import Speech
import AVFoundation
import SwiftUI

@MainActor
final class SpeechManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var authorized: Bool = false

    // locale 决定识别语言。v0 先定中文；中英混说是 v1 课题。
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in   // iOS 17+
                Task { @MainActor in
                    self.authorized = (speechStatus == .authorized) && micGranted
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true     // 流式上屏，响应快

            // ✅ 兑现“本地 / 零延迟 / 隐私”的承诺：强制本地识别（设备支持时）
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.teardown()
                    }
                }
            }
        } catch {
            teardown()
        }
    }

    /// 松手时调用，返回当前最终文本
    @discardableResult
    func stopRecording() -> String {
        let final = transcript
        teardown()
        return final
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
