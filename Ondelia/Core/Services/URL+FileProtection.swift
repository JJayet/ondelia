import Foundation

extension URL {
    /// Drops data protection on an imported file so it stays readable before the first unlock
    /// after a reboot — the "alarm woke me, press play" case, where the default
    /// `completeUntilFirstUserAuthentication` class leaves the file locked.
    ///
    /// Recurses into directories, since a folder audiobook is a folder of files.
    func disableFileProtection() {
        var url = self
        try? url.setResourceValues({
            var values = URLResourceValues()
            values.isUserImmutable = false
            return values
        }())
        try? (url as NSURL).setResourceValue(URLFileProtection.none, forKey: .fileProtectionKey)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)
        else { return }

        for case let child as URL in enumerator {
            try? (child as NSURL).setResourceValue(URLFileProtection.none, forKey: .fileProtectionKey)
        }
    }
}
