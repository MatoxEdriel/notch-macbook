import AppKit
import ImageIO
import SwiftUI

enum PlayerSource: String, CaseIterable, Sendable {
    case music = "Music"
    case spotify = "Spotify"

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}

struct TrackSnapshot: Sendable, Equatable {
    var source: PlayerSource
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var artworkURL: String?

    var key: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }
}

final class ScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notchbar.applescript", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    private func execute(_ source: String, cached: Bool) -> NSAppleEventDescriptor? {
        let script: NSAppleScript?
        if cached {
            if let s = cache[source] { script = s } else {
                script = NSAppleScript(source: source)
                cache[source] = script
            }
        } else {
            script = NSAppleScript(source: source)
        }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    func command(_ source: String) {
        queue.async { _ = self.execute(source, cached: false) }
    }

    func fetch(_ sources: [PlayerSource], completion: @escaping @Sendable ([TrackSnapshot]) -> Void) {
        queue.async {
            let snaps = sources.compactMap { src -> TrackSnapshot? in
                guard let d = self.execute(Self.stateScript(for: src), cached: true) else { return nil }
                return Self.parse(d, source: src)
            }
            completion(snaps)
        }
    }

    func fetchMusicArtwork(completion: @escaping @Sendable (Data?) -> Void) {
        queue.async {
            let script = """
            tell application "Music"
                try
                    return raw data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            """
            let d = self.execute(script, cached: true)
            completion(d?.descriptorType == typeUnicodeText ? nil : d?.data)
        }
    }

    private static func stateScript(for src: PlayerSource) -> String {
        let durationExpr = src == .spotify ? "(duration of t) / 1000" : "duration of t"
        let artworkExpr = src == .spotify ? "artwork url of t" : "\"\""
        return """
        tell application "\(src.rawValue)"
            try
                if player state is stopped then return {"stopped"}
                set t to current track
                if player state is playing then
                    set s to "playing"
                else
                    set s to "paused"
                end if
                return {s, name of t, artist of t, album of t, \(durationExpr), player position, \(artworkExpr)}
            on error
                return {"stopped"}
            end try
        end tell
        """
    }

    private static func parse(_ d: NSAppleEventDescriptor, source: PlayerSource) -> TrackSnapshot? {
        guard d.numberOfItems >= 6, let state = d.atIndex(1)?.stringValue, state != "stopped" else { return nil }
        let title = d.atIndex(2)?.stringValue ?? ""
        guard !title.isEmpty else { return nil }
        let art = d.numberOfItems >= 7 ? d.atIndex(7)?.stringValue : nil
        return TrackSnapshot(
            source: source,
            isPlaying: state == "playing",
            title: title,
            artist: d.atIndex(3)?.stringValue ?? "",
            album: d.atIndex(4)?.stringValue ?? "",
            duration: d.atIndex(5)?.doubleValue ?? 0,
            position: d.atIndex(6)?.doubleValue ?? 0,
            artworkURL: (art?.isEmpty ?? true) ? nil : art)
    }
}

