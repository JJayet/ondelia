import Foundation

enum SafeImportPathError: LocalizedError, Equatable {
    case empty
    case absolute(String)
    case traversal(String)
    case invalidComponent(String)
    case outsideRoot(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The imported path is empty."
        case .absolute(let path):
            return "Absolute imported paths are not allowed: \(path)"
        case .traversal(let path):
            return "Imported paths cannot traverse outside their root: \(path)"
        case .invalidComponent(let path):
            return "The imported path contains an invalid component: \(path)"
        case .outsideRoot(let path):
            return "The imported path resolves outside its allowed root: \(path)"
        }
    }
}

enum SafeImportPath {
    static func normalizedRelativePath(_ rawPath: String) throws -> String {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty else { throw SafeImportPathError.empty }
        guard !path.hasPrefix("/"), !hasWindowsDrivePrefix(path) else {
            throw SafeImportPathError.absolute(rawPath)
        }
        guard !path.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw SafeImportPathError.invalidComponent(rawPath)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        var normalized: [Substring] = []
        for (index, component) in components.enumerated() {
            if component.isEmpty {
                // A trailing slash is valid for a directory entry; embedded empty components are not.
                if index == components.indices.last { continue }
                throw SafeImportPathError.invalidComponent(rawPath)
            }
            if component == "." { continue }
            guard component != ".." else { throw SafeImportPathError.traversal(rawPath) }
            normalized.append(component)
        }

        guard !normalized.isEmpty else { throw SafeImportPathError.empty }
        return normalized.joined(separator: "/")
    }

    static func resolvedURL(for rawPath: String, inside root: URL) throws -> URL {
        let relativePath = try normalizedRelativePath(rawPath)
        let standardizedRoot = root.standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw SafeImportPathError.outsideRoot(rawPath)
        }
        return candidate
    }

    static func existingFileURL(for rawPath: String, inside root: URL) throws -> URL {
        let candidate = try resolvedURL(for: rawPath, inside: root)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedCandidate.path.hasPrefix(rootPrefix) else {
            throw SafeImportPathError.outsideRoot(rawPath)
        }
        return resolvedCandidate
    }

    private static func hasWindowsDrivePrefix(_ path: String) -> Bool {
        guard path.count >= 2 else { return false }
        let scalars = Array(path.unicodeScalars.prefix(2))
        guard scalars[1] == ":" else { return false }
        return CharacterSet.letters.contains(scalars[0])
    }
}
