import AppKit
import XCTest
@testable import VoiceTyper

final class ReliabilityTests: XCTestCase {
    func testCloudTranscriptRejectsSilence() throws {
        XCTAssertThrowsError(try OpenRouterRecognizer.validatedTranscript(" \n\t "))
        XCTAssertEqual(
            try OpenRouterRecognizer.validatedTranscript("  Привет, мир!\n"),
            "Привет, мир!"
        )
    }

    @MainActor
    func testInvalidPersistedMicrophoneDoesNotCrash() {
        let suite = "VoiceTyperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for value in [-1, Int.max] {
            defaults.set(value, forKey: "microphoneDeviceID")
            XCTAssertNil(AppSettings(defaults: defaults).microphoneDeviceID)
        }
        defaults.set(42, forKey: "microphoneDeviceID")
        XCTAssertEqual(AppSettings(defaults: defaults).microphoneDeviceID, 42)
    }

    @MainActor
    func testCancelledPermissionRequestCannotStartOrCancelNextRecording() async {
        var requests: [CheckedContinuation<Bool, Never>] = []
        let recorder = AudioRecorder(permissionRequest: {
            await withCheckedContinuation { requests.append($0) }
        })
        let first = Task {
            try await recorder.start(deviceID: nil, voiceProcessingEnabled: false)
        }
        while requests.count < 1 { await Task.yield() }
        recorder.cancel()

        let second = Task {
            try await recorder.start(deviceID: nil, voiceProcessingEnabled: false)
        }
        while requests.count < 2 { await Task.yield() }
        requests[0].resume(returning: true)
        do {
            try await first.value
            XCTFail("A cancelled request must not open the microphone")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentURL)

        requests[1].resume(returning: false)
        do {
            try await second.value
            XCTFail("Permission was denied")
        } catch AudioRecorder.RecorderError.permissionDenied {
            // The stale request did not invalidate this newer request.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testEmptyInsertionDoesNotReplaceClipboard() async {
        let changeCount = NSPasteboard.general.changeCount
        do {
            _ = try await TextInserter().insert(
                " \n", into: TextInsertionTarget(application: nil, focusedElement: nil)
            )
            XCTFail("Empty transcription must not be inserted")
        } catch {
            XCTAssertEqual(NSPasteboard.general.changeCount, changeCount)
        }
    }
}
