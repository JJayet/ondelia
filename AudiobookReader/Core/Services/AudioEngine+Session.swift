import Foundation
import AVFoundation
import MediaPlayer

extension AudioEngine {
    // MARK: - Audio Session Setup
    func setupAudioSession() {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Deactivate session first to avoid conflicts
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        // Configure basic audio session for audiobook playback
        try audioSession.setCategory(.playback, 
                                   mode: .spokenAudio, 
                                   options: [.allowAirPlay, 
                                           .allowBluetoothA2DP])
        
        // Set reasonable audio settings that work reliably
        do {
            try audioSession.setPreferredSampleRate(44100.0) // Standard CD quality
        } catch {
            Log.audio.warning("⚠️ AudioEngine: Could not set sample rate: \(error)")
        }
        
        do {
            try audioSession.setPreferredIOBufferDuration(0.02) // 20ms buffer for stability
        } catch {
            Log.audio.warning("⚠️ AudioEngine: Could not set buffer duration: \(error)")
        }
        
        // Configure audio routing
        do {
            try audioSession.setPreferredOutputNumberOfChannels(2)
        } catch {
            Log.audio.warning("⚠️ AudioEngine: Could not set output channels: \(error)")
        }
        
        // Activate the session
        try audioSession.setActive(true)
        hasSetupAudioSession = true

        Log.audio.debug("✅ AudioEngine: Audio session configured successfully")

    } catch {
        Log.audio.error("❌ AudioEngine: Failed to set up audio session: \(error)")
        // Try a minimal fallback configuration
        setupFallbackAudioSession()
    }
}

    private func setupFallbackAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            Log.audio.debug("🔄 AudioEngine: Attempting fallback audio session setup")
            
            // Minimal configuration that should always work
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            hasSetupAudioSession = true

            Log.audio.debug("✅ AudioEngine: Fallback audio session configured")
            
        } catch {
            Log.audio.error("❌ AudioEngine: Even fallback audio session failed: \(error)")
        }
    }

    // MARK: - Audio Session Event Handlers
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            Log.audio.debug("🎵 AudioEngine: Audio session interrupted - pausing playback")
            pause()
            
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                Log.audio.debug("🎵 AudioEngine: Audio session interruption ended - resuming playback")
                // Resume after a short delay to ensure audio session is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self, !self.isCleanedUp else { return }
                    self.play()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause playback
            Log.audio.debug("🎧 AudioEngine: Audio device disconnected - pausing playback")
            pause()
            
        case .newDeviceAvailable:
            Log.audio.debug("🎧 AudioEngine: New audio device connected")
            // Optionally configure for the new device
            configureForCurrentAudioRoute()
            
        case .routeConfigurationChange:
            Log.audio.debug("🎧 AudioEngine: Audio route configuration changed")
            configureForCurrentAudioRoute()
            
        default:
            break
        }
    }
    
    private func configureForCurrentAudioRoute() {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        
        // Check if we're using spatial audio capable outputs
        let hasSpatialAudioCapableOutput = currentRoute.outputs.contains { output in
            output.portType == .headphones || 
            output.portType == .bluetoothA2DP ||
            output.portType == .builtInSpeaker
        }
        
        if hasSpatialAudioCapableOutput {
            do {
                // Configure optimal settings for spatial audio capable devices
                try audioSession.setPreferredSampleRate(48000.0)
                Log.audio.debug("✨ AudioEngine: Enhanced audio settings enabled for spatial audio capable route")
            } catch {
                Log.audio.warning("⚠️ AudioEngine: Failed to configure enhanced audio settings: \(error)")
            }
        }
    }

func deactivateAudioSession() {
    if hasSetupAudioSession {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasSetupAudioSession = false
            Log.audio.debug("✅ AudioEngine: Audio session deactivated")
        } catch {
            Log.audio.warning("⚠️ AudioEngine: Failed to deactivate audio session: \(error)")
        }
    }
}
}
