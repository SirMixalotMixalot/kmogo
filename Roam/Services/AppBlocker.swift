import FamilyControls
import ManagedSettings
import DeviceActivity
import Observation
import Foundation

/// Uses opaque Screen Time tokens; app names and browsing history stay private.
@MainActor @Observable
final class AppBlocker {
    static let shared = AppBlocker()
    private let settings = ManagedSettingsStore(named: .init("roam.focus"))
    private let center = DeviceActivityCenter()
    private let activity = DeviceActivityName("roam.focus")
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "blocking.enabled") }
    }
    var selection: FamilyActivitySelection {
        didSet {
            if let data = try? JSONEncoder().encode(selection) {
                UserDefaults.standard.set(data, forKey: "blocking.selection")
            }
        }
    }
    #if targetEnvironment(simulator)
    static let isSimulatorDemo = true
    var demoAuthorized = false
    var demoApps: Set<String> = []
    var demoBlockingUntil: Date?
    #else
    static let isSimulatorDemo = false
    #endif

    var errorMessage: String?
    var requesting = false
    var authorized: Bool {
        #if targetEnvironment(simulator)
        return demoAuthorized
        #else
        return AuthorizationCenter.shared.authorizationStatus == .approved
        #endif
    }
    var hasSelection: Bool {
        #if targetEnvironment(simulator)
        return !demoApps.isEmpty
        #else
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
        #endif
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "blocking.enabled")
        selection = UserDefaults.standard.data(forKey: "blocking.selection")
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection()
    }

    func authorize() async -> Bool {
        #if targetEnvironment(simulator)
        return demoAuthorized
        #else
        requesting = true
        defer { requesting = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return authorized
        } catch {
            errorMessage = "Screen Time access wasn’t granted. You can try again to enable app blocking."
            return false
        }
        #endif
    }

    func stop() {
        #if targetEnvironment(simulator)
        demoBlockingUntil = nil
        #else
        center.stopMonitoring([activity])
        settings.clearAllSettings()
        #endif
    }

    func synchronize(until end: Date?) {
        stop()
        guard enabled, authorized, hasSelection, let end, end > Date() else { return }
        #if targetEnvironment(simulator)
        demoBlockingUntil = end
        #else
        // Device Activity requires a 15-minute interval. Only its end callback is used,
        // allowing even short runs to release their shields while Roam is suspended.
        let start = min(Date(), end.addingTimeInterval(-16 * 60))
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        do {
            try center.startMonitoring(activity, during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: start),
                intervalEnd: calendar.dateComponents(components, from: end), repeats: false))
            settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
            settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        } catch {
            // Never apply restrictions unless an independent unlock has been scheduled.
            errorMessage = "App blocking couldn’t start for this run. Your apps remain available. Try starting another run."
        }
        #endif
    }
}
