import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let idPrefix = "moon-"
    private let calendar = Calendar.current

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func refreshAuthStatus() async {
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus
    }

    /// Requests authorization and returns whether it was granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthStatus()
            return granted
        } catch {
            await refreshAuthStatus()
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules moon rise/set notifications for the next 7 days.
    /// Requires a valid location. Replaces any previously scheduled moon notifications.
    func scheduleMoonNotifications(latitude: Double, longitude: Double) {
        // Synchronously cancel known IDs — avoids the async race condition where a
        // Task-based cancel runs *after* the new requests have already been added.
        let today = calendar.startOfDay(for: Date())
        var idsToRemove: [String] = []
        for offset in -7..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayId = dayIdentifier(for: day)
            idsToRemove.append("\(idPrefix)rise-\(dayId)")
            idsToRemove.append("\(idPrefix)set-\(dayId)")
            idsToRemove.append("\(idPrefix)riseSet-\(dayId)")
        }
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        let now = Date()

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            // Use noon of that day for phase/illumination context, but rise/set are day-specific
            guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { continue }

            let data = MoonCalculator.getMoonData(
                for: noon,
                latitude: latitude,
                longitude: longitude
            )

            let riseHours = data.riseHours
            let setHours = data.setHours
            let hasRise = riseHours.isFinite && riseHours >= 0
            let hasSet = setHours.isFinite && setHours >= 0

            guard hasRise || hasSet else { continue }

            let dayId = dayIdentifier(for: day)

            if hasRise && hasSet && abs(riseHours - setHours) < 1.0 {
                // Combined notification — fire at the earlier event
                let fireHours = min(riseHours, setHours)
                guard let fireDate = hoursToDate(fireHours, on: day), fireDate > now else { continue }
                schedule(
                    id: "\(idPrefix)riseSet-\(dayId)",
                    title: "Moonrise & Moonset",
                    body: "Moonrise at \(formatTime(riseHours)) and moonset at \(formatTime(setHours))",
                    at: fireDate
                )
            } else {
                if hasRise, let riseDate = hoursToDate(riseHours, on: day), riseDate > now {
                    schedule(
                        id: "\(idPrefix)rise-\(dayId)",
                        title: "Moonrise",
                        body: "The moon has started rising at \(formatTime(riseHours))",
                        at: riseDate
                    )
                }
                if hasSet, let setDate = hoursToDate(setHours, on: day), setDate > now {
                    schedule(
                        id: "\(idPrefix)set-\(dayId)",
                        title: "Moonset",
                        body: "The moon has started setting at \(formatTime(setHours))",
                        at: setDate
                    )
                }
            }
        }
    }

    /// Removes all pending moon notifications.
    func cancelMoonNotifications() {
        Task {
            let requests = await center.pendingNotificationRequests()
            let moonIds = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: moonIds)
        }
    }

    // MARK: - Helpers

    private func schedule(id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("Failed to schedule notification \(id): \(error)")
            }
        }
    }

    private func hoursToDate(_ hours: Double, on day: Date) -> Date? {
        let startOfDay = calendar.startOfDay(for: day)
        let seconds = hours * 3600
        return calendar.date(byAdding: .second, value: Int(seconds.rounded()), to: startOfDay)
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    private func formatTime(_ hours: Double) -> String {
        guard hours.isFinite, hours >= 0 else { return "—" }
        let adjusted = (hours + 24).truncatingRemainder(dividingBy: 24)
        let totalMinutes = Int((adjusted * 60.0).rounded()) % (24 * 60)
        let hour = totalMinutes / 60
        let minutes = totalMinutes % 60
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = ((hour + 11) % 12) + 1
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager {
    /// Show banner + play sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
