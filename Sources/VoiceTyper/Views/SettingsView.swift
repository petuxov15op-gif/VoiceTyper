import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: AppSettings
    @State private var openRouterKey = ""

    var body: some View {
        Form {
            Section("Сочетания клавиш") {
                LabeledContent("Диктовка") {
                    ShortcutRecorderView(shortcut: $settings.dictationShortcut)
                }

                LabeledContent("Голосовой помощник") {
                    ShortcutRecorderView(shortcut: $settings.assistantShortcut)
                }

                Text("Нажмите на сочетание, затем введите новое. Для отмены нажмите Esc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.hasShortcutConflict {
                    Label(
                        "Назначьте разные сочетания для диктовки и помощника.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section("Распознавание") {
                Picker("Режим", selection: $settings.recognizerMode) {
                    ForEach(AppSettings.RecognizerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Язык", selection: $settings.languageCode) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                    Text("Автоопределение").tag("auto")
                }

                if settings.recognizerMode == .localWhisper {
                    Text("Быстрая многоязычная модель Whisper Base загрузится один раз, затем распознавание работает полностью локально.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.recognizerMode == .openRouter {
                Section("OpenRouter") {
                    SecureField("API-ключ", text: $openRouterKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Вставьте ключ OpenRouter — после этого кнопка сохранения станет активной.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Сохранить ключ") {
                            appState.saveOpenRouterKey(openRouterKey)
                            openRouterKey = ""
                        }
                        .disabled(openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if appState.hasOpenRouterKey {
                            Button("Удалить ключ", role: .destructive) {
                                appState.deleteOpenRouterKey()
                            }
                        }
                    }

                    Label(
                        appState.hasOpenRouterKey ? "Ключ сохранён в Keychain" : "Ключ не добавлен",
                        systemImage: appState.hasOpenRouterKey ? "checkmark.shield" : "key"
                    )
                    .foregroundStyle(appState.hasOpenRouterKey ? .green : .secondary)

                    if let message = appState.keychainMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Микрофон") {
                LabeledContent("Состояние") {
                    Text(appState.microphonePermission.title)
                }

                if appState.microphonePermission != .granted {
                    Button("Запросить доступ") {
                        appState.requestMicrophonePermission()
                    }
                }
            }

            Section("Вставка текста") {
                LabeledContent("Универсальный доступ") {
                    Text(appState.hasAccessibilityPermission ? "Разрешён" : "Не разрешён")
                        .foregroundStyle(appState.hasAccessibilityPermission ? .green : .red)
                }

                Text("Нужен, чтобы VoiceTyper мог вставить распознанный текст в поле с курсором другого приложения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !appState.hasAccessibilityPermission {
                    Text("Включите переключатель у этой копии приложения:")
                        .font(.caption)
                    Text(appState.appBundlePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Открыть «Универсальный доступ»") {
                            appState.openAccessibilitySettings()
                        }
                        Button("Проверить ещё раз") {
                            appState.refreshAccessibilityPermission()
                        }
                    }

                    Button("Запросить разрешение macOS") {
                        appState.requestAccessibilityPermission()
                    }
                }
            }

            Section {
                Button("Применить сочетания") {
                    appState.registerShortcuts()
                }
                .disabled(settings.hasShortcutConflict)

                if let error = appState.shortcutError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 520)
        .onAppear {
            appState.refreshOpenRouterKeyStatus()
            appState.refreshAccessibilityPermission()
        }
    }
}
