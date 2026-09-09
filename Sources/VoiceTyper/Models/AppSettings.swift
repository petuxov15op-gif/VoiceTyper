import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var dictationShortcut: KeyboardShortcut {
        didSet { save(dictationShortcut, key: Keys.dictationShortcut) }
    }

    @Published var assistantShortcut: KeyboardShortcut {
        didSet { save(assistantShortcut, key: Keys.assistantShortcut) }
    }

    @Published var recognizerMode: RecognizerMode {
        didSet { defaults.set(recognizerMode.rawValue, forKey: Keys.recognizerMode) }
    }

    @Published var recognitionContext: String {
        didSet { defaults.set(recognitionContext, forKey: Keys.recognitionContext) }
    }

    @Published var smartCorrectionEnabled: Bool {
        didSet { defaults.set(smartCorrectionEnabled, forKey: Keys.smartCorrectionEnabled) }
    }

    @Published var microphoneDeviceID: UInt32? {
        didSet {
            if let microphoneDeviceID {
                defaults.set(Int(microphoneDeviceID), forKey: Keys.microphoneDeviceID)
            } else {
                defaults.removeObject(forKey: Keys.microphoneDeviceID)
            }
        }
    }

    @Published var voiceProcessingEnabled: Bool {
        didSet { defaults.set(voiceProcessingEnabled, forKey: Keys.voiceProcessingEnabled) }
    }

    private let defaults: UserDefaults

    enum RecognizerMode: String, CaseIterable, Identifiable, Sendable {
        case localWhisper
        case openRouter

        var id: Self { self }
        var title: String {
            switch self {
            case .localWhisper: "Локальный Whisper"
            case .openRouter: "OpenRouter"
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dictationShortcut = Self.loadShortcut(
            defaults: defaults,
            key: Keys.dictationShortcut,
            fallback: .defaultDictation
        )
        assistantShortcut = Self.loadShortcut(
            defaults: defaults,
            key: Keys.assistantShortcut,
            fallback: .defaultAssistant
        )
        recognizerMode = RecognizerMode(
            rawValue: defaults.string(forKey: Keys.recognizerMode) ?? ""
        ) ?? .localWhisper
        recognitionContext = defaults.string(forKey: Keys.recognitionContext) ?? ""
        smartCorrectionEnabled = defaults.object(forKey: Keys.smartCorrectionEnabled) as? Bool ?? false
        if defaults.object(forKey: Keys.microphoneDeviceID) != nil {
            microphoneDeviceID = UInt32(exactly: defaults.integer(forKey: Keys.microphoneDeviceID))
        } else {
            microphoneDeviceID = nil
        }
        voiceProcessingEnabled = defaults.object(forKey: Keys.voiceProcessingEnabled) as? Bool ?? true
    }

    var hasShortcutConflict: Bool {
        dictationShortcut == assistantShortcut
    }

    private func save(_ shortcut: KeyboardShortcut, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadShortcut(
        defaults: UserDefaults,
        key: String,
        fallback: KeyboardShortcut
    ) -> KeyboardShortcut {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else { return fallback }
        return value
    }

    private enum Keys {
        static let dictationShortcut = "dictationShortcut"
        static let assistantShortcut = "assistantShortcut"
        static let recognizerMode = "recognizerMode"
        static let recognitionContext = "recognitionContext"
        static let smartCorrectionEnabled = "smartCorrectionEnabled"
        static let microphoneDeviceID = "microphoneDeviceID"
        static let voiceProcessingEnabled = "voiceProcessingEnabled"
    }
}
