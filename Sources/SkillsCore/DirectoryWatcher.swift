import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything below the watched folders changes.
/// Events are coalesced by FSEvents, so a burst of writes produces one callback.
@MainActor
public final class DirectoryWatcher {
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    public init(paths: [URL], latency: TimeInterval = 0.4, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        // Only the skills folders themselves: the agent home folders change constantly with
        // session logs. A skills folder created later is picked up when the app is reactivated.
        let watched = Set(paths.map(\.path)).filter { FileManager.default.fileExists(atPath: $0) }
        guard !watched.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let pointer = UInt(bitPattern: info)
            MainActor.assumeIsolated {
                let raw = UnsafeMutableRawPointer(bitPattern: pointer)!
                Unmanaged<DirectoryWatcher>.fromOpaque(raw).takeUnretainedValue().onChange()
            }
        }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            Array(watched) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
