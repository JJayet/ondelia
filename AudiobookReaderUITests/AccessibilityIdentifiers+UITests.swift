//
//  AccessibilityIdentifiers+UITests.swift
//  AudiobookReaderUITests
//
//  Created for UI Testing Support
//

import Foundation

/// Centralized accessibility identifiers for UI testing and VoiceOver support
enum AccessibilityIdentifiers {
    // MARK: - Player View
    enum Player {
        static let playPauseButton = "player_play_pause_button"
        static let skipBackwardButton = "player_skip_backward_button"
        static let skipForwardButton = "player_skip_forward_button"
        static let progressSlider = "player_progress_slider"
        static let speedControl = "player_speed_control"
        static let chaptersButton = "player_chapters_button"
        static let bookmarksButton = "player_bookmarks_button"
        static let sleepTimerButton = "player_sleep_timer_button"
        static let coverArt = "player_cover_art"
    }
    
    // MARK: - Library View
    enum Library {
        static let searchBar = "library_search_bar"
        static let sortButton = "library_sort_button"
        static let viewModeToggle = "library_view_mode_toggle"
        static let importButton = "library_import_button"
        static let audiobookCell = "library_audiobook_cell"
    }
    
    // MARK: - Mini Player
    enum MiniPlayer {
        static let container = "mini_player_container"
        static let playPauseButton = "mini_player_play_pause_button"
        static let closeButton = "mini_player_close_button"
        static let progressBar = "mini_player_progress_bar"
    }
    
    // MARK: - Tab Bar
    enum TabBar {
        static let homeTab = "tab_bar_home"
        static let libraryTab = "tab_bar_library"
        static let settingsTab = "tab_bar_settings"
    }
    
    // MARK: - Home Screen
    enum HomeScreen {
        static let mainContent = "home_main_content"
        static let welcomeMessage = "home_welcome_message"
    }
    
    // MARK: - Settings
    enum Settings {
        static let themeToggle = "settings_theme_toggle"
        static let speedSetting = "settings_speed_setting"
        static let skipIntervalSetting = "settings_skip_interval"
    }
    
    // MARK: - Widgets
    enum Widgets {
        static let nowPlayingWidget = "widget_now_playing"
        static let libraryWidget = "widget_library"
    }
}