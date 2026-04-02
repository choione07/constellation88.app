import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @AppStorage("galleryViewMode") private var galleryViewMode: String = "grid"

    private var galleryIcon: String {
        galleryViewMode == "grid" ? "square.grid.2x2.fill" : "list.bullet"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Create", systemImage: "star.circle.fill", value: 0) {
                ConstellationCanvasView()
            }

            Tab("Gallery", systemImage: galleryIcon, value: 1) {
                GalleryView()
            }
            
            Tab("Moon", systemImage: "moon.stars.fill", value: 2) {
                MoonPhaseView()
            }
            
            Tab("More", systemImage: "ellipsis.circle.fill", value: 3) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
}
