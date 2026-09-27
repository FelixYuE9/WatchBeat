import Foundation

/// Deterministic suspend/resume point for unit tests. No clock, no sleeping.
public final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func open() {
        lock.lock()
        isOpen = true
        let waiting = waiters
        waiters = []
        lock.unlock()
        for waiter in waiting { waiter.resume() }
    }

    public func wait() async {
        lock.lock()
        if isOpen {
            lock.unlock()
            return
        }
        lock.unlock()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
