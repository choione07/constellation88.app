import SwiftUI
import UIKit

struct ConstellationDetailView: View {
    let constellation: Constellation
    @State private var showStars = true
    @State private var showIllustration = true
    @State private var showDescription = true
    @State private var starData: ConstellationStars?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let metrics = ResponsiveLayoutMetrics(
                width: geometry.size.width,
                horizontalSizeClass: horizontalSizeClass
            )
            let isPadLandscape = metrics.isTablet && geometry.size.width > geometry.size.height
            let imageHeight: CGFloat = isPadLandscape
                ? max(460, geometry.size.height * 0.72)
                : metrics.isTablet ? 560 : 400
            let infoPanelWidth = metrics.splitPaneWidth(fraction: 0.38, minWidth: 300, maxWidth: 380)

            if isPadLandscape {
                // iPad landscape: fixed header, then two independent columns
                VStack(spacing: 0) {
                    headerSection
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.top, 32)
                        .padding(.bottom, 12)

                    HStack(alignment: .top, spacing: metrics.cardSpacing) {
                        // Left column: image centered, buttons pinned to bottom
                        VStack(spacing: 0) {
                            Spacer()
                            ConstellationImageView(
                                constellation: constellation,
                                starData: starData,
                                showStars: showStars,
                                showIllustration: showIllustration
                            )
                            .frame(height: imageHeight)
                            Spacer()
                            HStack(spacing: 12) {
                                toggleButton(title: "Stars", systemImage: "star.fill", isOn: $showStars)
                                toggleButton(title: "Illustration", systemImage: "photo.fill", isOn: $showIllustration)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Right column: independently scrollable info/description
                        ScrollView {
                            infoSection
                                .padding(.bottom, metrics.horizontalPadding)
                        }
                        .frame(width: infoPanelWidth)
                    }
                    .frame(maxWidth: metrics.contentMaxWidth, maxHeight: .infinity)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // iPhone + iPad portrait: single scrollable column
                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        headerSection
                        mediaSection(imageHeight: imageHeight)
                        infoSection
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.horizontalPadding)
                    .frame(maxWidth: .infinity)
                }
                .contentMargins(.top, 28, for: .scrollContent)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: constellation.id) {
            await loadAndRegisterStarData()
        }
        .onDisappear {
            // Only clear when app is still active (user navigated back).
            // Don't clear when the app is backgrounding — context is needed to start the activity.
            if scenePhase == .active {
                ViewStateManager.shared.clearConstellationDetailContext(id: constellation.id)
                LiveActivityManager.shared.endConstellationActivity(caller: "ConstellationDetailView.onDisappear")
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(constellation.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(constellation.meaning)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func mediaSection(imageHeight: CGFloat) -> some View {
        VStack(spacing: 20) {
            ConstellationImageView(
                constellation: constellation,
                starData: starData,
                showStars: showStars,
                showIllustration: showIllustration
            )
            .frame(height: imageHeight)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    toggleButton(title: "Stars", systemImage: "star.fill", isOn: $showStars)
                    toggleButton(title: "Illustration", systemImage: "photo.fill", isOn: $showIllustration)
                }

                VStack(spacing: 12) {
                    toggleButton(title: "Stars", systemImage: "star.fill", isOn: $showStars)
                    toggleButton(title: "Illustration", systemImage: "photo.fill", isOn: $showIllustration)
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                InfoRow(label: "Hemisphere", value: constellation.hemisphere)
                InfoRow(label: "Observable", value: constellation.observableSeasons)
                InfoRow(label: "Right Ascension", value: String(format: "%.2f°", constellation.centerRa))
                InfoRow(label: "Declination", value: String(format: "%.2f°", constellation.centerDec))
            }

            if !constellation.description.isEmpty {
                Divider()
                    .background(.white.opacity(0.2))

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDescription.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Description")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.6))
                                .rotationEffect(.degrees(showDescription ? 0 : -90))
                                .animation(.easeInOut(duration: 0.25), value: showDescription)
                        }
                    }
                    .buttonStyle(.plain)

                    if showDescription {
                        Text(constellation.description)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func toggleButton(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isOn.wrappedValue ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isOn.wrappedValue ? .white.opacity(0.3) : .white.opacity(0.15), lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadAndRegisterStarData() async {
        var loadedData: ConstellationStars?

        if !constellation.id.isEmpty {
            loadedData = await ConstellationStarLoader.getStars(for: constellation.id)
        }

        if loadedData == nil {
            loadedData = await ConstellationStarLoader.getStars(forIllustration: constellation.illustration)
        }

        starData = loadedData

        guard let data = loadedData else { return }

        let stars = data.stars.map { (x: $0.x, y: $0.y) }

        var hipToIndex: [String: Int] = [:]
        for (index, star) in data.stars.enumerated() {
            hipToIndex[star.hip] = index
        }

        var connections: [[Int]] = []
        for connection in data.connections {
            guard connection.count >= 2,
                  let index1 = hipToIndex[connection[0]],
                  let index2 = hipToIndex[connection[1]] else {
                continue
            }
            connections.append([index1, index2])
        }

        ViewStateManager.shared.registerConstellationDetail(
            id: constellation.id,
            name: constellation.name,
            meaning: constellation.meaning,
            centerRa: constellation.centerRa,
            centerDec: constellation.centerDec,
            hemisphere: constellation.hemisphere,
            stars: stars,
            connections: connections
        )
        // Start from foreground — ActivityKit forbids starting from background.
        LiveActivityManager.shared.startActivityIfNeeded(caller: "ConstellationDetailView")
    }
}

// 별자리 이미지 + 별 오버레이
struct ConstellationImageView: View {
    let constellation: Constellation
    let starData: ConstellationStars?
    let showStars: Bool
    let showIllustration: Bool

    var body: some View {
        GeometryReader { geometry in
            let displaySize = min(geometry.size.width, geometry.size.height)

            ZStack {
                // 1. Illustration layer (behind) - matching website z-index order
                if showIllustration {
                    IllustrationLayer(constellation: constellation)
                        .opacity(0.85)
                        .transition(.opacity)
                }

                // 2. Stars layer (on top)
                if showStars {
                    ConstellationStarsLayer(
                        constellation: constellation,
                        displaySize: displaySize,
                        starData: starData
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showStars)
            .animation(.easeInOut(duration: 0.25), value: showIllustration)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// 별자리 별 + 연결선 레이어 (웹사이트 로직과 동일하게)
struct ConstellationStarsLayer: View {
    let constellation: Constellation
    let displaySize: CGFloat
    let starData: ConstellationStars?

    var body: some View {
        Canvas { context, size in
            guard let starData = starData, !starData.stars.isEmpty else {
                return
            }

            // 1. 별자리 좌표 범위 계산 (stereographic coordinates)
            var minX = Double.infinity
            var maxX = -Double.infinity
            var minY = Double.infinity
            var maxY = -Double.infinity

            for star in starData.stars {
                minX = min(minX, star.x)
                maxX = max(maxX, star.x)
                minY = min(minY, star.y)
                maxY = max(maxY, star.y)
            }

            let width = maxX - minX
            let height = maxY - minY

            guard width > 0 && height > 0 else { return }

            // 2. 스케일 계산 (75% of display size)
            let targetSize = displaySize * 0.75
            let scaleX = targetSize / width
            let scaleY = targetSize / height
            let baseScale = min(scaleX, scaleY)

            // 3. constellation_scale 적용
            let scale = baseScale * constellation.constellationScale

            // 4. 중심점 계산
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2

            // 5. 오프셋 계산 (캔버스 중앙에 배치)
            var offsetX = size.width / 2 - centerX * scale
            var offsetY = size.height / 2 + centerY * scale  // Y 반전

            // 6. x_shift, y_shift 적용 (display size 기준)
            let xShiftPixels = constellation.xShift * displaySize
            let yShiftPixels = constellation.yShift * displaySize
            offsetX += xShiftPixels
            offsetY += yShiftPixels

            // 7. 회전 적용
            let rotationRadians = constellation.constellationRotation * .pi / 180
            let canvasCenterX = size.width / 2
            let canvasCenterY = size.height / 2

            // 좌표 변환 함수 (회전 포함)
            func transform(x: Double, y: Double) -> CGPoint {
                // 먼저 스케일 + 오프셋 적용
                let px = x * scale + offsetX
                let py = -y * scale + offsetY  // Y 반전

                // 캔버스 중심 기준으로 회전
                let dx = px - canvasCenterX
                let dy = py - canvasCenterY
                let rotatedX = dx * cos(rotationRadians) - dy * sin(rotationRadians)
                let rotatedY = dx * sin(rotationRadians) + dy * cos(rotationRadians)

                return CGPoint(
                    x: rotatedX + canvasCenterX,
                    y: rotatedY + canvasCenterY
                )
            }

            // 8. 별 위치 매핑
            var starPositions: [String: CGPoint] = [:]
            for star in starData.stars {
                starPositions[star.hip] = transform(x: star.x, y: star.y)
            }

            // 9. 연결선 그리기 (별 뒤에)
            for connection in starData.connections {
                guard connection.count == 2,
                      let start = starPositions[connection[0]],
                      let end = starPositions[connection[1]] else {
                    continue
                }

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                context.stroke(
                    path,
                    with: .color(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.5)),
                    lineWidth: 1.5
                )
            }

            // 10. 별 그리기
            for (_, position) in starPositions {
                drawStar(at: position, in: context)
            }
        }
    }

    private func drawStar(at point: CGPoint, in context: GraphicsContext) {
        let baseSize: CGFloat = 12
        let starSize: CGFloat = 5

        // 1. Glow effect
        let glowGradient = Gradient(colors: [
            Color.white.opacity(0.8),
            Color(red: 0.78, green: 0.7, blue: 1.0).opacity(0.6),
            Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0)
        ])

        let glowPath = Circle().path(in: CGRect(
            x: point.x - baseSize,
            y: point.y - baseSize,
            width: baseSize * 2,
            height: baseSize * 2
        ))

        context.fill(
            glowPath,
            with: .radialGradient(
                glowGradient,
                center: point,
                startRadius: 0,
                endRadius: baseSize
            )
        )

        // 2. 4-pointed star shape
        var starPath = Path()
        starPath.move(to: CGPoint(x: point.x, y: point.y - starSize))
        starPath.addLine(to: CGPoint(x: point.x + starSize/3, y: point.y - starSize/3))
        starPath.addLine(to: CGPoint(x: point.x + starSize, y: point.y))
        starPath.addLine(to: CGPoint(x: point.x + starSize/3, y: point.y + starSize/3))
        starPath.addLine(to: CGPoint(x: point.x, y: point.y + starSize))
        starPath.addLine(to: CGPoint(x: point.x - starSize/3, y: point.y + starSize/3))
        starPath.addLine(to: CGPoint(x: point.x - starSize, y: point.y))
        starPath.addLine(to: CGPoint(x: point.x - starSize/3, y: point.y - starSize/3))
        starPath.closeSubpath()

        context.fill(starPath, with: .color(.white))

        // 3. Bright center
        let centerPath = Circle().path(in: CGRect(
            x: point.x - 1.5,
            y: point.y - 1.5,
            width: 3,
            height: 3
        ))
        context.fill(centerPath, with: .color(.white.opacity(0.9)))
    }
}

// 일러스트 레이어 (with caching)
struct IllustrationLayer: View {
    let constellation: Constellation
    @State private var processedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = processedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(0.9)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .onAppear {
            guard processedImage == nil else { return }
            ImageCache.shared.getProcessedImage(for: constellation.illustration) { image in
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.processedImage = image
                    self.isLoading = false
                }
            }
        }
    }
}


struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    NavigationStack {
        ConstellationDetailView(constellation: Constellation(
            id: "Aql",
            name: "Aquila",
            meaning: "Eagle",
            illustration: "aquila.png",
            centerRa: 293.86593,
            centerDec: 5.092872,
            observableSeasons: "Summer, Early Fall",
            description: "A constellation in the northern sky.",
            constellationScale: 0.69,
            constellationRotation: -11,
            xShift: -0.08,
            yShift: 0.01,
            hemisphere: "Both"
        ))
    }
}
