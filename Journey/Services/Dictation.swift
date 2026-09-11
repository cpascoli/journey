// AVAudioConverter's input block is typed @Sendable but runs synchronously inside convert().
@preconcurrency import AVFoundation
import Foundation
import Speech

/// On-device dictation with iOS 26's SpeechAnalyzer. Finished phrases go to the
/// `onText` handler; the phrase still being spoken is published as `partialText`.
@Observable
final class Dictation {
    private(set) var isPreparing = false
    private(set) var isListening = false
    private(set) var partialText = ""
    private(set) var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?

    func start(language: String, onText: @escaping (String) -> Void) async {
        guard !isListening, !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw DictationError.microphoneDenied
            }
            await Self.requestSpeechAuthorizationIfNeeded()
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
                throw DictationError.unsupportedLanguage
            }
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            // The first use of a language downloads its speech model.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw DictationError.audioUnavailable
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            try Self.installTap(on: engine.inputNode, convertingTo: format, into: continuation)
            engine.prepare()
            try engine.start()

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            self?.partialText = ""
                            onText(text)
                        } else {
                            self?.partialText = text
                        }
                    }
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
            try await analyzer.start(inputSequence: stream)
            self.analyzer = analyzer
            self.input = continuation
            isListening = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            resultsTask?.cancel()
            resultsTask = nil
            tearDownAudio()
        }
    }

    func stop() async {
        guard isListening else { return }
        isListening = false
        tearDownAudio()
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        await resultsTask?.value
        resultsTask = nil
        partialText = ""
    }

    private func tearDownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Nonisolated so the tap block isn't main-actor: Core Audio calls it on its own thread.
    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        convertingTo format: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let inputFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw DictationError.audioUnavailable
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if let converted = Self.convert(buffer, with: converter, to: format) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }

    private nonisolated static func requestSpeechAuthorizationIfNeeded() async {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }
    }
}

nonisolated enum DictationError: LocalizedError {
    case microphoneDenied
    case unsupportedLanguage
    case audioUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Allow microphone access in Settings to dictate."
        case .unsupportedLanguage: "Dictation isn't available in this language."
        case .audioUnavailable: "The microphone isn't available right now."
        }
    }
}
