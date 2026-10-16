#if canImport(AppKit)
import AppKit
import VimouseCore

/// Whatever way the process ends, the user must not be left with a held mouse button,
/// a live event tap or an overlay on screen. The normal path is `applicationWillTerminate`;
/// this covers signals (Terminal ^C, `kill`, logout) and uncaught Objective-C exceptions.
/// A SIGKILL or a hard crash cannot be caught; the system then removes the tap and the
/// overlay with the process, and only a held button could remain (released by the next
/// real click).
enum Shutdown {
    private static var sources: [DispatchSourceSignal] = []
    private static var cleanup: (() -> Void)?

    static func install(cleanup: @escaping () -> Void) {
        self.cleanup = cleanup
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler {
                NSLog("vimouse: signal \(sig), shutting down")
                runCleanup()
                exit(0)
            }
            s.resume()
            sources.append(s)
        }
        NSSetUncaughtExceptionHandler { e in
            NSLog("vimouse: uncaught exception \(e)")
            Shutdown.runCleanup()
        }
        atexit { Pointer.releaseHeldButtons() }
    }

    static func runCleanup() {
        cleanup?()
        cleanup = nil
        Pointer.releaseHeldButtons()
    }
}
#endif
