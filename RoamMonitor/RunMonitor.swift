import DeviceActivity
import ManagedSettings

final class RunMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ManagedSettingsStore(named: .init("roam.focus")).clearAllSettings()
    }
}
