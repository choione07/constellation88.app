import SwiftUI
import UIKit

struct ConstellationCanvasView: View {
    @State private var stars: [CGPoint] = []
    @State private var edges: [[Int]] = []
    @State private var currentStarIndex: Int = -1
    @State private var isSubmitted = false
    @State private var isLoading = false
    @State private var matchResults: [MatchResult] = []
    @State private var selectedMatchIndex: Int = -1
    @State private var canvasSize: CGSize = .zero

    private let maxStars = 30
    private let starClickThreshold: CGFloat = 25

    var selectedMatch: MatchResult? {
        guard !matchResults.isEmpty,
              selectedMatchIndex >= 0,
              selectedMatchIndex < matchResults.count else { return nil }
        return matchResults[selectedMatchIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.05, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height

                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Create")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)

                            Spacer()

                            Text("Stars: \(stars.count) / \(maxStars)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.9))
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .offset(y: 4)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                        if isLandscape {
                            // Landscape: canvas left, cards right
                            HStack(alignment: .top, spacing: 12) {
                                canvasPanel
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                if isSubmitted && !matchResults.isEmpty {
                                    ScrollView(.vertical, showsIndicators: false) {
                                        VStack(spacing: 10) {
                                            ForEach(Array(matchResults.enumerated()), id: \.element.id) { index, result in
                                                CandidateCard(
                                                    result: result,
                                                    isSelected: index == selectedMatchIndex,
                                                    onTap: {
                                                        withAnimation(.easeInOut(duration: 0.3)) {
                                                            selectedMatchIndex = index
                                                        }
                                                    }
                                                )
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                    .frame(width: 124)
                                }
                            }
                            .padding(.horizontal)
                            .frame(maxHeight: .infinity)
                        } else {
                            // Portrait: canvas fills space, cards + controls stick to bottom
                            canvasPanel
                                .padding(.horizontal)
                                .frame(maxHeight: .infinity)

                            
                            if isSubmitted && !matchResults.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(matchResults.enumerated()), id: \.element.id) { index, result in
                                            CandidateCard(
                                                result: result,
                                                isSelected: index == selectedMatchIndex,
                                                onTap: {
                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        selectedMatchIndex = index
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .frame(minWidth: geometry.size.width, alignment: .center)
                                    .padding(.vertical, 12)
                                }
                                .padding(.top, 8)
                            }
                        }

                        // Controls
                        HStack(spacing: 16) {
                            clearButton
                            primaryActionButton
                        }
                        .padding()
                    }
                }

                // Loading overlay
                if isLoading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Finding your constellation...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                ViewStateManager.shared.clearContext()
            }
            .task {
                await ConstellationMatcher.shared.prepare()
            }
        }
    }

    private var canvasPanel: some View {
        ZStack {
            GeometryReader { geometry in
                let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                let layerScale: Double = isIPad ? (geometry.size.width > geometry.size.height ? 0.80 : 0.65) : 0.85

                ZStack {
                    MatchIllustrationLayer(
                        constellation: isSubmitted ? selectedMatch.flatMap { ConstellationMatcher.shared.getConstellation(id: $0.id) } : nil,
                        canvasSize: geometry.size,
                        scale: layerScale
                    )

                    Canvas { context, size in
                        guard size.width > 0, size.height > 0 else { return }
                        let drawScale: Double = UIDevice.current.userInterfaceIdiom == .pad ? (size.width > size.height ? 0.80 : 0.65) : 0.85

                        if isSubmitted, let match = selectedMatch {
                            drawMatchedConstellation(match: match, in: context, size: size, scale: drawScale)
                            drawUserStarsMatched(match: match, in: context, size: size, scale: drawScale)
                        } else {
                            drawEdges(in: context)
                            drawStars(in: context)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard !isSubmitted else { return }
                                handleTap(at: value.location)
                            }
                    )
                }
                .onAppear {
                    canvasSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    canvasSize = newSize
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var clearButton: some View {
        Button {
            clearAll()
        } label: {
            Label("Clear All", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(stars.isEmpty && !isSubmitted ? .white.opacity(0.3) : .red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .disabled(stars.isEmpty && !isSubmitted)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if isSubmitted, let match = selectedMatch,
           let constellation = ConstellationMatcher.shared.getConstellation(id: match.id) {
            NavigationLink {
                ConstellationDetailView(constellation: constellation)
            } label: {
                Label("View Details", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.4), lineWidth: 0.5)
                    )
            }
        } else {
            Button {
                submitConstellation()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Submit", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(stars.count < 3 ? .white.opacity(0.3) : .white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(stars.count < 3 ? .white.opacity(0.2) : .white.opacity(0.4), lineWidth: 0.5)
                )
            }
            .disabled(stars.count < 3 || isLoading)
        }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        var clickedStarIndex = -1
        for (index, star) in stars.enumerated() {
            let distance = hypot(location.x - star.x, location.y - star.y)
            if distance <= starClickThreshold {
                clickedStarIndex = index
                break
            }
        }

        if clickedStarIndex != -1 {
            if currentStarIndex != -1 && currentStarIndex != clickedStarIndex {
                if !edgeExists(currentStarIndex, clickedStarIndex) {
                    edges.append([currentStarIndex, clickedStarIndex])
                }
            }
            currentStarIndex = clickedStarIndex
        } else {
            guard stars.count < maxStars else { return }
            let newStarIndex = stars.count
            stars.append(location)
            if currentStarIndex != -1 {
                edges.append([currentStarIndex, newStarIndex])
            }
            currentStarIndex = newStarIndex
        }
    }

    private func edgeExists(_ idx1: Int, _ idx2: Int) -> Bool {
        return edges.contains { edge in
            (edge[0] == idx1 && edge[1] == idx2) || (edge[0] == idx2 && edge[1] == idx1)
        }
    }

    // MARK: - Normal Drawing

    private func drawEdges(in context: GraphicsContext) {
        guard !edges.isEmpty, !stars.isEmpty else { return }

        for edge in edges {
            guard edge.count == 2, edge[0] < stars.count, edge[1] < stars.count else { continue }
            let star1 = stars[edge[0]]
            let star2 = stars[edge[1]]

            var path = Path()
            path.move(to: star1)
            path.addLine(to: star2)

            context.stroke(
                path,
                with: .color(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.6)),
                lineWidth: 2
            )
        }
    }

    private func drawStars(in context: GraphicsContext) {
        guard !stars.isEmpty else { return }

        for (index, star) in stars.enumerated() {
            drawStar(at: star, isCurrent: index == currentStarIndex, isUser: true, in: context)
        }
    }

    // MARK: - Matched Drawing

    private func drawMatchedConstellation(match: MatchResult, in context: GraphicsContext, size: CGSize, scale: Double) {
        guard let constData = ConstellationMatcher.shared.getConstellationData(id: match.id),
              let constInfo = ConstellationMatcher.shared.getConstellation(id: match.id) else { return }

        let illustrationSize = min(size.width, size.height) * scale
        let stars = constData.pointsRaw

        guard !stars.isEmpty else { return }

        // Calculate bounds
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for star in stars {
            minX = min(minX, star.x)
            maxX = max(maxX, star.x)
            minY = min(minY, star.y)
            maxY = max(maxY, star.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return }

        // Scale calculation (same as website)
        let targetSize = illustrationSize * 0.8
        let scaleVal = min(targetSize / width, targetSize / height)
        let constellationScale = constInfo.constellationScale
        let finalScale = scaleVal * constellationScale

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let offsetX = size.width / 2 - centerX * finalScale
        let offsetY = size.height / 2 + centerY * finalScale

        // Shifts
        let xShiftPixels = constInfo.xShift * illustrationSize
        let yShiftPixels = constInfo.yShift * illustrationSize

        // Apply constellation rotation
        let rotationRad = constInfo.constellationRotation * .pi / 180

        // Transform function
        func transform(_ point: CGPoint) -> CGPoint {
            let px = point.x * finalScale + offsetX + xShiftPixels
            let py = -point.y * finalScale + offsetY + yShiftPixels

            // Rotate around canvas center
            let dx = px - size.width / 2
            let dy = py - size.height / 2
            let rotatedX = dx * cos(rotationRad) - dy * sin(rotationRad)
            let rotatedY = dx * sin(rotationRad) + dy * cos(rotationRad)

            return CGPoint(x: rotatedX + size.width / 2, y: rotatedY + size.height / 2)
        }

        // Draw constellation edges (golden color)
        context.stroke(
            Path { path in
                for edge in constData.edges {
                    guard edge.count == 2, edge[0] < stars.count, edge[1] < stars.count else { continue }
                    let p1 = transform(stars[edge[0]])
                    let p2 = transform(stars[edge[1]])
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
            },
            with: .color(Color(red: 1, green: 0.78, blue: 0.4).opacity(0.5)),
            lineWidth: 2
        )

        // Draw constellation stars
        for star in stars {
            let pos = transform(star)
            drawConstellationStar(at: pos, in: context)
        }
    }

    private func drawUserStarsMatched(match: MatchResult, in context: GraphicsContext, size: CGSize, scale: Double) {
        guard !stars.isEmpty,
              let constData = ConstellationMatcher.shared.getConstellationData(id: match.id),
              let constInfo = ConstellationMatcher.shared.getConstellation(id: match.id) else { return }

        let illustrationSize = min(size.width, size.height) * scale

        // Normalize user stars
        let normalized = normalizePoints(stars)
        guard normalized.scale > 0 else { return }

        // Rotate user points by match angle
        let matchRad: Double = match.angle * .pi / 180
        let cosMatch: Double = cos(matchRad)
        let sinMatch: Double = sin(matchRad)
        var rotatedUser: [CGPoint] = []
        for point in normalized.points {
            let newX: Double = point.x * cosMatch - point.y * sinMatch
            let newY: Double = point.x * sinMatch + point.y * cosMatch
            rotatedUser.append(CGPoint(x: newX, y: newY))
        }

        // Calculate constellation bounds for scaling
        let constStars = constData.pointsRaw
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for star in constStars {
            minX = min(minX, star.x)
            maxX = max(maxX, star.x)
            minY = min(minY, star.y)
            maxY = max(maxY, star.y)
        }
        let constWidth = maxX - minX
        let constHeight = maxY - minY

        let targetSize = illustrationSize * 0.8
        let constScale = min(targetSize / constWidth, targetSize / constHeight)
        let finalConstScale = constScale * constInfo.constellationScale

        // User pixel scale
        let userPixelScale = constData.scale * finalConstScale

        // Offsets
        let offsetX = size.width / 2
        let offsetY = size.height / 2
        let xShiftPixels = constInfo.xShift * illustrationSize
        let yShiftPixels = constInfo.yShift * illustrationSize

        // Constellation rotation
        let constRotationRad = constInfo.constellationRotation * .pi / 180

        // Transform function for user stars
        func transformUser(_ point: CGPoint) -> CGPoint {
            let px = point.x * userPixelScale + offsetX + xShiftPixels
            let py = -point.y * userPixelScale + offsetY + yShiftPixels

            // Apply constellation rotation
            let dx = px - size.width / 2
            let dy = py - size.height / 2
            let rotatedX = dx * cos(constRotationRad) - dy * sin(constRotationRad)
            let rotatedY = dx * sin(constRotationRad) + dy * cos(constRotationRad)

            return CGPoint(x: rotatedX + size.width / 2, y: rotatedY + size.height / 2)
        }

        // Draw user edges
        context.stroke(
            Path { path in
                for edge in edges {
                    guard edge.count == 2, edge[0] < rotatedUser.count, edge[1] < rotatedUser.count else { continue }
                    let p1 = transformUser(rotatedUser[edge[0]])
                    let p2 = transformUser(rotatedUser[edge[1]])
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
            },
            with: .color(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.6)),
            lineWidth: 2
        )

        // Draw user stars
        for (index, point) in rotatedUser.enumerated() {
            let pos = transformUser(point)
            drawStar(at: pos, isCurrent: index == currentStarIndex, isUser: true, in: context)
        }
    }

    // MARK: - Star Drawing Helpers

    private func drawStar(at point: CGPoint, isCurrent: Bool, isUser: Bool, in context: GraphicsContext) {
        let glowGradient = Gradient(colors: [
            Color.white.opacity(0.8),
            Color(red: 0.78, green: 0.7, blue: 1.0).opacity(0.6),
            Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0)
        ])

        let glowPath = Circle().path(in: CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30))
        context.fill(glowPath, with: .radialGradient(glowGradient, center: point, startRadius: 0, endRadius: 15))

        var starPath = Path()
        starPath.move(to: CGPoint(x: point.x, y: point.y - 6))
        starPath.addLine(to: CGPoint(x: point.x + 2, y: point.y - 2))
        starPath.addLine(to: CGPoint(x: point.x + 6, y: point.y))
        starPath.addLine(to: CGPoint(x: point.x + 2, y: point.y + 2))
        starPath.addLine(to: CGPoint(x: point.x, y: point.y + 6))
        starPath.addLine(to: CGPoint(x: point.x - 2, y: point.y + 2))
        starPath.addLine(to: CGPoint(x: point.x - 6, y: point.y))
        starPath.addLine(to: CGPoint(x: point.x - 2, y: point.y - 2))
        starPath.closeSubpath()

        let starColor = isCurrent ? Color(red: 1, green: 0.86, blue: 0.4) : Color.white
        context.fill(starPath, with: .color(starColor))

        let centerPath = Circle().path(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        context.fill(centerPath, with: .color(.white.opacity(0.9)))
    }

    private func drawConstellationStar(at point: CGPoint, in context: GraphicsContext) {
        let glowGradient = Gradient(colors: [
            Color(red: 1, green: 0.78, blue: 0.6).opacity(0.6),
            Color(red: 1, green: 0.7, blue: 0.4).opacity(0.4),
            Color(red: 1, green: 0.6, blue: 0.3).opacity(0)
        ])

        let glowPath = Circle().path(in: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        context.fill(glowPath, with: .radialGradient(glowGradient, center: point, startRadius: 0, endRadius: 12))

        let centerPath = Circle().path(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        context.fill(centerPath, with: .color(Color(red: 1, green: 0.78, blue: 0.6).opacity(0.9)))
    }

    // MARK: - Normalization Helper

    private func normalizePoints(_ points: [CGPoint]) -> (points: [CGPoint], scale: Double) {
        guard !points.isEmpty else { return ([], 0) }

        var centroidX: Double = 0, centroidY: Double = 0
        for p in points { centroidX += p.x; centroidY += p.y }
        centroidX /= Double(points.count)
        centroidY /= Double(points.count)

        let shifted = points.map { CGPoint(x: $0.x - centroidX, y: $0.y - centroidY) }

        var meanSq: Double = 0
        for p in shifted { meanSq += p.x * p.x + p.y * p.y }
        meanSq /= Double(shifted.count)
        let scale = sqrt(meanSq)

        guard scale > 0 else { return ([], 0) }

        let normalized = shifted.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
        return (normalized, scale)
    }

    // MARK: - Actions

    private func clearAll() {
        withAnimation(.smooth) {
            stars.removeAll()
            edges.removeAll()
            currentStarIndex = -1
            isSubmitted = false
            matchResults.removeAll()
            selectedMatchIndex = -1
        }
    }

    private func submitConstellation() {
        guard stars.count >= 3 else { return }

        isLoading = true

        let capturedStars = stars
        let capturedEdges = edges

        Task {
            let results = await ConstellationMatcher.shared.findMatches(
                userStars: capturedStars,
                userEdges: capturedEdges
            )

            await MainActor.run {
                isLoading = false
                matchResults = results

                if !results.isEmpty {
                    isSubmitted = true
                    selectedMatchIndex = 0
                }
            }
        }
    }
}

// MARK: - Candidate Card

struct CandidateCard: View {
    let result: MatchResult
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }

    private var matchPercentage: Int {
        let normalizedScore = min(max(1 - result.error, 0), 1)
        return Int((normalizedScore * 100).rounded())
    }

    private var backgroundFill: Color {
        isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05)
    }

    private var strokeColor: Color {
        isSelected ? Color.white.opacity(0.5) : Color.white.opacity(0.15)
    }

    private var strokeWidth: CGFloat {
        isSelected ? 2 : 0.5
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                if let constellation = ConstellationMatcher.shared.getConstellation(id: result.id) {
                    ConstellationThumbnail(illustration: constellation.illustration, size: isIPad ? 76 : 62)
                }
                Text(result.name)
                    .font(isIPad ? .footnote : .caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(matchPercentage)%")
                    .font(isIPad ? .caption : .caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: isIPad ? 100 : 86)
            .padding(.vertical, isIPad ? 14 : 11)
            .padding(.horizontal, isIPad ? 10 : 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(backgroundFill))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(strokeColor, lineWidth: strokeWidth))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Match Illustration Layer (with caching)

struct MatchIllustrationLayer: View {
    let constellation: Constellation?
    let canvasSize: CGSize
    var scale: Double = 0.85
    @State private var processedImage: UIImage?
    @State private var loadedConstellationId: String = ""

    var body: some View {
        ZStack {
            if let image = processedImage, constellation != nil {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(canvasSize.width, canvasSize.height) * scale,
                           height: min(canvasSize.width, canvasSize.height) * scale)
                    .opacity(0.7)
            }
        }
        .onAppear {
            guard let constellation = constellation,
                  loadedConstellationId != constellation.id else { return }
            loadedConstellationId = constellation.id
            ImageCache.shared.getProcessedImage(for: constellation.illustration) { image in
                self.processedImage = image
            }
        }
        .onChange(of: constellation?.id) { _, newId in
            guard let newId = newId, let constellation = constellation else {
                processedImage = nil
                loadedConstellationId = ""
                return
            }
            guard loadedConstellationId != newId else { return }
            loadedConstellationId = newId

            ImageCache.shared.getProcessedImage(for: constellation.illustration) { image in
                self.processedImage = image
            }
        }
    }
}

#Preview {
    ConstellationCanvasView()
}
