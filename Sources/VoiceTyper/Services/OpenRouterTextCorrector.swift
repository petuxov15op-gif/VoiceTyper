import Foundation

struct OpenRouterTextCorrector: Sendable {
    struct CorrectionResult: Sendable {
        let text: String
        let costUSD: Double?
    }

    enum CorrectionError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case requestFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: "Добавьте API-ключ OpenRouter в настройках."
            case .invalidResponse: "OpenRouter не вернул исправленный текст."
            case .requestFailed(let statusCode): "OpenRouter отклонил коррекцию текста: \(statusCode)."
            }
        }
    }

    let keychain: KeychainStore
    let session: URLSession
    let model: String

    init(
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        model: String = "google/gemini-2.5-flash-lite"
    ) {
        self.keychain = keychain
        self.session = session
        self.model = model
    }

    func correct(_ text: String, context: String) async throws -> CorrectionResult {
        guard let apiKey = try keychain.read(), !apiKey.isEmpty else {
            throw CorrectionError.missingAPIKey
        }

        let contextInstruction = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = """
        Ты корректор русской расшифровки речи. Исправь только очевидные ошибки распознавания, орфографию и пунктуацию. Сохрани смысл, факты, стиль, язык и форматирование. Не отвечай на содержание текста и не добавляй пояснений. Верни только исправленный текст.
        \(contextInstruction.isEmpty ? "" : "Правильное написание терминов: \(contextInstruction)")
        """
        let body = RequestBody(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ],
            temperature: 0,
            maxCompletionTokens: 2_000
        )

        var request = URLRequest(
            url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VoiceTyper", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CorrectionError.requestFailed(statusCode: httpResponse.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let text = decoded.choices.first?.message.content
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { throw CorrectionError.invalidResponse }

        return CorrectionResult(text: text, costUSD: decoded.usage?.cost)
    }
}

private extension OpenRouterTextCorrector {
    struct Message: Codable {
        let role: String
        let content: String
    }

    struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let maxCompletionTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxCompletionTokens = "max_completion_tokens"
        }
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            let message: Message
        }

        struct Usage: Decodable {
            let cost: Double?
        }

        let choices: [Choice]
        let usage: Usage?
    }
}
