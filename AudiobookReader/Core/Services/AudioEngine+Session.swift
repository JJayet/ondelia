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
            print("⚠️ AudioEngine: Could not set sample rate: \(error)")
        }
        
        do {
            try audioSession.setPreferredIOBufferDuration(0.02) // 20ms buffer for stability
        } catch {
            print("⚠️ AudioEngine: Could not set buffer duration: \(error)")
        }
        
        // Configure audio routing
        do {
            try audioSession.setPreferredOutputNumberOfChannels(2)
        } catch {
            print("⚠️ AudioEngine: Could not set output channels: \(error)")
        }
        
        // Activate the session
        try audioSession.setActive(true)
        hasSetupAudioSession = true

        print("✅ AudioEngine: Audio session configured successfully")

    } catch {
        print("❌ AudioEngine: Failed to set up audio session: \(error)")
        // Try a minimal fallback configuration
        setupFallbackAudioSession()
    }
}

    private func setupFallbackAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            print("🔄 AudioEngine: Attempting fallback audio session setup")
            
            // Minimal configuration that should always work
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            hasSetupAudioSession = true

            print("✅ AudioEngine: Fallback audio session configured")
            
        } catch {
            print("❌ AudioEngine: Even fallback audio session failed: \(error)")
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
            print("🎵 AudioEngine: Audio session interrupted - pausing playback")
            pause()
            
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                print("🎵 AudioEngine: Audio session interruption ended - resuming playback")
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
            print("🎧 AudioEngine: Audio device disconnected - pausing playback")
            pause()
            
        case .newDeviceAvailable:
            print("🎧 AudioEngine: New audio device connected")
            // Optionally configure for the new device
            configureForCurrentAudioRoute()
            
        case .routeConfigurationChange:
            print("🎧 AudioEngine: Audio route configuration changed")
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
                print("✨ AudioEngine: Enhanced audio settings enabled for spatial audio capable route")
            } catch {
                print("⚠️ AudioEngine: Failed to configure enhanced audio settings: \(error)")
            }
        }
    }

func deactivateAudioSession() {
    if hasSetupAudioSession {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasSetupAudioSession = false
            print("✅ AudioEngine: Audio session deactivated")
        } catch {
            print("⚠️ AudioEngine: Failed to deactivate audio session: \(error)")
        }
    }
}
}
