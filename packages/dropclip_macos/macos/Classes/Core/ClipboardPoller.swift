import AppKit

/// Runs a [ClipboardWatcher] on a timer with the adaptive interval of
/// PROTO-DC-V2.0 §14.1 / §16: 200 ms when there was user input in the last
/// 30 s, 1,000 ms when idle and 2,000 ms while the screen is locked. Must be
/// started on a thread with a run loop (the main thread in the app).
public final class ClipboardPoller {
    public static let activeInterval: TimeInterval = 0.2
    public static let idleInterval: TimeInterval = 1.0
    public static let lockedInterval: TimeInterval = 2.0
    public static let activeWindow: TimeInterval = 30

    public static func interval(secondsSinceInput: TimeInterval, screenLocked: Bool) -> TimeInterval {
        if screenLocked { return lockedInterval }
        return secondsSinceInput < activeWindow ? activeInterval : idleInterval
    }

    /// Seconds since the last keyboard or mouse event in this login session.
    public static func systemSecondsSinceInput() -> TimeInterval {
        // kCGAnyInputEventType
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private let watcher: ClipboardWatcher
    private let secondsSinceInput: () -> TimeInterval
    private let onChange: (ClipSnapshot) -> Void
    private var timer: Timer?
    private var lockObservers: [NSObjectProtocol] = []
    var screenLocked = false
    public private(set) var isRunning = false

    public init(
        watcher: ClipboardWatcher,
        secondsSinceInput: @escaping () -> TimeInterval = ClipboardPoller.systemSecondsSinceInput,
        onChange: @escaping (ClipSnapshot) -> Void
    ) {
        self.watcher = watcher
        self.secondsSinceInput = secondsSinceInput
        self.onChange = onChange
    }

    var currentInterval: TimeInterval {
        Self.interval(secondsSinceInput: secondsSinceInput(), screenLocked: screenLocked)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = DistributedNotificationCenter.default()
        lockObservers = [
            center.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in self?.screenLocked = true },
            center.addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
            ) { [weak self] _ in self?.screenLocked = false },
        ]
        scheduleNext()
    }

    public func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        let center = DistributedNotificationCenter.default()
        lockObservers.forEach { center.removeObserver($0) }
        lockObservers.removeAll()
    }

    // A one-shot timer re-armed after every poll, so the interval adapts.
    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) {
            [weak self] _ in
            guard let self = self, self.isRunning else { return }
            if let snapshot = self.watcher.poll() { self.onChange(snapshot) }
            self.scheduleNext()
        }
    }
}
