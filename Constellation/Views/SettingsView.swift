import ActivityKit
import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

private struct ObservedCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

struct SettingsView: View {
    @AppStorage("moonNotificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionAlert = false
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var supportsLiveActivityControls: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var areLiveActivitiesEnabledInSystem: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var observedCoordinate: ObservedCoordinate? {
        guard let coordinate = locationManager.coordinate else { return nil }
        return ObservedCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = ResponsiveLayoutMetrics(
                    width: geometry.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )
                let columns = metrics.columns(minItemWidth: 320, maxCount: 2)

                VStack(spacing: 0) {
                    HStack {
                        Text("More")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            notificationsCard
                            if supportsLiveActivityControls {
                                liveActivityCard
                            }
                            feedbackCard
                            informationCard
                        }
                        .frame(maxWidth: metrics.contentMaxWidth)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .toolbar(metrics.hidesTopLevelNavigationBar ? .hidden : .visible, for: .navigationBar)
            }
            .background(backgroundGradient)
            .onAppear {
                ViewStateManager.shared.clearContext()
                locationManager.requestLocation()
                Task {
                    await NotificationManager.shared.refreshAuthStatus()
                    authStatus = NotificationManager.shared.authStatus
                    rescheduleMoonNotificationsIfPossible()
                }
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                handleNotificationToggle(enabled)
            }
            .onChange(of: observedCoordinate) { _, _ in
                rescheduleMoonNotificationsIfPossible()
            }
            .alert("Notifications Disabled", isPresented: $showPermissionAlert) {
                Button("Open Settings") { openSystemSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable notifications for Constellation in iOS Settings.")
            }
        }
    }

    // MARK: - Cards

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Divider().background(.white.opacity(0.15))

            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.9))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Moon Rise & Set")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("Notify when the moon rises and sets each day")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(Color(red: 0.6, green: 0.4, blue: 0.9))
            }
            .padding(.top, 12)

            notificationStatusNote
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rescheduleMoonNotificationsIfPossible() {
        guard notificationsEnabled,
              authStatus == .authorized,
              let coord = locationManager.coordinate else {
            return
        }
        NotificationManager.shared.scheduleMoonNotifications(
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }

    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Activities")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Divider().background(.white.opacity(0.15))

            HStack(spacing: 12) {
                Image(systemName: "iphone.gen2")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.9))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lock Screen Live Activities")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("Show constellation and moon info when the app is in the background")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Toggle("", isOn: $liveActivityEnabled)
                    .labelsHidden()
                    .tint(Color(red: 0.6, green: 0.4, blue: 0.9))
                    .disabled(!areLiveActivitiesEnabledInSystem)
            }
            .padding(.top, 12)

            if !areLiveActivitiesEnabledInSystem {
                Label("Enable Live Activities in iOS Settings to use this feature.", systemImage: "rectangle.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Divider().background(.white.opacity(0.15))

            NavigationLink(destination: AboutView()) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.9))
                        .frame(width: 32)

                    Text("About")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Feedback & Contact")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Divider().background(.white.opacity(0.15))

            Button {
                if let url = URL(string: "mailto:one@choione.com") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.9))
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send Feedback")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        Text("one@choione.com")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var notificationStatusNote: some View {
        if notificationsEnabled {
            if authStatus == .denied {
                Button { openSystemSettings() } label: {
                    Label("Enable notifications in iOS Settings", systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 8)
            } else if locationManager.isDenied {
                Button { openSystemSettings() } label: {
                    Label("Enable location for accurate rise/set times", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 8)
            } else if locationManager.coordinate == nil {
                Label("Waiting for location to schedule notifications…", systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 8)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handleNotificationToggle(_ enabled: Bool) {
        guard enabled else {
            NotificationManager.shared.cancelMoonNotifications()
            return
        }

        Task {
            let granted = await NotificationManager.shared.requestPermission()
            authStatus = NotificationManager.shared.authStatus

            if granted {
                if let coord = locationManager.coordinate {
                    NotificationManager.shared.scheduleMoonNotifications(
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                }
                // When location isn't available yet, .onChange(of: locationManager.coordinate) schedules once it arrives
            } else {
                notificationsEnabled = false
                showPermissionAlert = true
            }
        }
    }
}

#Preview {
    SettingsView()
}
