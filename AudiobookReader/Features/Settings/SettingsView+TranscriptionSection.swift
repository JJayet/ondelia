import SwiftUI
import Speech

extension SettingsView {
    var transcriptionSection: some View {
        Section(NSLocalizedString("Transcription", comment: "Settings section: Transcription")) {
            HStack {
                Label(NSLocalizedString("Language", comment: "Language setting label"), systemImage: "globe")
                Spacer()
                Picker("", selection: $themeManager.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: themeManager.transcriptionLanguage) { _, newLanguage in
                    themeManager.updateTranscriptionLanguage(newLanguage)
                    Task { await refreshAssetStatus() }
                }
            }
            .modifier(SettingsRowCard())

            languageModelRow
                .modifier(SettingsRowCard())

            Toggle(isOn: $themeManager.enableTranslation) {
                Label(NSLocalizedString("Enable Translation", comment: "Enable translation toggle label"), systemImage: "translate")
            }
            .onChange(of: themeManager.enableTranslation) { _, newValue in
                themeManager.updateEnableTranslation(newValue)
            }
            .modifier(SettingsRowCard())

            if themeManager.enableTranslation {
                HStack {
                    Label(NSLocalizedString("Translate To", comment: "Translation target language label"), systemImage: "arrow.right.circle")
                    Spacer()
                    Picker("", selection: $themeManager.translationTargetLanguage) {
                        ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.translationTargetLanguage) { _, newLanguage in
                        themeManager.updateTranslationTargetLanguage(newLanguage)
                    }
                }
                .modifier(SettingsRowCard())
            }
        }
        .task { await refreshAssetStatus() }
    }

    /// The system owns the recognition model, so this row only reports whether the language
    /// asset is on the device and offers to fetch it — there is nothing to choose.
    @ViewBuilder
    private var languageModelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    NSLocalizedString("Language Model", comment: "On-device speech model label"),
                    systemImage: "waveform.badge.mic"
                )
                .foregroundStyle(Color.primaryText)
                Spacer()
                switch assetStatus {
                case .installed:
                    Label(
                        NSLocalizedString("Ready", comment: "Speech model installed"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.green)
                case .downloading:
                    ProgressView().scaleEffect(0.8)
                case .supported:
                    Button(NSLocalizedString("Download", comment: "Download button")) {
                        Task {
                            try? await speechManager.installAssetsIfNeeded()
                            await refreshAssetStatus()
                        }
                    }
                    .font(.caption)
                case .unsupported, .none:
                    Text(NSLocalizedString("Not supported", comment: "Speech model unsupported"))
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                @unknown default:
                    EmptyView()
                }
            }

            if speechManager.isModelLoading {
                ProgressView(value: speechManager.modelLoadingProgress)
                Text(NSLocalizedString("Downloading language model...", comment: "Speech model downloading status"))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    private func refreshAssetStatus() async {
        assetStatus = await speechManager.assetStatus()
    }
}
