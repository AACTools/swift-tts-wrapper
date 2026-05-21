import Foundation
import AVFoundation

/// Helper player that wraps AVAudioPlayer to manage playback states, pausing, and boundary events.
public final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var boundaries: [WordBoundary] = []
    private var firedIndices = Set<Int>()

    public var onStart: (() -> Void)?
    public var onEnd: (() -> Void)?
    public var onBoundary: ((WordBoundary) -> Void)?
    public var onError: ((Error) -> Void)?

    public override init() {
        super.init()
    }

    /// Plays synthesized audio from a raw Data buffer.
    public func play(data: Data, boundaries: [WordBoundary] = []) throws {
        stop()
        self.boundaries = boundaries
        self.firedIndices.removeAll()
        
        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        
        onStart?()
        player?.play()
        startTimer()
    }

    /// Plays audio from a local file URL.
    public func play(url: URL, boundaries: [WordBoundary] = []) throws {
        stop()
        self.boundaries = boundaries
        self.firedIndices.removeAll()
        
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        
        onStart?()
        player?.play()
        startTimer()
    }

    /// Pauses audio playback.
    public func pause() {
        player?.pause()
        stopTimer()
    }

    /// Resumes audio playback from the current position.
    public func resume() {
        player?.play()
        startTimer()
    }

    /// Stops audio playback and clears references.
    public func stop() {
        stopTimer()
        if let p = player, p.isPlaying {
            p.stop()
        }
        player = nil
        boundaries.removeAll()
        firedIndices.removeAll()
    }

    public var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    // MARK: - Timing Boundary Monitor

    private func startTimer() {
        guard !boundaries.isEmpty else { return }
        stopTimer()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.timer == nil, !self.boundaries.isEmpty else { return }
            
            let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
                self?.checkBoundaries()
            }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
    }

    private func stopTimer() {
        if Thread.isMainThread {
            timer?.invalidate()
            timer = nil
        } else {
            DispatchQueue.main.sync {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    private func checkBoundaries() {
        guard let p = player, p.isPlaying else { return }
        let currentMs = Int(p.currentTime * 1000)

        for (index, boundary) in boundaries.enumerated() {
            if !firedIndices.contains(index) && currentMs >= boundary.offset {
                firedIndices.insert(index)
                onBoundary?(boundary)
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopTimer()
        if flag {
            onEnd?()
        } else {
            onError?(NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Playback finished unsuccessfully"]))
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopTimer()
        if let err = error {
            onError?(err)
        }
    }
}
