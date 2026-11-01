import SwiftUI
import AVFoundation
import Combine

public final class MiniPlayerVideoNSView: NSView {
    public let playerLayer = AVPlayerLayer()
    
    override public init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.masksToBounds = true
        playerLayer.drawsAsynchronously = true
        playerLayer.player = PlaybackCoordinator.shared.primaryEngine.player
        layer?.addSublayer(playerLayer)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

public struct MiniPlayerPreviewRepresentable: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> MiniPlayerVideoNSView {
        return MiniPlayerVideoNSView(frame: .zero)
    }
    
    public func updateNSView(_ nsView: MiniPlayerVideoNSView, context: Context) {
        if nsView.playerLayer.player !== PlaybackCoordinator.shared.primaryEngine.player {
            nsView.playerLayer.player = PlaybackCoordinator.shared.primaryEngine.player
        }
    }
}

public struct MiniPlayerCardView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var currentTimeSeconds: Double = 0.0
    @State private var totalDurationSeconds: Double = 0.0
    @State private var isDraggingScrubber: Bool = false
    @State private var scrubProgress: Double = 0.0
    @State private var isPlaying: Bool = true
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 8) {
            // Live Video Preview Container
            ZStack(alignment: .bottomLeading) {
                MiniPlayerPreviewRepresentable()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                
                // Badges overlay
                HStack(spacing: 6) {
                    if settings.isAdaptiveFramerateEnabled {
                        badgeView(text: "⚡ Adaptive \(settings.targetFPS.shortTitle)")
                    } else {
                        badgeView(text: settings.targetFPS.shortTitle)
                    }
                    
                    if settings.playbackSpeed != 1.0 {
                        badgeView(text: String(format: "%.2fx", settings.playbackSpeed))
                    }
                    
                    Spacer()
                    
                    if settings.isDayNightEnabled {
                        badgeView(text: ResourceMonitor.isDarkMode() ? "🌙 Night" : "☀️ Day")
                    }
                }
                .padding(6)
            }
            .frame(width: 270)
            
            // Video Title & Information
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentVideoName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty {
                        Text("Playlist \(PlaybackCoordinator.shared.currentPlaylistIndex + 1) of \(settings.playlistVideos.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .frame(width: 270)
            
            // Timeline Scrubber & Timestamp
            VStack(spacing: 3) {
                Slider(value: Binding(
                    get: { isDraggingScrubber ? scrubProgress : currentFraction },
                    set: { newValue in
                        scrubProgress = newValue
                        isDraggingScrubber = true
                        seekToFraction(newValue, exact: false)
                    }
                ), in: 0...1) { editing in
                    if !editing {
                        isDraggingScrubber = false
                        seekToFraction(scrubProgress, exact: true)
                    }
                }
                .controlSize(.mini)
                
                HStack {
                    Text(formatTime(currentTimeSeconds))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(totalDurationSeconds))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 270)
            
            // Playback Controls Row
            HStack(spacing: 16) {
                if settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty {
                    Button(action: {
                        PlaybackCoordinator.shared.advancePlaylist(direction: .previous)
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    PlaybackCoordinator.shared.togglePlayPause()
                    updateState()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                
                if settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty {
                    Button(action: {
                        PlaybackCoordinator.shared.advancePlaylist(direction: .next)
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(action: {
                    PlaybackCoordinator.shared.toggleMute()
                }) {
                    Image(systemName: settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(settings.isMuted ? .secondary : .primary)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 270)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onReceive(timer) { _ in
            if StatusMenuController.isMenuOpen {
                updateState()
            }
        }
        .onAppear {
            updateState()
        }
    }
    
    private var currentVideoName: String {
        if let url = PlaybackCoordinator.shared.primaryEngine.videoURL {
            return url.lastPathComponent
        }
        return "No Video Active"
    }
    
    private var currentFraction: Double {
        guard totalDurationSeconds > 0 else { return 0.0 }
        return max(0.0, min(1.0, currentTimeSeconds / totalDurationSeconds))
    }
    
    private func updateState() {
        let engine = PlaybackCoordinator.shared.primaryEngine
        let currentCM = engine.currentTime
        let current = CMTimeGetSeconds(currentCM)
        let duration = CMTimeGetSeconds(engine.duration)
        
        if current.isFinite && current >= 0 {
            currentTimeSeconds = current
        }
        if duration.isFinite && duration > 0 {
            totalDurationSeconds = duration
        }
        
        isPlaying = engine.isPlaying
    }
    
    private func seekToFraction(_ fraction: Double, exact: Bool = true) {
        PlaybackCoordinator.shared.seek(toFraction: fraction, exact: exact)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func badgeView(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.65))
            .cornerRadius(4)
    }
}
