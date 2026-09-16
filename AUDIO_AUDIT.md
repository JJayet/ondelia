# Audio audit: Dolby Atmos and spatial playback

Date: 2026-09-12

## Conclusion

Ondelia has a suitable iPhone playback architecture for compatible Dolby Atmos files, but end-to-end Atmos rendering has not been verified on a physical device. Import preserves original audio, playback uses Apple's AVQueuePlayer, and multichannel spatialization is permitted. These facts do not prove that a particular file and output route render Atmos.

Watch downloads explicitly discard the original spatial presentation by converting audio to mono AAC at 64 kbps.

Recommended support wording until device validation is complete:

> Original audio is preserved on iPhone, with compatible multichannel and spatial playback through Apple's player. Watch downloads are optimized to mono audio.

## Scope and evidence

This is the source audit discussed on 2026-09-12, covering import, folder merging, playback, audio-session lifecycle, output routes, speed changes, transcription, and Watch transfers. It is not an audit of every audio-related feature or an Atmos certification.

- Findings are based on the current source and Apple documentation linked below.
- No physical-device Atmos playback, route, or speed measurements were performed.
- No Atmos reference-file decoding tests were performed.
- Earlier successful builds and schema tests do not establish audio rendering behavior.
- No production code was changed for this audit.

| Area | Source evidence / status |
| --- | --- |
| iPhone import | Original files are copied without audio re-encoding |
| Folder merging | Individual audio files are copied into the merged folder |
| iPhone playback | AVQueuePlayer with multichannel spatialization permitted |
| Atmos identification | No explicit selected-track Atmos detection or rendering diagnostics found |
| Playback speed | Rate changes implemented; Atmos behavior unverified |
| AirPods, AirPlay, CarPlay | Rendering depends on the content, route, and system preferences; device validation pending |
| Transcription | Separate decoding/conversion path; does not overwrite playback audio |
| Watch transfers | One-channel PCM downmix followed by mono AAC encoding at 64 kbps |

## Findings

### 1. P2 — No recovery after a media-services reset

The iPhone audio session is configured behind `hasActivatedAudioSession`. The manager observes interruptions and route changes, but does not observe `mediaServicesWereResetNotification`. After a media-server restart, the activation flag remains set and there is no explicit path to recreate audio objects and restore the session configuration.

This is a general playback reliability issue, including for multichannel playback. Its occurrence and exact symptoms have not been reproduced on a device in this audit.

**Recommendation:** observe the reset, invalidate the activation flag, recreate the affected audio objects, restore the necessary session settings and saved playback state, and wait for user action before restarting playback.

Evidence:

- [Audio-session activation and observers](Ondelia/Core/Managers/GlobalAudioManager+AudioSession.swift), `activateAudioSession`, `activateSession`, `observeAudioSession`.
- [Manager state](Ondelia/Core/Managers/GlobalAudioManager.swift), `hasActivatedAudioSession`.
- [Apple: mediaServicesWereResetNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification) requires reinitializing audio objects and resetting audio-session configuration.

### 2. Confirmed limitation — Watch transfers do not preserve Atmos

`WatchAudioExporter` asks AVAssetReader for one-channel PCM, then writes one-channel MPEG-4 AAC at 64,000 bits per second. This removes the original spatial presentation, including ordinary stereo separation. This is an intentional storage and transfer tradeoff, not a missing playback toggle.

**Recommendation:** describe Watch downloads as optimized audio. Any future quality-preserving option needs a different export/transfer path and separate watchOS compatibility validation. Enabling spatialization cannot restore information removed during conversion.

Evidence:

- [Watch exporter](Ondelia/Core/Services/Watch/WatchAudioExporter.swift), `makeReader` and `makeWriter`.
- [Transfer integration](Ondelia/Core/Services/Watch/WatchSyncService+Transfers.swift), invocation of `WatchAudioExporter.export`.
- [Watch audio session](OndeliaWatch%20Watch%20App/Audio/WatchAudioManager+Session.swift), playback with `.spokenAudio` and `.longFormAudio`.

### 3. P3 — Spatial-audio comments overstate the configuration's effect

The player comment says the default permits only mono/stereo and leaves Atmos unspatialized. Apple's current documentation says audio-only content defaults to permitting **multichannel** spatialization. Setting `.monoStereoAndMultichannel` additionally permits spatializing ordinary mono/stereo recordings; it is not an Atmos decoder switch.

The session comment also presents `setSupportsMultichannelContent(true)` as preventing downmixing. Apple describes this API as advertising multichannel support, and explains that AVPlayer manages the relevant indications automatically. The call is not proof of the source format or actual output rendering.

**Recommendation:** correct those explanations and explicitly decide whether spatializing ordinary narration is intended. The current spatialization value is valid, but has a broader effect than Atmos support alone.

The comment claiming `.spokenAudio` always flattens Atmos to stereo should also be treated as unverified. The documentation consulted describes that mode's interruption behavior, not a universal Atmos-to-stereo rule. The current `.default` mode is not itself evidence of Atmos rendering.

Evidence:

