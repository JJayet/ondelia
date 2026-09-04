import Foundation

extension Bundle {
    /// `1.2 (34)`, read from the bundle rather than typed into the About screen.
    var shortVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = infoDictionary?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}
