import AppKit
import Foundation

/// Temporarily pauses Spotify while VoiceTyper records. It never launches Spotify
/// and resumes playback only when VoiceTyper paused it itself.
@MainActor
final class SpotifyPlaybackController {
    private let spotifyBundleIdentifier = "com.spotify.client"

    func pauseIfPlaying() -> Bool {
        guard isSpotifyRunning else { return false }

        let state = run(script: """
        tell application id "com.spotify.client"
            if player state is playing then
                pause
                return "paused"
            end if
            return "notPlaying"
        end tell
        """)
        return state == "paused"
    }

    func resume() {
        guard isSpotifyRunning else { return }
        _ = run(script: """
        tell application id "com.spotify.client"
            play
        end tell
        """)
    }

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: spotifyBundleIdentifier
        ).isEmpty
    }

    private func run(script source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }
}
