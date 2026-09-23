import Foundation

/// Appends keep-alive/network events to `~/Library/Logs/NightCat/network.log`,
/// rotating past the size cap into `network.log.1` (one generation, so the
/// ceiling stays ~2×cap).
///
/// Best effort by design: every file operation is swallowed on failure. The
/// log exists to explain a mystery after the fact — it must never be the
/// thing that breaks the feature it was written for.
struct NetworkLogWriter {
    private let folderURL: URL
    private let fileURL: URL

    /// `folderURL` is injectable so tests can point it at a temp directory.
    init(folderURL: URL? = nil) {
        let base = folderURL
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("NightCat", isDirectory: true)
        self.folderURL = base
        self.fileURL = base.appendingPathComponent("network.log")
    }

    func append(_ line: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path) {
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        rotateIfNeeded()
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // First write ever (or the file vanished): create it.
            try? data.write(to: fileURL)
        }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              NetworkLog.shouldRotate(fileSizeBytes: size) else { return }
        let old = folderURL.appendingPathComponent("network.log.1")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: fileURL, to: old)
    }
}
