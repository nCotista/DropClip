import Foundation

/// Pure helper logic for the macOS native file picker (`dropclip/file_picker`).
public enum FilePickerSupport {
    /// Filters and deduplicates URLs returned by `NSOpenPanel`, preserving
    /// selection order while dropping non-file URLs and empty paths.
    public static func normalizeFileURLs(_ urls: [URL]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for url in urls where url.isFileURL {
            let path = url.path
            guard !path.isEmpty else { continue }
            let canonical = url.standardizedFileURL.path
            if seen.insert(canonical).inserted {
                result.append(path)
            }
        }
        return result
    }
}
