import AppKit

/// Spotify and Apple Music through the notifications they broadcast on every change
/// and AppleScript for the controls and the artwork. Neither app is ever launched by Isla.
@MainActor
final class MusicController {
    static let shared = MusicController()

    private let players = [
        (app: "Spotify", bundle: "com.spotify.client", note: "com.spotify.client.PlaybackStateChanged"),
        (app: "Music", bundle: "com.apple.Music", note: "com.apple.Music.playerInfo"),
    ]
    private let scriptQueue = DispatchQueue(label: "isla.applescript")
    private var lastArtworkTrack = ""

    func start() {
        for p in players {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(p.note), object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.received(player: p.app, info: info) }
            }
        }
        refresh()
    }

    private func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    private func received(player: String, info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if IslaModel.shared.nowPlaying?.player == player { IslaModel.shared.nowPlaying = nil }
            return
        }
        let np = NowPlaying(player: player,
                            title: info["Name"] as? String ?? "",
                            artist: info["Artist"] as? String ?? "",
                            isPlaying: state == "Playing",
                            artworkURL: nil)
        // A paused player never replaces another one that is playing.
        if let cur = IslaModel.shared.nowPlaying, cur.player != player, cur.isPlaying, !np.isPlaying { return }
        IslaModel.shared.nowPlaying = np
        loadArtwork(player: player, track: np.title + np.artist)
    }

    /// Reads the current track once at launch (only from players already open).
    func refresh() {
        for p in players where isRunning(p.bundle) {
            let script = """
            tell application "\(p.app)"
              if player state is stopped then return ""
              return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as text)
            end tell
            """
            run(script) { [weak self] out in
                guard let out, !out.isEmpty else { return }
                let parts = out.components(separatedBy: "\n")
                guard parts.count >= 3 else { return }
                self?.received(player: p.app, info: ["Name": parts[0], "Artist": parts[1],
                                                    "Player State": parts[2] == "playing" ? "Playing" : "Paused"])
            }
        }
    }

    private func loadArtwork(player: String, track: String) {
        guard track != lastArtworkTrack else { return }
        lastArtworkTrack = track
        IslaModel.shared.artwork = nil
        if player == "Spotify" {
            run("tell application \"Spotify\" to return artwork url of current track") { out in
                guard let out, let url = URL(string: out) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async { IslaModel.shared.artwork = img }
                }.resume()
            }
        } else {
            let tmp = HookServer.supportDir.appendingPathComponent("artwork.jpg").path
            let script = """
            tell application "Music"
              set d to raw data of artwork 1 of current track
              set f to open for access (POSIX file "\(tmp)") with write permission
              set eof f to 0
              write d to f
              close access f
            end tell
            return "ok"
            """
            run(script) { out in
                guard out == "ok", let img = NSImage(contentsOfFile: tmp) else { return }
                IslaModel.shared.artwork = img
            }
        }
    }

    // MARK: - Controls

    private var activePlayer: String? {
        if let p = IslaModel.shared.nowPlaying?.player { return p }
        return players.first { isRunning($0.bundle) }?.app
    }

    private func send(_ command: String) {
        guard let app = activePlayer, let p = players.first(where: { $0.app == app }), isRunning(p.bundle) else { return }
        run("tell application \"\(app)\" to \(command)") { _ in }
    }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    /// Runs AppleScript off the main thread and hands the text result back on it.
    private func run(_ source: String, completion: @escaping @MainActor (String?) -> Void) {
        scriptQueue.async {
            var err: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(out) } }
        }
    }
}
