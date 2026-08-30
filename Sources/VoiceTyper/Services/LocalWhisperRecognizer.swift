import Foundation
import WhisperKit

actor LocalWhisperRecognizer: SpeechRecognizer {
    enum LocalWhisperError: LocalizedError {
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .emptyResult:
                "Локальный Whisper не распознал речь. Попробуйте говорить ближе к микрофону."
            }
        }
    }

    private let modelName: String
    private var whisperKit: WhisperKit?

    /// A Core ML conversion of Whisper Large V3 Turbo. It balances substantially
    /// better multilingual accuracy than Base with practical on-device speed.
    init(modelName: String = "large-v3-v20240930_626MB") {
        self.modelName = modelName
    }

    func preload() async throws {
        _ = try await loadWhisperKit()
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        let whisperKit = try await loadWhisperKit()
        let isAutomaticLanguage = language == "auto"
        let options = DecodingOptions(
            language: isAutomaticLanguage ? nil : language,
            usePrefillPrompt: !isAutomaticLanguage,
            detectLanguage: isAutomaticLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw LocalWhisperError.emptyResult
        }
        return TranscriptionResult(text: text, costUSD: nil)
    }

    private func loadWhisperKit() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        let configuration = WhisperKitConfig(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        let whisperKit = try await WhisperKit(configuration)
        self.whisperKit = whisperKit
        return whisperKit
    }
}
