import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class AudioRecorder {
    struct InputDevice: Identifiable, Equatable, Sendable {
        let id: AudioDeviceID
        let name: String
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case invalidInputFormat
        case notRecording
        case deviceUnavailable
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Нет доступа к микрофону. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Микрофон."
            case .invalidInputFormat:
                "Не удалось получить поддерживаемый формат микрофона."
            case .notRecording:
                "Запись ещё не запущена."
            case .deviceUnavailable:
                "Не удалось подключить выбранный микрофон. Выберите системный микрофон или другое устройство."
            case .writeFailed(let message):
                "Не удалось записать звук: \(message)"
            }
        }
    }

    enum PermissionState: Equatable {
        case notDetermined
        case granted
        case denied

        var title: String {
            switch self {
            case .notDetermined: "Доступ ещё не запрошен"
            case .granted: "Доступ разрешён"
            case .denied: "Доступ запрещён"
            }
        }
    }

    private var engine: AVAudioEngine?
    private var sink: AudioFileSink?
    private(set) var currentURL: URL?

    var permissionState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    var isRecording: Bool { engine?.isRunning == true }
    var inputLevel: Float { sink?.currentInputLevel() ?? 0 }

    func requestPermission() async -> Bool {
        switch permissionState {
        case .granted: true
        case .denied: false
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    func start(deviceID: AudioDeviceID?, voiceProcessingEnabled: Bool) async throws {
        guard engine?.isRunning != true else { return }
        guard await requestPermission() else { throw RecorderError.permissionDenied }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceID {
            guard let audioUnit = input.audioUnit else { throw RecorderError.deviceUnavailable }
            var selectedDeviceID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &selectedDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw RecorderError.deviceUnavailable }
        }
        if voiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.invalidInputFormat
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTyper-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let sink = AudioFileSink(file: file)

        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format,
            block: Self.makeTapBlock(sink: sink)
        )

        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.sink = sink
            currentURL = url
        } catch {
            input.removeTap(onBus: 0)
            engine.reset()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func availableInputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard Self.inputChannelCount(for: deviceID) > 0,
                  let name = Self.deviceName(for: deviceID)
            else { return nil }
            return InputDevice(id: deviceID, name: name)
        }
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr
        else { return 0 }
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawBuffer) == noErr
        else { return 0 }
        let list = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name) == noErr,
              let name
        else { return nil }
        return name.takeRetainedValue() as String
    }

    func stop() throws -> URL {
        guard let engine, engine.isRunning, let currentURL else {
            throw RecorderError.notRecording
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        self.engine = nil
        if let writeError = sink?.finish() {
            sink = nil
            self.currentURL = nil
            try? FileManager.default.removeItem(at: currentURL)
            throw RecorderError.writeFailed(writeError.localizedDescription)
        }
        sink = nil
        self.currentURL = nil
        return currentURL
    }

    func cancel() {
        if let engine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        engine = nil
        _ = sink?.finish()
        sink = nil
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        currentURL = nil
    }

    nonisolated private static func makeTapBlock(
        sink: AudioFileSink
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.write(buffer)
        }
    }
}

private final class AudioFileSink: @unchecked Sendable {
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var writeError: Error?
    private var inputLevel: Float = 0

    init(file: AVAudioFile) {
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard writeError == nil, let file else { return }
        do {
            try file.write(from: buffer)
            let level = Self.level(in: buffer)
            inputLevel = level
        } catch {
            writeError = error
        }
    }

    func finish() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        return writeError
    }

    func currentInputLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return inputLevel
    }

    private static func level(in buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let samplesPerChannel = buffer.format.isInterleaved ? frames * channelCount : frames
        let buffersCount = buffer.format.isInterleaved ? 1 : channelCount
        var sum: Double = 0

        func addSamples<T: BinaryFloatingPoint>(_ samples: UnsafePointer<T>, scale: Double) {
            for index in 0..<samplesPerChannel {
                let value = Double(samples[index]) * scale
                sum += value * value
            }
        }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else { return 0 }
            for channel in 0..<buffersCount { addSamples(channels[channel], scale: 1) }
        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else { return 0 }
            for channel in 0..<buffersCount {
                for index in 0..<samplesPerChannel {
                    let value = Double(channels[channel][index]) / Double(Int16.max)
                    sum += value * value
                }
            }
        case .pcmFormatInt32:
            guard let channels = buffer.int32ChannelData else { return 0 }
            for channel in 0..<buffersCount {
                for index in 0..<samplesPerChannel {
                    let value = Double(channels[channel][index]) / Double(Int32.max)
                    sum += value * value
                }
            }
        default:
            return 0
        }

        let sampleCount = max(1, samplesPerChannel * buffersCount)
        return min(1, Float(sqrt(sum / Double(sampleCount)) * 8))
    }
}
