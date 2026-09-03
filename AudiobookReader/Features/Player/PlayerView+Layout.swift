import SwiftUI
import UIKit

extension PlayerView {
    // MARK: - Full Player View
    @ViewBuilder
    func fullPlayerView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background layer - full screen with cover image
            backgroundLayer(geometry: geometry)
            VStack {
                Spacer()
                controlPanel
                    .frame(height: geometry.size.height * 0.7)  // 70% height
            }
        }
    }

    // Mini player UI is handled by the tabViewBottomAccessory
    // MARK: - Background Layer
    @ViewBuilder
    func backgroundLayer(geometry: GeometryProxy) -> some View {
        if let coverImage = coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .top
                )
                .clipped()
                .accessibilityLabel(
                    String(
                        format: NSLocalizedString("Cover of %@", comment: "Audiobook cover accessibility label"),
                        audiobook.title ?? NSLocalizedString("Unknown Title", comment: "Unknown title")
                    )
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.Player.coverArt)
        } else {
            // Fallback gradient background
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.6),
                    Color.primaryBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Control Panel
    @ViewBuilder
    var controlPanel: some View {
        VStack(spacing: 16) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primaryText.opacity(0.25))
                .frame(width: 56, height: 6)
                .padding(.top, 8)
                .accessibilityHidden(true)

            headerControls
            
            Spacer()
            
            bookInfo

            progressSection

            actionButtons

            Spacer()
        }
        .padding(.horizontal, 16)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .background(Color.glassTint, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    // MARK: - Header Controls
    @ViewBuilder
    var headerControls: some View {
        HStack {
            Button {
                // Dismiss overlay by clearing router's presented
                if let router = playerRouter {
                    router.presented = nil
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundColor(.primaryText)
            }
            .accessibilityLabel(NSLocalizedString("Sleep Timer", comment: "Sleep timer accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.sleepTimerButton)

            Spacer()

            Button {
                showingSleepTimer = true
            } label: {
                if viewModel.sleepTimeRemaining > 0 {
                    Label(
                        formatTime(viewModel.sleepTimeRemaining),
                        systemImage: "moon.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "moon")
                        .font(.title2)
                        .foregroundColor(.primaryText)
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Book Info
    @ViewBuilder
    var bookInfo: some View {
        VStack(spacing: 8) {
            Text(
                audiobook.title
                    ?? NSLocalizedString(
                        "Unknown Title",
                        comment: "Default title for audiobooks without title"
                    )
            )
            .font(.title2)
            .foregroundColor(.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)

            Text(
                audiobook.author
                    ?? NSLocalizedString(
                        "Unknown Author",
                        comment: "Default author for audiobooks without author"
                    )
            )
            .font(.headline)
            .foregroundColor(.secondaryText)

            if let narrator = audiobook.narrator {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Narrated by %@",
                            comment: "Narrator credit text"
                        ),
                        narrator
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondaryText)
            }

            // Current Chapter
            if let chapter = viewModel.currentChapter {
                Button {
                    showingChapterList = true
                } label: {
                    Text(
                        chapter.title
                            ?? String(
                                format: NSLocalizedString(
                                    "Chapter %d",
                                    comment: "Default chapter title with number"
                                ),
                                chapter.chapterNumber
                            )
                    )
                    .font(.footnote)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .background(Color.glassTint, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityIdentifiers.Player.chaptersButton)
            }
        }
    }

    // MARK: - Progress Section
    @ViewBuilder
    var progressSection: some View {
        VStack(spacing: 16) {
            // Time Slider
            progressSlider

            // Playback controls
            playbackControls

            // Speed control
            speedControls
        }
    }

    // MARK: - Progress Slider
    @ViewBuilder
    var progressSlider: some View {
        VStack(spacing: 8) {
            PlayerProgressSlider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { newValue in
                        audioManager.seek(to: newValue)
                    }
                ),
                range: 0...max(viewModel.duration, 1),
                onEditingChanged: { editing in
                    viewModel.isSeekingManually = editing
                }
            )

            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(viewModel.duration))
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .monospacedDigit()
            }
        }
    }
}
