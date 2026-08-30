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

                LabeledContent("Язык") {
                    Text("Русский")
                }

                TextField(
                    "Контекст распознавания",
                    text: $settings.recognitionContext,
                    prompt: Text("Имена, названия и специальные термины через запятую"),
                    axis: .vertical
                )
                .lineLimit(2...4)

                Text("Контекст помогает Whisper правильно писать редкие слова. Аудио в локальном режиме по-прежнему никуда не отправляется.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.recognizerMode == .localWhisper {
                    Text("Точная многоязычная модель Whisper Large V3 Turbo (~626 МБ) загрузится один раз, затем распознавание работает полностью локально.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }


                Toggle("Умная коррекция текста", isOn: $settings.smartCorrectionEnabled)
                    .disabled(settings.recognizerMode != .openRouter)

                Text(settings.recognizerMode == .openRouter
                     ? "После распознавания исправляет орфографию и пунктуацию через OpenRouter, не меняя смысл."
                     : "Доступна в режиме OpenRouter, поскольку коррекция использует сетевую модель.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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


                Picker("Устройство", selection: $settings.microphoneDeviceID) {
                    Text("Системный микрофон").tag(nil as UInt32?)
                    ForEach(appState.inputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }

                Toggle("Подавление шума и эха", isOn: $settings.voiceProcessingEnabled)

                Text("После отпускания клавиши VoiceTyper сохраняет короткое окончание записи, чтобы не обрезать последнее слово.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            appState.refreshInputDevices()
        }
    }
}
