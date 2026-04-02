import CoreGraphics
import Foundation

struct MatchResult: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let error: Double
    let positionError: Double
    let edgeScore: Double
    let angle: Double
}

struct NormalizedPoints: Sendable {
    let points: [CGPoint]
    let centroid: CGPoint
    let scale: Double
}

final class ConstellationMatcher {
    struct ConstellationMatchData: Sendable {
        let id: String
        let name: String
        let pointsRaw: [CGPoint]
        let pointsNorm: [CGPoint]
        let scale: Double
        let centroid: CGPoint
        let edges: [[Int]]
        let hipToIndex: [String: Int]
    }

    private struct Snapshot: Sendable {
        let constellationData: [String: ConstellationMatchData]
        let constellationsMap: [String: Constellation]
    }

    static let shared = ConstellationMatcher()

    private let lock = NSLock()
    private var snapshot: Snapshot?
    private var loadTask: Task<Snapshot, Never>?

    private init() {}

    func prepare() async {
        _ = await loadSnapshot()
    }

    func findMatches(userStars: [CGPoint], userEdges: [[Int]]) async -> [MatchResult] {
        let snapshot = await loadSnapshot()

        let normalizedUser = normalizePoints(userStars)
        guard normalizedUser.scale > 0 else {
            appDebugLog("User points are too close together")
            return []
        }

        var results: [MatchResult] = []

        for constellation in snapshot.constellationData.values {
            guard !constellation.pointsNorm.isEmpty else { continue }
            guard constellation.pointsRaw.count >= 3 else { continue }

            let starCount = constellation.pointsRaw.count
            let maxCount = max(starCount, userStars.count)
            let diffThreshold = max(5, Int(ceil(Double(maxCount) * 0.6)))

            if abs(starCount - userStars.count) > diffThreshold {
                continue
            }

            let scan = scanRotation(
                source: normalizedUser.points,
                target: constellation.pointsNorm,
                userEdges: userEdges,
                constEdges: constellation.edges
            )

            results.append(
                MatchResult(
                    id: constellation.id,
                    name: constellation.name,
                    error: scan.error,
                    positionError: scan.positionError,
                    edgeScore: scan.edgeScore,
                    angle: scan.angle
                )
            )
        }

        results.sort { $0.error < $1.error }
        return Array(results.prefix(4))
    }

    func getConstellation(id: String) -> Constellation? {
        withSnapshot { $0.constellationsMap[id] }
    }

    func getConstellationData(id: String) -> ConstellationMatchData? {
        withSnapshot { $0.constellationData[id] }
    }

    private func loadSnapshot() async -> Snapshot {
        if let snapshot = withSnapshot({ $0 }) {
            return snapshot
        }

        let task = lock.withLock { () -> Task<Snapshot, Never> in
            if let loadTask {
                return loadTask
            }

            let task = Task.detached(priority: .userInitiated) {
                await Self.buildSnapshot()
            }
            loadTask = task
            return task
        }

        let loaded = await task.value

        lock.withLock {
            snapshot = loaded
            loadTask = nil
        }

        return loaded
    }

    private func withSnapshot<T>(_ body: (Snapshot) -> T?) -> T? {
        lock.withLock {
            guard let snapshot else { return nil }
            return body(snapshot)
        }
    }

    private static func buildSnapshot() async -> Snapshot {
        let constellations = await ConstellationLoader.loadConstellations()
        let starsData = await ConstellationStarLoader.loadStars()

        let constellationsMap = Dictionary(uniqueKeysWithValues: constellations.map { ($0.id, $0) })
        var constellationData: [String: ConstellationMatchData] = [:]
        constellationData.reserveCapacity(starsData.count)

        for (id, stars) in starsData {
            var hipToIndex: [String: Int] = [:]
            var pointsRaw: [CGPoint] = []

            for (index, star) in stars.stars.enumerated() {
                hipToIndex[star.hip] = index
                pointsRaw.append(CGPoint(x: star.x, y: star.y))
            }

            var edges: [[Int]] = []
            for connection in stars.connections {
                guard connection.count == 2,
                      let idx1 = hipToIndex[connection[0]],
                      let idx2 = hipToIndex[connection[1]] else {
                    continue
                }
                edges.append([idx1, idx2])
            }

            let normalized = normalizePoints(pointsRaw)
            let name = constellationsMap[id]?.name ?? id

            constellationData[id] = ConstellationMatchData(
                id: id,
                name: name,
                pointsRaw: pointsRaw,
                pointsNorm: normalized.points,
                scale: normalized.scale,
                centroid: normalized.centroid,
                edges: edges,
                hipToIndex: hipToIndex
            )
        }

        appDebugLog("ConstellationMatcher loaded \(constellationData.count) constellations")
        return Snapshot(
            constellationData: constellationData,
            constellationsMap: constellationsMap
        )
    }

    private func normalizePoints(_ points: [CGPoint]) -> NormalizedPoints {
        Self.normalizePoints(points)
    }

