import SwiftUI

struct AboutView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let metrics = ResponsiveLayoutMetrics(
                width: geometry.size.width,
                horizontalSizeClass: horizontalSizeClass
            )
            let summaryWidth = metrics.splitPaneWidth(fraction: 0.34, minWidth: 280, maxWidth: 320)

            ScrollView {
                VStack(spacing: 24) {
                    if metrics.isWideTablet {
                        HStack(alignment: .top, spacing: metrics.cardSpacing) {
                            summaryCard(iconSize: 148)
                                .frame(width: summaryWidth, alignment: .top)
                            detailsCard
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        summaryCard(iconSize: metrics.isTablet ? 140 : 120)
                        detailsCard
                    }

                    VStack(spacing: 6) {
                        Text("Data Attribution")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.5))

                        Text("Constellation illustrations and descriptions sourced from Stellarium, an open-source planetarium software.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: metrics.contentMaxWidth)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            ViewStateManager.shared.clearContext()
        }
    }

    private func summaryCard(iconSize: CGFloat) -> some View {
        VStack(spacing: 24) {
            AppIconView(size: iconSize)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Constellation Creator")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("About")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Create your own constellations by placing stars on the canvas. The app will match your creation with real constellations from the night sky.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Features")
                    .font(.headline)
                    .foregroundStyle(.white)

                FeatureRow(
                    icon: "star.circle.fill",
                    title: "Create Constellations",
                    description: "Draw up to 30 stars on the canvas"
                )

                FeatureRow(
                    icon: "sparkles",
                    title: "Pattern Matching",
                    description: "Find similar constellation patterns"
                )

                FeatureRow(
                    icon: "square.grid.2x2.fill",
                    title: "Gallery",
                    description: "Browse all 88 constellations"
                )

                FeatureRow(
                    icon: "moon.stars.fill",
                    title: "Moon Phases",
                    description: "Track the lunar cycle"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
        }
    }
}

// MARK: - App Icon View

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image("AboutIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            .shadow(color: .purple.opacity(0.3), radius: 20)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
