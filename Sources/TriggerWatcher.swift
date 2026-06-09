import Foundation

/// Watches a small command file for external triggers (e.g. from the AAA app).
/// Another process writes a command word ("start", "stop", "toggle", "enter")
/// to the file; each write fires `onCommand` on the main queue.
///
/// Writers should append a unique nonce after the command (e.g. "start 1718500000")
/// so two identical commands in a row still register as a file change. Only the
/// first whitespace-separated token is treated as the command.
final class TriggerWatcher {
    static let defaultPath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/SimpleDictation/trigger")

    private let path: String
    private let onCommand: (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(path: String = TriggerWatcher.defaultPath, onCommand: @escaping (String) -> Void) {
        self.path = path
        self.onCommand = onCommand

        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        arm()
    }

    private func arm() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // File may not exist yet — retry shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.arm() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self = self, let src = src else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced — tear down and re-arm against the new inode
                src.cancel()
                return
            }
            self.fire()
        }
        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
            // Recreate the file if it's gone, then re-arm
            if !FileManager.default.fileExists(atPath: self.path) {
                FileManager.default.createFile(atPath: self.path, contents: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.arm() }
        }
        source = src
        src.resume()
    }

    private func fire() {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        guard let token = contents.split(whereSeparator: { $0.isWhitespace }).first else { return }
        let cmd = String(token).lowercased()
        guard !cmd.isEmpty else { return }
        onCommand(cmd)
    }
}
