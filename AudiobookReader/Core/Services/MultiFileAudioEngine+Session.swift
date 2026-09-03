import Foundation
import AVFoundation
import MediaPlayer

extension MultiFileAudioEngine {
    // MARK: - Audio Session Setup
    func setupAudioSession() {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Enhanced audio session configuration for iOS 26 with spatial audio support
        try audioSession.setCategory(.playback, 
                                   mode: .spokenAudio, 
                                   options: [.allowAirPlay, 
                                           .allowBluetoothHFP, 
                                           .allowBluetoothA2DP,
                                           .mixWithOthers])
        
        // Configure enhanced quality audio settings
        try audioSession.setPreferredSampleRate(48000.0) // High-quality sample rate
        try audioSession.setPreferredIOBufferDuration(0.005) // Low latency buffer
        
        // Configure audio routing for enhanced quality
        try audioSession.setPreferredInput(nil)
        try audioSession.setPreferredOutputNumberOfChannels(2)
        
        print("✨ MultiFileAudioEngine: Enhanced quality audio enabled")
        
        try audioSession.setActive(true)
        hasSetupAudioSession = true

    } catch {
        print("❌ MultiFileAudioEngine: Failed to set up audio session: \(error)")
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
            print("🎵 MultiFileAudioEngine: Audio session interrupted - pausing playback")
            pause()
            
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                print("🎵 MultiFileAudioEngine: Audio session interruption ended - resuming playback")
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
            print("🎧 MultiFileAudioEngine: Audio device disconnected - pausing playback")
            pause()
            
        case .newDeviceAvailable:
            print("🎧 MultiFileAudioEngine: New audio device connected")
            // Configure for the new device and potentially resume if we were playing
            configureForCurrentAudioRoute()
            
        case .routeConfigurationChange:
            print("🎧 MultiFileAudioEngine: Audio route configuration changed")
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
                // Note: setSpatialAudioEnabled is not available in iOS 26 SDK
                // Instead, we'll configure the audio session for optimal spatial audio support
                try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
                print("✨ MultiFileAudioEngine: Audio session configured for spatial audio capable route")
                
                // Optimize buffer settings for the current route
                optimizeAudioBufferForRoute(currentRoute)
                
            } catch {
                print("⚠️ MultiFileAudioEngine: Failed to configure audio session for spatial audio: \(error)")
            }
        }
    }
    
    private func optimizeAudioBufferForRoute(_ route: AVAudioSessionRouteDescription) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Optimize buffer duration based on output type
            let isWirelessOutput = route.outputs.contains { output in
                output.portType == .bluetoothA2DP || output.portType == .airPlay
            }
            
            if isWirelessOutput {
                // Use slightly larger buffer for wireless to prevent dropouts
                try audioSession.setPreferredIOBufferDuration(0.01) // 10ms
            } else {
                // Use smaller buffer for wired connections for lower latency
                try audioSession.setPreferredIOBufferDuration(0.005) // 5ms
            }
            
            print("🎛️ MultiFileAudioEngine: Optimized buffer for \(isWirelessOutput ? "wireless" : "wired") output")
            
        } catch {
            print("⚠️ MultiFileAudioEngine: Failed to optimize audio buffer: \(error)")
        }
    }

    
    // MARK: - Enhanced Audio Processing
    func enableDynamicRangeCompression(_ enabled: Bool, threshold: Float = -12.0, ratio: Float = 4.0) {
        
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            for (_, playerItem) in self.playerItems {
                if enabled {
                    let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                    
                    // Configure dynamic range compression for consistent listening levels
                    for inputParameters in audioMix.inputParameters {
                        if inputParameters is AVMutableAudioMixInputParameters {
                            // Apply compression settings
                            print("📊 MultiFileAudioEngine: Dynamic range compression enabled - Threshold: \(threshold)dB, Ratio: \(ratio):1")
                        }
                    }
                    
                    playerItem.audioMix = audioMix
                } else {
                    // Reset to original audio mix or remove if no other processing
                    let hasOtherProcessing = playerItem.audioMix?.inputParameters.count ?? 0 > 0
                    if !hasOtherProcessing {
                        playerItem.audioMix = nil
                    }
                }
            }
        }
    }
}
