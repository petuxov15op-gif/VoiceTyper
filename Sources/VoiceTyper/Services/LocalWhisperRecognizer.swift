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

    init(modelName: String = "small") {
        self.modelName = modelName
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