    private static func normalizePoints(_ points: [CGPoint]) -> NormalizedPoints {
        guard !points.isEmpty else {
            return NormalizedPoints(points: [], centroid: .zero, scale: 0)
        }

        var centroidX: Double = 0
        var centroidY: Double = 0
        for point in points {
            centroidX += point.x
            centroidY += point.y
        }
        centroidX /= Double(points.count)
        centroidY /= Double(points.count)
        let centroid = CGPoint(x: centroidX, y: centroidY)

        let shifted = points.map { CGPoint(x: $0.x - centroidX, y: $0.y - centroidY) }

        var meanSq: Double = 0
        for point in shifted {
            meanSq += point.x * point.x + point.y * point.y
        }
        meanSq /= Double(shifted.count)
        let scale = sqrt(meanSq)

        guard scale > 0, !scale.isNaN else {
            return NormalizedPoints(points: [], centroid: centroid, scale: 0)
        }

        let normalized = shifted.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }

        return NormalizedPoints(points: normalized, centroid: centroid, scale: scale)
    }

    private func rotatePoints(_ points: [CGPoint], by theta: Double) -> [CGPoint] {
        let cos = cos(theta)
        let sin = sin(theta)
        return points.map { point in
            CGPoint(
                x: point.x * cos - point.y * sin,
                y: point.x * sin + point.y * cos
            )
        }
    }

    private func minDistance(from point: CGPoint, to points: [CGPoint]) -> Double {
        var best = Double.infinity
        for other in points {
            let dx = point.x - other.x
            let dy = point.y - other.y
            let distSq = dx * dx + dy * dy
            if distSq < best {
                best = distSq
            }
        }
        return sqrt(best)
    }

    private func chamferDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return Double.infinity }

        let distancesAB = a.map { minDistance(from: $0, to: b) }
        let distancesBA = b.map { minDistance(from: $0, to: a) }

        let sumAB = distancesAB.reduce(0, +)
        let sumBA = distancesBA.reduce(0, +)

        return 0.5 * ((sumAB / Double(a.count)) + (sumBA / Double(b.count)))
    }

    private func buildCorrespondence(userPoints: [CGPoint], constellationPoints: [CGPoint]) -> [Int] {
        var correspondence = [Int](repeating: -1, count: userPoints.count)
        var used = Set<Int>()

        for (userIdx, userPoint) in userPoints.enumerated() {
            var bestDist = Double.infinity
            var bestConstIdx = -1

            for (constIdx, constPoint) in constellationPoints.enumerated() {
                if used.contains(constIdx) { continue }

                let dx = userPoint.x - constPoint.x
                let dy = userPoint.y - constPoint.y
                let distSq = dx * dx + dy * dy

                if distSq < bestDist {
                    bestDist = distSq
                    bestConstIdx = constIdx
                }
            }

            if bestConstIdx != -1 {
                correspondence[userIdx] = bestConstIdx
                used.insert(bestConstIdx)
            }
        }

        return correspondence
    }

    private func edgeSimilarity(
        userEdges: [[Int]],
        constellationEdges: [[Int]],
        correspondence: [Int]
    ) -> Double {
        guard !userEdges.isEmpty, !constellationEdges.isEmpty else { return 0 }

        let constellationEdgeSet = Set(
            constellationEdges.compactMap { edge -> String? in
                guard edge.count == 2 else { return nil }
                let sorted = edge.sorted()
                return "\(sorted[0])-\(sorted[1])"
            }
        )

        var matchedEdges = 0
        var validUserEdges = 0

        for edge in userEdges {
            guard edge.count == 2 else { continue }
            let userIdx1 = edge[0]
            let userIdx2 = edge[1]

            guard userIdx1 < correspondence.count,
                  userIdx2 < correspondence.count else {
                continue
            }

            let constIdx1 = correspondence[userIdx1]
            let constIdx2 = correspondence[userIdx2]

            guard constIdx1 != -1, constIdx2 != -1 else { continue }

            validUserEdges += 1
            let sorted = [constIdx1, constIdx2].sorted()
            let key = "\(sorted[0])-\(sorted[1])"

            if constellationEdgeSet.contains(key) {
                matchedEdges += 1
            }
        }

        guard validUserEdges > 0 else { return 0 }
        return Double(matchedEdges) / Double(validUserEdges)
    }

    private func scanRotation(
        source: [CGPoint],
        target: [CGPoint],
        userEdges: [[Int]],
        constEdges: [[Int]]
    ) -> (error: Double, positionError: Double, edgeScore: Double, angle: Double) {
        var bestError = Double.infinity
        var bestPositionError = Double.infinity
        var bestEdgeScore = 0.0
        var bestAngle = 0.0

        let step = 5.0 * .pi / 180
        let totalSteps = Int((2 * .pi) / step)

        for i in 0..<totalSteps {
            let angle = Double(i) * step
            let rotated = rotatePoints(source, by: angle)
            let positionError = chamferDistance(rotated, target)

            let correspondence = buildCorrespondence(
                userPoints: rotated,
                constellationPoints: target
            )
            let edgeScore = edgeSimilarity(
                userEdges: userEdges,
                constellationEdges: constEdges,
                correspondence: correspondence
            )

            let combinedError = positionError * 0.7 + (1.0 - edgeScore) * 0.3

            if combinedError < bestError {
                bestError = combinedError
                bestPositionError = positionError
                bestEdgeScore = edgeScore
                bestAngle = angle * 180 / .pi
            }
        }

        return (
            error: bestError,
            positionError: bestPositionError,
            edgeScore: bestEdgeScore,
            angle: bestAngle
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
