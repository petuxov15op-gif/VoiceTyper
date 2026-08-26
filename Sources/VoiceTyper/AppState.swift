import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Mode: Equatable {
        case ready
        case starting(ActionKind)
        case listening(ActionKind)
        case processing(ActionKind)
        case recorded(ActionKind)
        case result(ActionKind)
        case error(String)
    }

    enum ActionKind: String, Equatable {
        case dictation
        case assistant

        var title: String {
            switch self {
            case .dictation: "Диктовка"
            case .assistant: "Голосовой помощник"
            }
        }
    }

    @Published private(set) var mode: Mode = .ready
    @Published private(set) var shortcutError: String?
    @Published private(set) var microphonePermission: AudioRecorder.PermissionState
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastTranscript: String?
    @Published private(set) var lastCostUSD: Double?
    @Published private(set) var hasOpenRouterKey: Bool
    @Published private(set) var keychainMessage: String?
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published private(set) var insertionNotice: String?
    @Published private(set) var inputLevel: Float = 0

    let settings: AppSettings
    private let hotKeyManager: GlobalHotKeyManager
    private let audioRecorder: AudioRecorder
    private let keychain: KeychainStore
    private let localWhisperRecognizer: LocalWhisperRecognizer
    private let openRouterRecognizer: OpenRouterRecognizer
    private let textInserter: TextInserter
    private var isStartingRecording = false
    private var insertionTarget: TextInsertionTarget?
    private var recordingGeneration = 0
    private var shortcutPressTracker = ShortcutPressTracker()
    private var finishWhenRecordingStarts = false

    init(
        settings: AppSettings = AppSettings(),
        hotKeyManager: GlobalHotKeyManager = GlobalHotKeyManager(),
        audioRecorder: AudioRecorder = AudioRecorder(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.settings = settings
        self.hotKeyManager = hotKeyManager
        self.audioRecorder = audioRecorder
        self.keychain = keychain
        localWhisperRecognizer = LocalWhisperRecognizer()
        openRouterRecognizer = OpenRouterRecognizer(keychain: keychain)
        textInserter = TextInserter()
        microphonePermission = audioRecorder.permissionState
        hasOpenRouterKey = false
        hasAccessibilityPermission = textInserter.hasAccessibilityPermission
        registerShortcuts()
        Task {
            _ = await audioRecorder.requestPermission()
            microphonePermission = audioRecorder.permissionState
        }
        if !hasAccessibilityPermission {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                textInserter.promptForAccessibilityPermission()
                refreshAccessibilityPermission()
            }
        }
    }

    var statusTitle: String {
        switch mode {
        case .ready: "Готов к работе"
        case .starting(let action): "Включаю микрофон: \(action.title.lowercased())"
        case .listening(let action): "Слушаю: \(action.title.lowercased())"
        case .processing(let action): "Обрабатываю: \(action.title.lowercased())"
        case .recorded(let action): "Запись готова: \(action.title.lowercased())"
        case .result(let action): "Готово: \(action.title.lowercased())"
        case .error: "Нужна проверка"
        }
    }

    var statusSymbol: String {
        switch mode {
        case .ready: "waveform"
        case .starting: "mic.badge.plus"
        case .listening: "mic.fill"
        case .processing: "ellipsis.circle"
        case .recorded: "checkmark.circle.fill"
        case .result: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var isRecording: Bool {
        switch mode {
        case .starting, .listening:
            true
        default:
            false
        }
    }

    var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    func registerShortcuts() {
        do {
            try hotKeyManager.register(
                dictation: settings.dictationShortcut,
                assistant: settings.assistantShortcut
            ) { [weak self] action, phase in
                guard let self else { return }
                let kind: ActionKind = action == .dictation ? .dictation : .assistant
                switch phase {
                case .pressed:
                    self.shortcutPressed(kind)
                case .released:
                    self.shortcutReleased()
                }
            }
            shortcutError = nil
        } catch {
            shortcutError = error.localizedDescription
        }
    }

    func begin(_ action: ActionKind) {
        guard !audioRecorder.isRecording, !isStartingRecording else { return }
        recordingGeneration += 1
        let generation = recordingGeneration
        isStartingRecording = true
        insertionTarget = textInserter.captureTarget()
        insertionNotice = nil
        mode = .starting(action)
        RecordingOverlayController.shared.show(appState: self)
        removeLastRecording()
        Task {
            do {
                try await audioRecorder.start()
                guard recordingGeneration == generation else {
                    audioRecorder.cancel()
                    return
                }
                isStartingRecording = false
                microphonePermission = audioRecorder.permissionState
                mode = .listening(action)
                monitorRecording(generation: generation)

                if finishWhenRecordingStarts {
                    finishWhenRecordingStarts = false
                    finish()
                    return
                }

            } catch {
                isStartingRecording = false
                microphonePermission = audioRecorder.permissionState
                RecordingOverlayController.shared.hide()
                mode = .error(error.localizedDescription)
            }
        }
    }

    func finish() {
        guard case .listening(let action) = mode else { return }
        recordingGeneration += 1
        do {
            mode = .processing(action)
            RecordingOverlayController.shared.hide()
            inputLevel = 0
            lastRecordingURL = try audioRecorder.stop()
            switch settings.recognizerMode {
            case .localWhisper:
                transcribeLocally(action: action)
            case .openRouter:
                transcribeWithOpenRouter(action: action)
            }
        } catch {
            mode = .error(error.localizedDescription)
        }
    }

    func toggle(_ action: ActionKind) {
        if isStartingRecording {
            cancel()
        } else if audioRecorder.isRecording {
            finish()
        } else if case .processing = mode {
            return
        } else {
            begin(action)
        }
    }

    private func shortcutPressed(_ action: ActionKind) {
        // Carbon can repeat the pressed event while a key is held. Repeats must
        // never toggle recording off.
        guard shortcutPressTracker.press(at: ProcessInfo.processInfo.systemUptime) else { return }

        if isStartingRecording {
            finishWhenRecordingStarts = true
        } else if audioRecorder.isRecording {
            finish()
        } else if case .processing = mode {
            return
        } else {
            begin(action)
        }
    }

    private func shortcutReleased() {
        let release = shortcutPressTracker.release(at: ProcessInfo.processInfo.systemUptime)

        // A held shortcut is push-to-talk. A quick tap intentionally leaves
        // recording active so the next tap can finish it.
        guard release == .held else { return }
        if isStartingRecording {
            finishWhenRecordingStarts = true
        } else if audioRecorder.isRecording {
            finish()
        }
    }

    func requestMicrophonePermission() {
        Task {
            _ = await audioRecorder.requestPermission()
            microphonePermission = audioRecorder.permissionState
        }
    }

    func requestAccessibilityPermission() {
        textInserter.requestAccessibilityPermission()
        hasAccessibilityPermission = textInserter.hasAccessibilityPermission
    }

    func openAccessibilitySettings() {
        textInserter.openAccessibilitySettings()
    }

    func refreshAccessibilityPermission() {
        hasAccessibilityPermission = textInserter.hasAccessibilityPermission
    }

    func saveOpenRouterKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            keychainMessage = "Введите API-ключ."
            return
        }
        do {
            try keychain.save(trimmed)
            hasOpenRouterKey = true
            keychainMessage = "Ключ сохранён в Keychain."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    func refreshOpenRouterKeyStatus() {
        hasOpenRouterKey = (try? keychain.read())?.isEmpty == false
    }

    func deleteOpenRouterKey() {
        do {
            try keychain.delete()
            hasOpenRouterKey = false
            keychainMessage = "Ключ удалён."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    func cancel() {
        recordingGeneration += 1
        isStartingRecording = false
        finishWhenRecordingStarts = false
        shortcutPressTracker.reset()
        audioRecorder.cancel()
        RecordingOverlayController.shared.hide()
        inputLevel = 0
        mode = .ready
    }

    private func removeLastRecording() {
        if let lastRecordingURL {
            try? FileManager.default.removeItem(at: lastRecordingURL)
        }
        lastRecordingURL = nil
        lastTranscript = nil
        lastCostUSD = nil
    }

    private func transcribeWithOpenRouter(action: ActionKind) {
        guard let url = lastRecordingURL else { return }
        Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                if lastRecordingURL == url {
                    lastRecordingURL = nil
                }
            }
            do {
                let result = try await openRouterRecognizer.transcribe(
                    audioURL: url,
                    language: settings.languageCode
                )
                lastTranscript = result.text
                lastCostUSD = result.costUSD
                let insertion = try await textInserter.insert(
                    result.text,
                    into: insertionTarget ?? textInserter.captureTarget()
                )
                updateInsertionNotice(for: insertion)
                mode = .result(action)
            } catch {
                mode = .error(error.localizedDescription)
            }
        }
    }

    private func transcribeLocally(action: ActionKind) {
        guard let url = lastRecordingURL else { return }
        Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                if lastRecordingURL == url {
                    lastRecordingURL = nil
                }
            }
            do {
                let result = try await localWhisperRecognizer.transcribe(
                    audioURL: url,
                    language: settings.languageCode
                )
                lastTranscript = result.text
                lastCostUSD = nil
                let insertion = try await textInserter.insert(
                    result.text,
                    into: insertionTarget ?? textInserter.captureTarget()
                )
                updateInsertionNotice(for: insertion)
                mode = .result(action)
            } catch {
                mode = .error(error.localizedDescription)
            }
        }
    }

    private func updateInsertionNotice(for outcome: TextInsertionOutcome) {
        switch outcome {
        case .inserted:
            insertionNotice = nil
        case .copiedToClipboard:
            insertionNotice = "Текст распознан и скопирован. Для автоматической вставки разрешите VoiceTyper в «Универсальном доступе»."
        }
    }

    private func monitorRecording(generation: Int) {
        Task {
            while recordingGeneration == generation, audioRecorder.isRecording {
                inputLevel = audioRecorder.inputLevel

                try? await Task.sleep(for: .milliseconds(100))
            }
            if recordingGeneration == generation {
                inputLevel = 0
            }
        }
    }
}
