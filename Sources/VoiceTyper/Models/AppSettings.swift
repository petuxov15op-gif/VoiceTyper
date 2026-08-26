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

    @Published var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Keys.languageCode) }
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
        languageCode = defaults.string(forKey: Keys.languageCode) ?? "ru"
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
        static let languageCode = "languageCode"
    }
}
