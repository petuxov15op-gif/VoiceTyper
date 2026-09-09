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
    private var loadingTask: Task<Void, Error>?

    /// A Core ML conversion of Whisper Large V3 Turbo. It balances substantially
    /// better multilingual accuracy than Base with practical on-device speed.
    init(modelName: String = "large-v3-v20240930_626MB") {
        self.modelName = modelName
    }

    func preload() async throws {
        _ = try await loadWhisperKit()
    }

    func transcribe(
        audioURL: URL,
        language: String,
        context: String
    ) async throws -> TranscriptionResult {
        let whisperKit = try await loadWhisperKit()
        try Task.checkCancellation()
        let isAutomaticLanguage = language == "auto"
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptTokens = trimmedContext.isEmpty
            ? nil
            : whisperKit.tokenizer?.encode(text: " " + trimmedContext)
        let options = DecodingOptions(
            language: isAutomaticLanguage ? nil : language,
            usePrefillPrompt: !isAutomaticLanguage,
            detectLanguage: isAutomaticLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens
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
        if let loadingTask {
            try await loadingTask.value
            return try await loadWhisperKit()
        }

        let configuration = WhisperKitConfig(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        // Keep the non-Sendable pipeline inside this actor; waiters only await completion.
        let task = Task { self.whisperKit = try await WhisperKit(configuration) }
        loadingTask = task
        defer { loadingTask = nil }
        try await task.value
        return try await loadWhisperKit()
    }
}
