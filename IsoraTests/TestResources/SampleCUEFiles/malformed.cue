REM This is a malformed CUE file for testing error handling
PERFORMER "Test Author
TITLE "Missing Quote Audiobook"
FILE "audiobook.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Chapter 1"
    INDEX 01 99:99:99
  TRACK 02 AUDIO
    TITLE 
    INDEX 01 05:30:25
  TRACK 03
    TITLE "Missing Track Type"
    INDEX 01 invalid_time