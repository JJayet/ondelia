import SwiftUI

struct MainTabView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedTab = 1 // Start with Library tab
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            // Library Tab
            EnhancedLibraryView()
                .tabItem {
                    Image(systemName: "books.vertical.fill")
                    Text("Library")
                }
                .tag(1)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
        .environment(\.theme, themeManager)
    }
}

struct HomeView: View {
    @StateObject private var audiobookManager = AudiobookManager()
    @StateObject private var statistics = ReadingStatistics()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedAudiobook: Audiobook?
    
    private var recentlyPlayed: [Audiobook] {
        audiobookManager.audiobooks
            .filter { $0.lastPlayed != nil }
            .sorted { $0.lastPlayed ?? Date.distantPast > $1.lastPlayed ?? Date.distantPast }
            .prefix(5)
            .map { $0 }
    }
    
    private var continueReading: [Audiobook] {
        audiobookManager.audiobooks
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed ?? Date.distantPast > $1.lastPlayed ?? Date.distantPast }
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
                                
                                Text("Ready to listen?")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primaryText)
                            }
                            Spacer()
                        }
                        
                        // Quick Stats
                        HStack(spacing: 20) {
                            QuickStatView(
                                title: "This Month",
                                value: statistics.formattedMonthlyProgress,
                                icon: "calendar",
                                color: .blue
                            )
                            
                            QuickStatView(
                                title: "Streak",
                                value: "\(statistics.currentStreak) days",
                                icon: "flame.fill",
                                color: .orange
                            )
                            
                            QuickStatView(
                                title: "Completed",
                                value: "\(statistics.booksCompleted)",
                                icon: "checkmark.circle.fill",
                                color: .green
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Continue Reading Section
                    if !continueReading.isEmpty {
                        HomeSection(title: "Continue Reading", subtitle: "Pick up where you left off") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(continueReading, id: \.id) { audiobook in
                                        ContinueReadingCardView(audiobook: audiobook) {
                                            selectedAudiobook = audiobook
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Recently Played Section
                    if !recentlyPlayed.isEmpty {
                        HomeSection(title: "Recently Played", subtitle: "Your recent listening history") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(recentlyPlayed, id: \.id) { audiobook in
                                        RecentlyPlayedCardView(audiobook: audiobook) {
                                            selectedAudiobook = audiobook
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Monthly Goal Progress
                    HomeSection(title: "Monthly Goal", subtitle: "Keep up your reading streak") {
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
                                Text("Welcome to Audiobook Reader")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primaryText)
                                
                                Text("Start your audiobook journey by importing your first book")
                                    .font(.body)
                                    .foregroundColor(.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            
                            NavigationLink(destination: EnhancedLibraryView()) {
                                Text("Browse Library")
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
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                audiobookManager.fetchAudiobooks()
            }
        }
        .fullScreenCover(item: $selectedAudiobook) { audiobook in
            EnhancedPlayerView(audiobook: audiobook, statistics: statistics)
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
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good night"
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
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct RecentlyPlayedCardView: View {
    let audiobook: Audiobook
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
                    Text(audiobook.title ?? "Unknown Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primaryText)
                        .lineLimit(2)
                    
                    Text(audiobook.author ?? "Unknown Author")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                    
                    if let lastPlayed = audiobook.lastPlayed {
                        Text(RelativeDateTimeFormatter().localizedString(for: lastPlayed, relativeTo: Date()))
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
                    Text("Monthly Reading Goal")
                        .font(.headline)
                        .foregroundColor(.primaryText)
                    
                    Text("\(statistics.formattedMonthlyProgress) of \(statistics.formattedMonthlyGoal)")
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
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    MainTabView()
}