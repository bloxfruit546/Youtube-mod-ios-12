import Foundation
import Darwin

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.litetube5s.logger", qos: .utility)
    private let maxFileSizeBytes: UInt64 = 512 * 1024 // 512 KB rotating cap
    private let dateFormatter: DateFormatter

    let logFileURL: URL
    let backupLogFileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.logFileURL = docs.appendingPathComponent("logs.txt")
        self.backupLogFileURL = docs.appendingPathComponent("logs.prev.txt")

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dateFormatter = df

        ensureLogFileExists()
    }

    private func ensureLogFileExists() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
    }

    func log(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        queue.async { [weak self] in
            self?.appendLine(line)
        }
    }

    func info(_ message: String) {
        log("INFO", message)
    }

    func warn(_ message: String) {
        log("WARN", message)
    }

    func error(_ message: String) {
        log("ERROR", message)
    }

    func network(_ message: String) {
        log("NET", message)
    }

    func crash(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [CRASH] \(message)\n"
        queue.sync {
            appendLine(line)
        }
    }

    private func appendLine(_ line: String) {
        ensureLogFileExists()
        rotateIfNeeded()
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= maxFileSizeBytes else {
            return
        }
        try? FileManager.default.removeItem(at: backupLogFileURL)
        try? FileManager.default.moveItem(at: logFileURL, to: backupLogFileURL)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
    }

    func readLogs(maxTailBytes: Int = 64 * 1024) -> String {
        return queue.sync {
            guard let data = try? Data(contentsOf: logFileURL) else {
                return "(Chưa có log)"
            }
            let slice: Data
            if data.count > maxTailBytes {
                slice = data.subdata(in: (data.count - maxTailBytes)..<data.count)
            } else {
                slice = data
            }
            let text = String(data: slice, encoding: .utf8) ?? "(Không đọc được UTF-8)"
            return text.isEmpty ? "(File log trống)" : text
        }
    }

    func clearLogs() {
        queue.sync {
            try? FileManager.default.removeItem(at: backupLogFileURL)
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        info("Đã xóa log bởi người dùng.")
    }
}

enum CrashCatcher {
    static func install() {
        _ = CrashCatcherSignalPath.pathCString

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let msg = "Uncaught NSException: \(exception.name.rawValue) - \(exception.reason ?? "nil")\nStack:\n\(symbols)"
            AppLogger.shared.crash(msg)
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            signal(sig, crashSignalHandler)
        }
    }
}

private func crashSignalHandler(_ sig: Int32) {
    // Async-signal-safe write directly to logs.txt via POSIX open/write/close
    if let pathPtr = CrashCatcherSignalPath.pathCString {
        let fd = open(pathPtr, O_WRONLY | O_CREAT | O_APPEND, mode_t(0o644))
        if fd >= 0 {
            let prefix = "\n[CRASH] Fatal POSIX signal: "
            _ = prefix.withCString { ptr in
                write(fd, ptr, strlen(ptr))
            }
            var numBuf: [CChar] = Array(repeating: 0, count: 16)
            var v = sig
            var idx = 0
            if v == 0 {
                numBuf[idx] = 48
                idx += 1
            } else {
                var digits: [CChar] = []
                while v > 0 {
                    digits.append(CChar(48 + (v % 10)))
                    v /= 10
                }
                for d in digits.reversed() {
                    numBuf[idx] = d
                    idx += 1
                }
            }
            numBuf[idx] = 10 // '\n'
            idx += 1
            _ = numBuf.withUnsafeBufferPointer { buf in
                write(fd, buf.baseAddress, idx)
            }
            close(fd)
        }
    }
    signal(sig, nil)
    raise(sig)
}

private enum CrashCatcherSignalPath {
    static let pathCString: UnsafeMutablePointer<CChar>? = strdup(AppLogger.shared.logFileURL.path)
}
