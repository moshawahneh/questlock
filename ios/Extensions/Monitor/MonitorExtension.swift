import DeviceActivity

/// iOS starts this extension in its own short-lived process at the edges of each scheduled
/// DeviceActivity interval, even if the main app isn't running. All decisions live in `LockEngine`.
final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        LockEngine.intervalDidStart(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        LockEngine.intervalDidEnd(activity)
    }
}
