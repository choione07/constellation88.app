import ActivityKit
import Foundation

// Set to false before publishing to App Store
private let DEBUG_LIVE_ACTIVITY = true

private func debugLog(_ message: String) {
    if DEBUG_LIVE_ACTIVITY {
        print(message)
    }
}

/// Manages Live Activities for the Constellation app
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var constellationActivity: Activity<ConstellationActivityAttributes>?
    private var moonActivity: Activity<MoonActivityAttributes>?

    /// Tracks the pending start task so it can be cancelled if the app foregrounds before it runs.
    private var pendingStartTask: Task<Void, Never>?

    /// Maximum duration for Live Activities (1 hour)
    private let maxDuration: TimeInterval = 1 * 60 * 60

    private init() {}

    // MARK: - Public API

    /// Starts a Live Activity based on the current view context.
    /// Should only be called when the app is going to the background.
    func startActivityIfNeeded(caller: String = "unknown") {
        pendingStartTask?.cancel()
        pendingStartTask = Task {
            guard !Task.isCancelled else { return }
            await _startActivityIfNeeded(caller: caller)
        }
    }

    /// Ends all active Live Activities, including any orphaned from previous sessions.
    func endAllActivities(caller: String = "unknown") {
        // Cancel any in-flight start so it can't race and restart an activity after we end.
        pendingStartTask?.cancel()
        pendingStartTask = nil
        Task {
            await _endAllActivities()
        }
    }

    /// Ends the moon Live Activity. Call from MoonPhaseView when leaving the tab.
    func endMoonActivity(caller: String = "unknown") {
        Task {
            await _endAllMoonActivities()
        }
    }

    /// Ends the constellation Live Activity. Call from ConstellationDetailView when navigating away.
    func endConstellationActivity(caller: String = "unknown") {
        Task {
            await _endAllConstellationActivities()
        }
    }

    // MARK: - Private async implementation

    private func _startActivityIfNeeded(caller: String) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("🔴 LiveActivity: areActivitiesEnabled=false. Go to iOS Settings → \(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "App") → Live Activities and enable it.")
            return
        }
        guard UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true else {
            print("🔴 LiveActivity: disabled by user in app Settings tab.")
            return
        }
        guard !Task.isCancelled else { return }

        let context = ViewStateManager.shared.currentContext

        switch context {
        case .constellationDetail(let constellation):
            await _endAllMoonActivities()
            guard !Task.isCancelled else { return }
            await _startConstellationActivity(constellation)
        case .moonPhase(let moon):
            await _endAllConstellationActivities()
            guard !Task.isCancelled else { return }
            await _startMoonActivity(moon)
        case .other:
            break
        }
    }

    private func _endAllActivities() async {
        await _endAllConstellationActivities()
        await _endAllMoonActivities()
    }

    // MARK: - Constellation Activity

    private func _startConstellationActivity(_ context: ViewStateManager.ConstellationContext) async {
        // End ALL existing constellation activities (including orphaned from previous sessions)
        await _endAllConstellationActivities()

        let normalizedStars = normalizeStarPositions(context.stars)

        let attributes = ConstellationActivityAttributes(
            constellationId: context.id,
            name: context.name,
            meaning: context.meaning,
            centerRa: context.centerRa,
            centerDec: context.centerDec,
            hemisphere: context.hemisphere,
            normalizedStars: normalizedStars,
            connections: context.connections,
            startTime: Date()
        )

        let contentState = ConstellationActivityAttributes.ContentState(lastUpdated: Date())
        let activityContent = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(maxDuration)
        )

        do {
            constellationActivity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
        } catch {
            print("🔴 Failed to start constellation Live Activity: \(error)")
        }
    }

    private func _endAllConstellationActivities() async {
        for activity in Activity<ConstellationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        constellationActivity = nil
    }

    // MARK: - Moon Activity

    private func _startMoonActivity(_ context: ViewStateManager.MoonContext) async {
        // End ALL existing moon activities (including orphaned from previous sessions)
        await _endAllMoonActivities()

        let riseHours = sanitizeMoonEventHours(context.riseHours)
        let setHours = sanitizeMoonEventHours(context.setHours)

        let attributes = MoonActivityAttributes(
            selectedDate: context.selectedDate,
            startTime: Date()
        )

        let contentState = MoonActivityAttributes.ContentState(
            phase: context.phase,
            illumination: context.illumination,
            phaseName: context.phaseName,
            riseHours: riseHours,
            setHours: setHours,
            lastUpdated: Date()
        )

        let activityContent = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(maxDuration)
        )

        do {
            moonActivity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
        } catch {
            print("🔴 Failed to start moon Live Activity: \(error)")
        }
    }

    private func _endAllMoonActivities() async {
        for activity in Activity<MoonActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        moonActivity = nil
    }

    // MARK: - Helpers

    /// Normalize star positions to -1...1 range for widget rendering
    private func normalizeStarPositions(_ stars: [ViewStateManager.ConstellationContext.StarPosition]) -> [[Double]] {
        guard !stars.isEmpty else { return [] }

        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity

        for star in stars {
            minX = min(minX, star.x)
            maxX = max(maxX, star.x)
            minY = min(minY, star.y)
            maxY = max(maxY, star.y)
        }

        let width = maxX - minX
        let height = maxY - minY

        guard width > 0 && height > 0 else {
            return stars.map { _ in [0.0, 0.0] }
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let maxDimension = max(width, height)

        return stars.map { star in
            let normalizedX = (star.x - centerX) / (maxDimension / 2)
            let normalizedY = (star.y - centerY) / (maxDimension / 2)
            return [normalizedX, normalizedY]
        }
    }

    private func sanitizeMoonEventHours(_ hours: Double) -> Double {
        guard hours.isFinite, hours >= 0 else { return -1 }
        return hours
    }
}
