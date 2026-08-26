import Carbon
import Combine
import XCTest
@testable import VoiceTyper

final class KeyboardShortcutTests: XCTestCase {
    func testShortcutRoundTrip() throws {
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey)
        )

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)

        XCTAssertEqual(decoded, shortcut)
        XCTAssertEqual(decoded.displayName, "⌃⌥V")
    }

    func testShortcutPressTrackerIgnoresAutoRepeatAndDetectsHold() {
        var tracker = ShortcutPressTracker(holdThreshold: 0.35)

        XCTAssertTrue(tracker.press(at: 10))
        XCTAssertFalse(tracker.press(at: 10.2))
        XCTAssertEqual(tracker.release(at: 10.5), .held)
        XCTAssertNil(tracker.release(at: 10.6))
    }

    func testShortcutPressTrackerKeepsQuickTapDistinct() {
        var tracker = ShortcutPressTracker(holdThreshold: 0.35)

        XCTAssertTrue(tracker.press(at: 20))
        XCTAssertEqual(tracker.release(at: 20.1), .quickTap)
        XCTAssertTrue(tracker.press(at: 21))
    }

    @MainActor
    func testDefaultShortcutsDoNotConflict() {
        let suiteName = "VoiceTyperTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.hasShortcutConflict)
    }

    @MainActor
    func testRecognizerModePublishesAndChanges() {
        let suiteName = "VoiceTyperTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let published = expectation(description: "Settings publishes mode change")
        var cancellable: AnyCancellable?
        cancellable = settings.objectWillChange.sink { published.fulfill() }

        settings.recognizerMode = .openRouter

        wait(for: [published], timeout: 1)
        XCTAssertEqual(settings.recognizerMode, .openRouter)
        XCTAssertEqual(defaults.string(forKey: "recognizerMode"), "openRouter")
        cancellable?.cancel()
    }

    func testKeychainRoundTrip() throws {
        let identifier = UUID().uuidString
        let store = KeychainStore(
            service: "local.voicetyper.tests.\(identifier)",
            account: "temporary-test-key"
        )
        defer { try? store.delete() }

        XCTAssertNil(try store.read())
        try store.save("test-secret")
        XCTAssertEqual(try store.read(), "test-secret")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testOpenRouterTranscriptionWhenAudioIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOICETYPER_OPENROUTER_AUDIO"]
        else {
            throw XCTSkip("Set VOICETYPER_OPENROUTER_AUDIO to run the live integration test.")
        }

        let model = ProcessInfo.processInfo.environment["VOICETYPER_OPENROUTER_MODEL"]
            ?? "openai/whisper-large-v3"
        let result = try await OpenRouterRecognizer(model: model).transcribe(
            audioURL: URL(fileURLWithPath: path),
            language: "ru"
        )

        XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let expectedWords = ProcessInfo.processInfo.environment["VOICETYPER_EXPECTED_WORDS"] {
            let transcription = result.text.lowercased()
            for word in expectedWords.lowercased().split(whereSeparator: { $0.isWhitespace }) {
                XCTAssertTrue(transcription.contains(word), "Transcription '\(result.text)' is missing '\(word)'.")
            }
        }
    }

    func testLocalWhisperTranscriptionWhenAudioIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOICETYPER_LOCAL_WHISPER_AUDIO"]
        else {
            throw XCTSkip("Set VOICETYPER_LOCAL_WHISPER_AUDIO to run the local integration test.")
        }

        let recognizer = LocalWhisperRecognizer()
        let firstResult = try await recognizer.transcribe(
            audioURL: URL(fileURLWithPath: path),
            language: "ru"
        )
        let secondResult = try await recognizer.transcribe(
            audioURL: URL(fileURLWithPath: path),
            language: "ru"
        )

        XCTAssertFalse(firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(secondResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let expectedWords = ProcessInfo.processInfo.environment["VOICETYPER_EXPECTED_WORDS"] {
            let expected = expectedWords
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
            let firstText = firstResult.text.lowercased()
            let secondText = secondResult.text.lowercased()

            for word in expected {
                XCTAssertTrue(firstText.contains(word), "First transcription '\(firstResult.text)' is missing '\(word)'.")
                XCTAssertTrue(secondText.contains(word), "Second transcription '\(secondResult.text)' is missing '\(word)'.")
            }
        }
        XCTAssertNil(firstResult.costUSD)
        XCTAssertNil(secondResult.costUSD)
    }
}
