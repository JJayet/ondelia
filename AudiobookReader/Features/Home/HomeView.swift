//
//  Home.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 01/09/2025.
//
import SwiftUI

struct HomeView: View {
    @StateObject private var audiobookManager = AudiobookManager.shared
    @StateObject private var statistics = ReadingStatistics()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedAudiobook: AudiobookModel?
    @Environment(\.setTabSelection) private var setTabSelection
    @Environment(\.playerRouter) private var playerRouter

    private var recentlyPlayed: [AudiobookModel] {
        audiobookManager.audiobooks
            .filter { $0.lastPlayed > Date.distantPast }
            .sorted { $0.lastPlayed > $1.lastPlayed }
            .prefix(5)
            .map { $0 }
    }

    private var continueReading: [AudiobookModel] {
        audiobookManager.audiobooks
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed > $1.lastPlayed }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 32) {
                    // Welcome Header
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(greetingMessage)
                                    .font(.title2)
                                    .foregroundColor(.secondaryText)

                                Text(
                                    NSLocalizedString(
                                        "Ready to listen?",
                                        comment: "Home screen welcome message"
                                    )
                                )
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.primaryText)
                            }
                            Spacer()
                        }

                        // Quick Stats
                        HStack(spacing: 20) {
                            QuickStatView(
                                title: NSLocalizedString(
                                    "This Month",
                                    comment: "This month quick stat title"
                                ),
                                value: statistics.formattedMonthlyProgress,
                                icon: "calendar",
                                color: .blue
                            )

                            QuickStatView(
                                title: NSLocalizedString(
                                    "Streak",
                                    comment: "Reading streak quick stat title"
                                ),
                                value:
                                    "\(statistics.currentStreak) \(NSLocalizedString("days", comment: "Days unit"))",
                                icon: "flame.fill",
                                color: .orange
                            )

                            QuickStatView(
                                title: NSLocalizedString(
                                    "Completed",
                                    comment: "Books completed quick stat title"
                                ),
                                value: "\(statistics.booksCompleted)",
                                icon: "checkmark.circle.fill",
                                color: .green
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Continue Reading Section
                    if !continueReading.isEmpty {
                        HomeSection(
                            title: NSLocalizedString(
                                "Continue Reading",
                                comment: "Continue reading section title"
                            ),
                            subtitle: NSLocalizedString(
                                "Pick up where you left off",
                                comment: "Continue reading section subtitle"
                            )
                        ) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(continueReading, id: \.id) {
                                        audiobook in
                                        ContinueReadingCardView(
                                            audiobook: audiobook
                                        ) {
                                            let audio = GlobalAudioManager.shared
                                            audio.loadAudiobook(audiobook)
                                            audio.startPlayback()
                                            playerRouter?.present(audiobook)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Recently Played Section
                    if !recentlyPlayed.isEmpty {
                        HomeSection(
                            title: NSLocalizedString(
                                "Recently Played",
                                comment: "Recently played section title"
                            ),
                            subtitle: NSLocalizedString(
                                "Your recent listening history",
                                comment: "Recently played section subtitle"
                            )
                        ) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(recentlyPlayed, id: \.id) {
                                        audiobook in
                                        RecentlyPlayedCardView(
                                            audiobook: audiobook
                                        ) {
                                            let audio = GlobalAudioManager.shared
                                            audio.loadAudiobook(audiobook)
                                            audio.startPlayback()
                                            playerRouter?.present(audiobook)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Monthly Goal Progress
                    HomeSection(
                        title: NSLocalizedString(
                            "Monthly Goal",
                            comment: "Monthly goal section title"
                        ),
                        subtitle: NSLocalizedString(
                            "Keep up your reading streak",
                            comment: "Monthly goal section subtitle"
                        )
                    ) {
                        MonthlyGoalCardView(statistics: statistics)
                            .padding(.horizontal)
                    }

                    // Empty State for New Users
                    if audiobookManager.audiobooks.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: "headphones.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.accentColor)

                            VStack(spacing: 12) {
                                Text(
                                    NSLocalizedString(
                                        "Welcome to Audiobook Reader",
                                        comment: "Welcome message for new users"
                                    )
                                )
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primaryText)
                                .multilineTextAlignment(.center)
                            }

                            Button {
                                setTabSelection?(1)
                            } label: {
                                Text(
                                    NSLocalizedString(
                                        "Browse Library",
                                        comment: "Browse library button text"
                                    )
                                )
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.primaryBackground)
            .navigationTitle(
                NSLocalizedString("Home", comment: "Home navigation title")
            )
            .navigationBarTitleDisplayMode(.automatic)
            .refreshable {
                audiobookManager.fetchAudiobooks()
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
        .onAppear {
            audiobookManager.fetchAudiobooks()
        }
    }

    private var greetingMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return NSLocalizedString(
                "Good morning",
                comment: "Morning greeting"
            )
        case 12..<17:
            return NSLocalizedString(
                "Good afternoon",
                comment: "Afternoon greeting"
            )
        case 17..<22:
            return NSLocalizedString(
                "Good evening",
                comment: "Evening greeting"
            )
        default:
            return NSLocalizedString("Good night", comment: "Night greeting")
        }
    }
}

struct HomeSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal)

            content
        }
    }
}

struct QuickStatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primaryText)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondaryText)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

struct RecentlyPlayedCardView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                            .foregroundColor(.secondaryText)
                    }
                }
                .frame(width: 120, height: 80)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        audiobook.title
                            ?? NSLocalizedString(
                                "Unknown Title",
                                comment: "Unknown title placeholder"
                            )
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                    .lineLimit(2)

                    Text(
                        audiobook.author
                            ?? NSLocalizedString(
                                "Unknown Author",
                                comment: "Unknown author placeholder"
                            )
                    )
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)

                    if audiobook.lastPlayed > Date.distantPast {
                        Text(
                            RelativeDateTimeFormatter().localizedString(
                                for: audiobook.lastPlayed,
                                relativeTo: Date()
                            )
                        )
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MonthlyGoalCardView: View {
    @ObservedObject var statistics: ReadingStatistics

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        NSLocalizedString(
                            "Monthly Reading Goal",
                            comment: "Monthly reading goal card title"
                        )
                    )
                    .font(.headline)
                    .foregroundColor(.primaryText)
                    
                    Text(
                        "\(statistics.formattedMonthlyProgress) of \(statistics.formattedMonthlyGoal)"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondaryText)
                }
                
                Spacer()
                
                Text("\(Int(statistics.monthlyGoalProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            ProgressView(value: statistics.monthlyGoalProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(height: 6)
                .background(Color.secondaryBackground)
                .cornerRadius(3)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

#Preview("Home") {
    HomeView()
        .previewWithMockAudio()
}
