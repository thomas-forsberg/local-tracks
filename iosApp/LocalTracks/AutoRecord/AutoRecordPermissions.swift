import CoreLocation
import Shared
import UserNotifications

// The permissions auto-record needs beyond recording itself.
@MainActor
protocol AutoRecordPermissions {
    // Whether iOS lets the app watch home and start recording while it isn't open.
    var hasAlwaysLocation: Bool { get }
    // Asks for "Always" location access; returns whether the app has it afterwards.
    func requestAlwaysLocation() async -> Bool
    func requestNotifications() async
}

@MainActor
final class SystemAutoRecordPermissions: NSObject, AutoRecordPermissions, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    var hasAlwaysLocation: Bool { manager.authorizationStatus == .authorizedAlways }

    func requestAlwaysLocation() async -> Bool {
        if hasAlwaysLocation { return true }
        // iOS asks for When In Use first, then Always; each answer arrives through the delegate.
        if manager.authorizationStatus == .notDetermined {
            await ask { manager.requestWhenInUseAuthorization() }
        }
        if manager.authorizationStatus == .authorizedWhenInUse {
            await ask { manager.requestAlwaysAuthorization() }
        }
        return hasAlwaysLocation
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // iOS doesn't call back if it decides not to show the prompt (e.g. Always was already declined),
    // so give up waiting after a while.
    private func ask(_ request: () -> Void) async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            request()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.finishWaiting()
            }
        }
    }

    private func finishWaiting() {
        waiting?.resume()
        waiting = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.finishWaiting() }
    }
}

// Tells the user when auto-record does something, so a recording never runs without them knowing.
@MainActor
protocol AutoRecordNotifier {
    func recordingStarted(_ sport: Sport)
}

@MainActor
final class LocalNotifier: AutoRecordNotifier {
    func recordingStarted(_ sport: Sport) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(sport.title) recording started")
        content.body = String(localized: "Sporløs started recording automatically when you left home. It stops when you're back.")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "auto-record-started", content: content, trigger: nil))
    }
}
