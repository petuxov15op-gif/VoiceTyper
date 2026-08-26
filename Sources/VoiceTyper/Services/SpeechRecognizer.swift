import Foundation

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let costUSD: Double?
}
protocol SpeechRecognizer: Sendable {
    func transcribe(
        audioURL: URL,
        language: String
    ) async throws -> TranscriptionResult
}