@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var source: PlayerSource?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color = .white
    @Published private(set) var backgroundTint: Color = .black
    @Published var scrubPosition: Double?

    private var position: Double = 0
    private var positionDate = Date()
    private var trackKey = ""
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private let runner = ScriptRunner()

    var hasTrack: Bool { !title.isEmpty }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            dnc.addObserver(self, selector: #selector(playerChanged), name: .init(name), object: nil)
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wnc.addObserver(self, selector: #selector(appLaunchedOrQuit(_:)), name: name, object: nil)
        }
        refresh()
    }

    @objc private func appLaunchedOrQuit(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let id = app?.bundleIdentifier, PlayerSource.allCases.contains(where: { $0.bundleID == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    private func updateTimer(anyRunning: Bool) {
        let interval: TimeInterval? = !anyRunning ? nil : (isPlaying ? 4 : 10)
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.invalidate()
        timer = nil
        guard let interval else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func playerChanged() { refresh() }

    func refresh() {
        let running = PlayerSource.allCases.filter(\.isRunning)
        guard !running.isEmpty else { apply(nil); updateTimer(anyRunning: false); return }
        runner.fetch(running) { [weak self] snaps in
            DispatchQueue.main.async {
                self?.choose(from: snaps)
                self?.updateTimer(anyRunning: true)
            }
        }
    }

    private func choose(from snaps: [TrackSnapshot]) {
        let pick = snaps.first(where: \.isPlaying)
            ?? snaps.first(where: { $0.source == source })
            ?? snaps.first
        apply(pick)
    }

    private func apply(_ s: TrackSnapshot?) {
        guard let s else {
            if hasTrack {
                source = nil; title = ""; artist = ""; album = ""
                isPlaying = false; duration = 0; artwork = nil; trackKey = ""
                accentColor = .white
                backgroundTint = .black
            }
            return
        }
        source = s.source
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if album != s.album { album = s.album }
        if isPlaying != s.isPlaying { isPlaying = s.isPlaying }
        if duration != s.duration { duration = s.duration }
        position = s.position
        positionDate = Date()

        if s.key != trackKey {
            trackKey = s.key
            loadArtwork(for: s)
        }
    }

    private func loadArtwork(for s: TrackSnapshot) {
        let key = s.key
        let handle: @Sendable (Data?) -> Void = { [weak self] data in
            let palette = data.flatMap(ArtworkPalette.extract(from:))
            DispatchQueue.main.async {
                guard let self, self.trackKey == key else { return }
                self.artwork = data.flatMap(NSImage.init(data:))
                self.accentColor = palette?.accent ?? .white
                self.backgroundTint = palette?.background ?? .black
            }
        }
        switch s.source {
        case .music:
            runner.fetchMusicArtwork(completion: handle)
        case .spotify:
            guard let str = s.artworkURL, let url = URL(string: str) else { handle(nil); return }
            URLSession.shared.dataTask(with: url) { data, _, _ in handle(data) }.resume()
        }
    }

    func elapsed(at date: Date) -> Double {
        let p = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return min(max(p, 0), duration > 0 ? duration : p)
    }


    func playPause() {
        send("playpause")
        position = elapsed(at: Date()); positionDate = Date()
        isPlaying.toggle()
        updateTimer(anyRunning: true)
    }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        position = seconds; positionDate = Date()
        objectWillChange.send()
        send("set player position to \(Int(seconds))")
    }

    func open(_ app: PlayerSource) {
        guard let url = app.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ cmd: String) {
        guard let source else { return }
        runner.command("tell application \"\(source.rawValue)\" to \(cmd)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }
}

struct ArtworkPalette: Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static func extract(from data: Data) -> ArtworkPalette? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }

        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }

        let bins = 18
        var weight = [Double](repeating: 0, count: bins)
        var sumR = weight, sumG = weight, sumB = weight
        var totR = 0.0, totG = 0.0, totB = 0.0

        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            totR += r; totG += g; totB += b
            let mx = max(r, g, b), mn = min(r, g, b), delta = mx - mn
            let sat = mx == 0 ? 0 : delta / mx
            guard sat > 0.25, mx > 0.2 else { continue }
            var hue: Double
            if mx == r { hue = (g - b) / delta }
            else if mx == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
            let bin = min(Int(hue * Double(bins)), bins - 1)
            let w = sat * mx
            weight[bin] += w; sumR[bin] += r * w; sumG[bin] += g * w; sumB[bin] += b * w
        }

        let score = (0..<bins).map { weight[($0 + bins - 1) % bins] + weight[$0] * 2 + weight[($0 + 1) % bins] }
        let pixels = Double(side * side)
        if let best = score.indices.max(by: { score[$0] < score[$1] }), weight[best] > pixels * 0.02 {
            let w = weight[best]
            return ArtworkPalette(red: sumR[best] / w, green: sumG[best] / w, blue: sumB[best] / w)
        }
        return ArtworkPalette(red: totR / pixels, green: totG / pixels, blue: totB / pixels)
    }

    private var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    var background: Color {
        let (h, s, _) = hsb
        let neutral = s < 0.15
        return Color(nsColor: NSColor(hue: h, saturation: min(s, 0.85),
                                      brightness: neutral ? 0.25 : 0.45, alpha: 1))
    }

    var accent: Color {
        let (h, s, b) = hsb
        return Color(nsColor: NSColor(hue: h, saturation: min(s, 0.7),
                                      brightness: max(b, 0.85), alpha: 1))
    }
}
