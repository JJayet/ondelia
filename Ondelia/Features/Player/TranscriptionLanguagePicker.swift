import Speech
import SwiftUI

/// The language a book is recognised in. The default is what the file declares, else the
/// device language; it is named for what it is, not "auto-detect", because nothing listens to
/// the audio to find out.
struct TranscriptionLanguagePicker: View {
    /// Resolve the default for this file, independently of the selected override.
    let audioURL: URL?
    /// A locale identifier, or nil for the default.
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss
    @State private var locales: [Locale] = []
    @State private var search = ""
    @State private var defaultLocale: Locale?

    private var filtered: [Locale] {
        guard !search.isEmpty else { return locales }
        return locales.filter { Self.name(of: $0).localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { pick(nil) } label: {
                        row(
                            NSLocalizedString("From file or device", comment: "Transcription language: default option"),
                            detail: defaultLocale.map(Self.name(of:)),
                            checked: selection == nil
                        )
                    }
                }
                Section {
                    ForEach(filtered, id: \.identifier) { locale in
                        Button { pick(locale.identifier) } label: {
                            row(Self.name(of: locale), detail: locale.identifier, checked: selection == locale.identifier)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: NSLocalizedString("Search languages", comment: "Transcription language: search field"))
            .navigationTitle(NSLocalizedString("Transcription language", comment: "Transcription language picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                }
            }
            .task {
                locales = await SpeechTranscriber.supportedLocales
                    .sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
            }
            .task(id: audioURL) {
                defaultLocale = nil
                guard let audioURL else { return }
                let locale = await SpeechTranscriptionManager.defaultLocale(for: audioURL)
                guard !Task.isCancelled else { return }
                defaultLocale = locale
            }
        }
    }

    private func pick(_ identifier: String?) {
        withHapticFeedback { selection = identifier }
        dismiss()
    }

    private func row(_ title: String, detail: String?, checked: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }

    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