- [Player item configuration](Ondelia/Core/Services/AudiobookPlayer.swift), `moveQueue`.
- [Session configuration](Ondelia/Core/Managers/GlobalAudioManager+AudioSession.swift), `activateSession` and `configureSpatialAudio`.
- [Apple: allowedAudioSpatializationFormats](https://developer.apple.com/documentation/avfoundation/avplayeritem/allowedaudiospatializationformats).
- [Apple: Immerse your app in Spatial Audio](https://developer.apple.com/videos/play/wwdc2021/10265/).
- [Apple: spokenAudio mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/spokenaudio).

### 4. Validation gap — No way to distinguish Atmos rendering from fallback

The implementation does not inspect the selected audio format, spatial playback capabilities, or rendering changes. Successful playback may therefore be Atmos, conventional surround, or stereo, without the app being able to explain which occurred.

**Recommendation:** add developer diagnostics before adding an Atmos badge. Capture the selected track's codec and channel layout, current route, spatial-audio enablement, playback rate, and relevant rendering/capability changes. Codec or channel count alone should not be treated as proof of Atmos.

Important API limits:

- `isSpatialAudioEnabled` describes the output port's spatial capability and user preference; it does not identify Atmos content.
- `renderingMode` is not a universal AirPods Atmos detector. Apple documents `.notApplicable` outside supported CarPlay/AirPlay circumstances, as well as when playback/session conditions do not permit reporting.
- Spatialized stereo is not Dolby Atmos.

Evidence:

- [Apple: isSpatialAudioEnabled](https://developer.apple.com/documentation/avfaudio/avaudiosessionportdescription/isspatialaudioenabled).
- [Apple: renderingMode and its limitations](https://developer.apple.com/documentation/avfaudio/avaudiosession/renderingmode-swift.property).

### 5. Support boundary — File acceptance and audio-track selection

The normal M4A/M4B import path preserves bytes. Folder import, ZIP discovery, and fallback playback use extension allowlists that omit formats such as `.mp4`, `.mov`, and `.ec3`. These paths cannot support a blanket claim that all Atmos files are accepted. A filename extension by itself also does not establish codec compatibility.

AVPlayer chooses the audio track using its normal behavior. Ondelia does not explicitly prefer or expose selection between stereo and Atmos alternatives within a multi-track asset. This is not necessarily incorrect, but must be tested with representative multi-track files.

**Recommendation:** define a tested container/codec support matrix before expanding the allowlists or advertising additional formats. Inspect selected tracks in diagnostics before deciding whether custom selection is necessary.

Evidence:

- [Document picker](Ondelia/Features/Library/DocumentPickerView.swift), `contentTypes`.
- [Folder filtering](Ondelia/Core/Services/FolderImporter+Helpers.swift), `audioFileExtensions`.
- [ZIP discovery](Ondelia/Core/Services/ZIPImporter.swift), audio extension filtering.
- [Fallback playback discovery](Ondelia/Core/Services/AudiobookPlayer+Tracks.swift), `tracksFromDirectoryListing`.
- [Original-file copy](Ondelia/Core/Managers/AudiobookManager+FileCopy.swift), `streamCopyFile`.
- [Folder merge](Ondelia/Core/Managers/AudiobookManager+Merge.swift), source-file copying.

### 6. Validation gap — Playback speed and transcription compatibility

Playback speed is applied through AVPlayer's `defaultRate` and `rate`. Source inspection does not establish whether Atmos rendering is retained at every offered speed. Neither preservation nor loss should be asserted without device evidence.

Transcription separately opens the source through AVAudioFile and converts buffers to SpeechAnalyzer's requested format. It does not replace the player's audio or overwrite the original file. Nevertheless, AVPlayer playback success does not establish that the same file will decode through AVAudioFile/AVAudioConverter successfully.

**Recommendation:** test speed changes and transcription with the same known Atmos fixtures. Record rendering state where available and errors from each decoding path separately.

Evidence:

- [Playback rate](Ondelia/Core/Services/AudiobookPlayer.swift), `play`, `seek`, `setPlaybackRate`.
- [Transcription decoding](Ondelia/Core/Services/AudioWindowSequence.swift), iterator `open`, `next`, and `convert`.
- [Transcription orchestration](Ondelia/Core/Services/SpeechTranscriptionManager.swift).
- [Apple: audioTimePitchAlgorithm](https://developer.apple.com/documentation/avfoundation/avplayeritem/audiotimepitchalgorithm).

## Physical-device validation checklist

Use a known Atmos reference file, a surround-only reference, and a stereo control. Include a multi-track asset if that is part of the intended support claim. Record the device, iOS version, source codec/container, output hardware, system spatial settings, and playback rate for each result.

| Scenario | Required observation |
| --- | --- |
| Single-file, folder, and ZIP import | Compare source and imported file hashes; verify accepted formats |
| iPhone playback at 1x | Verify selected track and available rendering evidence; confirm intelligible, uninterrupted audio |
| Every offered playback speed | Check rendering changes, pitch, audible artifacts, and fallback behavior |
| AirPods: off, fixed, head-tracked | Verify system preference behavior without calling spatialized stereo Atmos |
| Supported AirPlay and CarPlay routes | Record route capabilities and rendering mode where supported |
| Unsupported/stereo route | Confirm usable playback and no misleading Atmos indication |
| Seeking and chapter transitions | Check for silence, errors, unexpected track changes, or rendering changes |
| Screen lock, interruptions, route changes | Verify continuation/recovery and retained settings |
| Media-services reset | Verify reinitialization and user-initiated recovery after the proposed fix |
| Transcription during playback | Confirm decoding succeeds and playback remains responsive |
| Watch download | Verify expected mono AAC output and that the iPhone original is unchanged |

An audible impression or a generic spatial-audio control alone is insufficient evidence of Atmos rendering. Preserve logs and source-format evidence alongside any route-specific rendering information.

## Recommended order of work

1. Implement media-services reset recovery.
2. Correct misleading spatialization comments and clarify the intended treatment of ordinary narration.
3. Add developer-only format and route diagnostics.
4. Run the physical-device matrix and document supported combinations.
5. Publish a precise support statement; add richer Watch transfer options only if desired and separately validated.

The existing iPhone playback architecture does not need to be replaced based on this audit.
