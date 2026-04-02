import SwiftUI
import UIKit

struct GalleryView: View {
    @State private var constellations: [Constellation] = []
    @State private var searchText = ""
    @AppStorage("galleryViewMode") private var viewMode: String = "grid"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isGridMode: Bool {
        viewMode == "grid"
    }
    
    var filteredConstellations: [Constellation] {
        if searchText.isEmpty {
            return constellations
        }
        return constellations.filter { constellation in
            constellation.name.localizedCaseInsensitiveContains(searchText) ||
            constellation.meaning.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = ResponsiveLayoutMetrics(
                    width: geometry.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )
                let gridColumns = metrics.columns(
                    minItemWidth: metrics.isWideTablet ? 220 : 160,
                    maxCount: metrics.isWideTablet ? 4 : 3
                )
                let listColumns = metrics.isWideTablet ? metrics.columns(minItemWidth: 360, maxCount: 2) : [GridItem(.flexible())]
                let cardThumbnailSize: CGFloat = metrics.isTablet ? 180 : 150
                let listThumbnailSize: CGFloat = metrics.isTablet ? 72 : 60

                VStack(spacing: 0) {
                    HStack {
                        Text("Gallery")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            viewMode = isGridMode ? "list" : "grid"
                        } label: {
                            Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
                                .font(.title3)
                                .frame(
                                    width: metrics.isTablet ? 22 : 20,
                                    height: metrics.isTablet ? 22 : 20
                                )
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(metrics.isTablet ? 12 : 10)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                )
                        }
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Search constellations", text: $searchText)
                            .foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .frame(maxWidth: min(metrics.contentMaxWidth, 680))
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, 8)

                    ScrollView {
                        Group {
                            if isGridMode {
                                LazyVGrid(columns: gridColumns, spacing: metrics.cardSpacing) {
                                    ForEach(filteredConstellations) { constellation in
                                        ConstellationCard(
                                            constellation: constellation,
                                            thumbnailSize: cardThumbnailSize
                                        )
                                    }
                                }
                            } else {
                                LazyVGrid(columns: listColumns, spacing: 12) {
                                    ForEach(filteredConstellations) { constellation in
                                        ConstellationListRow(
                                            constellation: constellation,
                                            thumbnailSize: listThumbnailSize
                                        )
                                    }
                                }
                            }
                        }
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                        .frame(maxWidth: metrics.contentMaxWidth, alignment: .leading)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, metrics.isTablet ? 20 : 16)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                .task {
                    guard constellations.isEmpty else { return }
                    constellations = await ConstellationLoader.loadConstellations()
                    appDebugLog("🌌 Loaded \(constellations.count) constellations in gallery")

                    if let first = constellations.first {
                        appDebugLog("📝 First constellation: \(first.name), ID: '\(first.id)'")
                    }
                    if constellations.count > 1 {
                        appDebugLog("📝 Second constellation: \(constellations[1].name), ID: '\(constellations[1].id)'")
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// 그리드 카드
struct ConstellationCard: View {
    let constellation: Constellation
    let thumbnailSize: CGFloat

    var body: some View {
        NavigationLink(destination: ConstellationDetailView(constellation: constellation)) {
            VStack(alignment: .leading, spacing: 8) {
                ConstellationThumbnail(
                    illustration: constellation.illustration,
                    size: thumbnailSize
                )
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(constellation.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(constellation.meaning)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if constellation.id.isEmpty {
                appDebugLog("⚠️ Card has empty ID: \(constellation.name)")
            }
        }
    }
}

// 리스트 행
struct ConstellationListRow: View {
    let constellation: Constellation
    let thumbnailSize: CGFloat
    
    var body: some View {
        NavigationLink(destination: ConstellationDetailView(constellation: constellation)) {
            HStack(spacing: 16) {
                ConstellationThumbnail(
                    illustration: constellation.illustration,
                    size: thumbnailSize
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(constellation.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(constellation.meaning)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    
                    HStack {
                        Text(constellation.hemisphere)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        
                        Text(constellation.observableSeasons)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if constellation.id.isEmpty {
                appDebugLog("⚠️ Row has empty ID: \(constellation.name)")
            }
        }
    }
}

// 썸네일 이미지 로딩 (with caching)
struct ConstellationThumbnail: View {
    let illustration: String
    let size: CGFloat

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 12 : 8))
            } else {
                RoundedRectangle(cornerRadius: size > 100 ? 12 : 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                    }
            }
        }
        .onAppear {
            guard uiImage == nil else { return }
            ImageCache.shared.getProcessedImage(for: illustration) { image in
                self.uiImage = image
            }
        }
    }
}

#Preview {
    GalleryView()
}
