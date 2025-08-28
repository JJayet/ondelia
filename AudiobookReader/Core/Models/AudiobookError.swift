import Foundation

enum AudiobookError: LocalizedError, Equatable {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case audioLoadFailed(String)
    case corruptedFile(String)
    case insufficientStorage
    case networkUnavailable
    case permissionDenied
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found at: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .audioLoadFailed(let reason):
            return "Failed to load audio: \(reason)"
        case .corruptedFile(let path):
            return "Audio file is corrupted: \(path)"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .permissionDenied:
            return "File access permission denied"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Please check if the file exists and try importing again."
        case .unsupportedFormat:
            return "Please convert the file to a supported format (MP3, M4A, M4B)."
        case .audioLoadFailed:
            return "Please try restarting the app or re-importing the file."
        case .corruptedFile:
            return "Please check the file integrity and try importing again."
        case .insufficientStorage:
            return "Please free up some storage space and try again."
        case .networkUnavailable:
            return "Please check your internet connection and try again."
        case .permissionDenied:
            return "Please allow file access in Settings."
        case .unknown:
            return "Please try again or contact support if the issue persists."
        }
    }
}