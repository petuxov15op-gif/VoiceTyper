import Foundation

struct OpenRouterRecognizer: SpeechRecognizer {
    enum RecognizerError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Добавьте API-ключ OpenRouter в настройках."
            case .invalidResponse:
                "OpenRouter вернул ответ неизвестного формата."
            case .requestFailed(let statusCode, let message):
                "Ошибка OpenRouter \(statusCode): \(message)"
            }
        }
    }

    let keychain: KeychainStore
    let session: URLSession
    let model: String

    init(
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        model: String = "openai/whisper-large-v3"
    ) {
        self.keychain = keychain
        self.session = session
        self.model = model
    }

    func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
        guard let apiKey = try keychain.read(), !apiKey.isEmpty else {
            throw RecognizerError.missingAPIKey
        }

        let audioData = try Data(contentsOf: audioURL)
        let requestBody = TranscriptionRequest(
            model: model,
            inputAudio: .init(
                data: audioData.base64EncodedString(),
                format: audioURL.pathExtension.lowercased()
            ),
            language: language == "auto" ? nil : language,
            temperature: 0
        )

        var request = URLRequest(
            url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VoiceTyper", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecognizerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let rawMessage = String(data: data, encoding: .utf8)
            throw RecognizerError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: error?.error.detailedMessage
                    ?? rawMessage.map { String($0.prefix(1_000)) }
                    ?? "запрос отклонён"
            )
        }

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw RecognizerError.invalidResponse
        }
        return TranscriptionResult(text: decoded.text, costUSD: decoded.usage?.cost)
    }

}

private extension OpenRouterRecognizer {
    struct ResponseBody: Decodable {
        struct Usage: Decodable {
            let cost: Double?
        }

        let text: String
        let usage: Usage?
    }

    struct TranscriptionRequest: Encodable {
        struct InputAudio: Encodable {
            let data: String
            let format: String

            enum CodingKeys: String, CodingKey {
                case data
                case format
            }
        }

        let model: String
        let inputAudio: InputAudio
        let language: String?
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case model
            case inputAudio = "input_audio"
            case language
            case temperature
        }
    }

    struct ErrorResponse: Decodable {
        struct Details: Decodable {
            let message: String
            let metadata: Metadata?

            var detailedMessage: String {
                guard let providerError = metadata?.raw else { return message }
                return "\(message): \(providerError)"
            }
        }

        struct Metadata: Decodable {
            let raw: String?

            enum CodingKeys: String, CodingKey {
                case raw = "raw"
            }
        }

        let error: Details
    }
}
