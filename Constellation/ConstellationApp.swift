import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

@main
struct ConstellationApp: App {
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Task.detached(priority: .utility) {
            await ConstellationMatcher.shared.prepare()
        }
        _ = NotificationManager.shared
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .onDisappear {
                        requestPermissionsIfNeeded()
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }

    private func requestPermissionsIfNeeded() {
        Task {
            // Notification permission
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                await NotificationManager.shared.refreshAuthStatus()
                if granted {
                    UserDefaults.standard.set(true, forKey: "moonNotificationsEnabled")
                }
            } else if settings.authorizationStatus == .authorized {
                // Permission already granted — enable moon notifications if the user hasn't explicitly configured it yet
                if UserDefaults.standard.object(forKey: "moonNotificationsEnabled") == nil {
                    UserDefaults.standard.set(true, forKey: "moonNotificationsEnabled")
                }
            }

            // Location permission
            LocationManager.shared.requestLocation()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .inactive:
            break

        case .active:
            LiveActivityManager.shared.endAllActivities(caller: "ConstellationApp.active")
            rescheduleNotificationsIfNeeded()

        case .background:
            break

        @unknown default:
            break
        }
    }

    private func rescheduleNotificationsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "moonNotificationsEnabled"),
              let coord = LocationManager.shared.coordinate else { return }

        let lastScheduledKey = "moonNotificationsLastScheduled"
        if let last = UserDefaults.standard.object(forKey: lastScheduledKey) as? Date,
           Calendar.current.isDateInToday(last) { return }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            NotificationManager.shared.scheduleMoonNotifications(
                latitude: coord.latitude,
                longitude: coord.longitude
            )
            UserDefaults.standard.set(Date(), forKey: lastScheduledKey)
        }
    }

    private func configureAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.backgroundEffect = nil
        navAppearance.shadowColor = .clear
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = .clear
        tabAppearance.backgroundEffect = nil
        tabAppearance.shadowColor = .clear

        let selectedPurple = UIColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 1.0)
        func applyTabColors(to layout: UITabBarItemAppearance) {
            layout.selected.iconColor = selectedPurple
            layout.selected.titleTextAttributes = [.foregroundColor: selectedPurple]
            layout.normal.iconColor = UIColor.white.withAlphaComponent(0.5)
            layout.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.5)]
        }

        applyTabColors(to: tabAppearance.stackedLayoutAppearance)
        applyTabColors(to: tabAppearance.inlineLayoutAppearance)
        applyTabColors(to: tabAppearance.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
