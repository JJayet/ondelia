import Foundation

/// Centralized accessibility identifiers for UI testing and VoiceOver support
enum AccessibilityIdentifiers {
    // MARK: - Player View
    enum Player {
        static let playPauseButton = "player_play_pause_button"
        static let skipBackwardButton = "player_skip_backward_button"
        static let skipForwardButton = "player_skip_forward_button"
        static let previousChapterButton = "player_previous_chapter_button"
        static let nextChapterButton = "player_next_chapter_button"
        static let progressSlider = "player_progress_slider"
        static let speedControl = "player_speed_control"
        static let chaptersButton = "player_chapters_button"
        static let bookmarksButton = "player_bookmarks_button"
        static let addBookmarkButton = "bookmarks_add_button"
        static let closeButton = "player_close_button"
        static let coverArt = "player_cover_art"
        static let upNextSection = "player_up_next_section"
        static let sleepTimerRow = "player_sleep_timer_row"
        static let undoSeekRow = "player_undo_seek_row"
    }
    
    // MARK: - Library View
    enum Library {
        static let sortButton = "library_sort_button"
        static let viewModeToggle = "library_view_mode_toggle"
        static let importButton = "library_import_button"
        static let audiobookCell = "library_audiobook_cell"
        /// The play/resume button on a book's detail screen.
        static let resumeButton = "book_detail_resume_button"
        /// The book-actions menu button on the book detail screen's header.
        static let bookActionsMenu = "library.bookActionsMenu"
    }
    
    // MARK: - Mini Player
    enum MiniPlayer {
        static let container = "mini_player_container"
        static let playPauseButton = "mini_player_play_pause_button"
    }
    
    // MARK: - Tab Bar
    enum TabBar {
        static let libraryTab = "tab_bar_library"
        static let statisticsTab = "tab_bar_statistics"
        static let settingsTab = "tab_bar_settings"
    }
}