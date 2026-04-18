import Foundation
import CoreServices

enum LogTail {
    final class Reader {
        private var offsets: [String: UInt64] = [:]
        private var carry: [String: String] = [:]

        func readNew(url: URL) -> [String] {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? handle.close() }
            let start = offsets[url.path] ?? 0
            do { try handle.seek(toOffset: start) } catch { return [] }
            let data: Data
            do { data = try handle.readToEnd() ?? Data() } catch { return [] }
            let newOffset = handle.offsetInFile
            offsets[url.path] = newOffset
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }
            let combined = (carry[url.path] ?? "") + text
            let endsWithNewline = combined.hasSuffix("\n")
            var parts = combined.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
            if !endsWithNewline, !parts.isEmpty {
                carry[url.path] = parts.removeLast()
            } else {
                carry[url.path] = nil
            }
            return parts.filter { !$0.isEmpty }
        }
    }

    final class Watcher {
        private var stream: FSEventStreamRef?
        private var timer: DispatchSourceTimer?
        private let onChange: () -> Void
        private let directory: String

        init(directory: String, onChange: @escaping () -> Void) {
            self.directory = directory
            self.onChange = onChange
        }

        deinit {
            stop()
        }

        func start() {
            startFSEvents()
            startPollingFallback()
        }

        func stop() {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                self.stream = nil
            }
            timer?.cancel()
            timer = nil
        }

        private func startFSEvents() {
            var ctx = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, clientInfo, _, _, _, _ in
                let watcher = Unmanaged<Watcher>.fromOpaque(clientInfo!).takeUnretainedValue()
                watcher.onChange()
            }
            stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &ctx,
                [directory] as CFArray,
                UInt64(kFSEventStreamEventIdSinceNow),
                0.05,
                UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            )
            if let stream {
                FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
                FSEventStreamStart(stream)
            }
        }

        private func startPollingFallback() {
            let timerSource = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            timerSource.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
            timerSource.setEventHandler { [weak self] in self?.onChange() }
            timerSource.resume()
            timer = timerSource
        }
    }
}
