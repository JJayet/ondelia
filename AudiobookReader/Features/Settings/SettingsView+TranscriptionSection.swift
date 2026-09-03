import SwiftUI

extension SettingsView {
    var transcriptionSection: some View {
        Section(NSLocalizedString("Transcription", comment: "Settings section: Transcription")) {
            VStack(alignment: .leading) {
                HStack {
                    Label(NSLocalizedString("WhisperKit Model", comment: "WhisperKit model setting label"), systemImage: "brain")
                        .foregroundColor(.primaryText)
                    Spacer()
                    Picker("", selection: $themeManager.whisperModel) {
                        ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .font(.body)
                                    .foregroundColor(.primaryText)
                                HStack {
                                    Text(model.sizeDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                    HStack(spacing: 2) {
                                        ForEach(0..<5) { index in
                                            Image(systemName: index < model.accuracyRating ? "star.fill" : "star")
                                                .font(.system(size: 8))
                                                .foregroundColor(index < model.accuracyRating ? .yellow : .secondaryText)
                                        }
                                    }
                                }
                            }
                            .tag(model)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: themeManager.whisperModel) { _, newModel in
                        themeManager.updateWhisperModel(newModel)
                        if themeManager.transcriptionEngine == .whisperKit {
                            pendingWhisperModel = newModel
                            showModelDownloadConfirm = true
                        }
                    }
                    .disabled(whisperManager.isModelLoading)
                }

                // Show loading indicator when model is loading
                if whisperManager.isModelLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(format: NSLocalizedString("Downloading %@...", comment: "Model downloading status"), themeManager.whisperModel.displayName))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                    .padding(.top, 4)
                }
            }
            .modifier(SettingsRowCard())

            HStack {
                Label(NSLocalizedString("Language", comment: "Language setting label"), systemImage: "globe")
                Spacer()
                Picker("", selection: $themeManager.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: themeManager.transcriptionLanguage) { _, newLanguage in
                    themeManager.updateTranscriptionLanguage(newLanguage)
                }
            }
            .modifier(SettingsRowCard())

            if TranslationManager.isAvailable {
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
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.translationTargetLanguage) { _, newLanguage in
                            themeManager.updateTranslationTargetLanguage(newLanguage)
                        }
                    }
                    .modifier(SettingsRowCard())
                }
            } else {
                HStack {
                    Label(NSLocalizedString("Translation", comment: "Translation feature label"), systemImage: "translate")
                    Spacer()
                    Text(NSLocalizedString("Requires iOS 17.4+", comment: "iOS version requirement text"))
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
                .modifier(SettingsRowCard())
            }
        }
    }
}
