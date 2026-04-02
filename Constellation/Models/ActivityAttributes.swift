import ActivityKit
import Foundation

// MARK: - Constellation Activity Attributes

struct ConstellationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lastUpdated: Date

        init(lastUpdated: Date = Date()) {
            self.lastUpdated = lastUpdated
        }
    }

    let constellationId: String
    let name: String
    let meaning: String
    let centerRa: Double
    let centerDec: Double
    let hemisphere: String
    let normalizedStars: [[Double]]
    let connections: [[Int]]
    let startTime: Date

    init(
        constellationId: String,
        name: String,
        meaning: String,
        centerRa: Double,
        centerDec: Double,
        hemisphere: String,
        normalizedStars: [[Double]],
        connections: [[Int]],
        startTime: Date = Date()
    ) {
        self.constellationId = constellationId
        self.name = name
        self.meaning = meaning
        self.centerRa = centerRa
        self.centerDec = centerDec
        self.hemisphere = hemisphere
        self.normalizedStars = normalizedStars
        self.connections = connections
        self.startTime = startTime
    }
}

// MARK: - Moon Activity Attributes

struct MoonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Double
        var illumination: Double
        var phaseName: String
        var riseHours: Double
        var setHours: Double
        var lastUpdated: Date

        init(
            phase: Double,
            illumination: Double,
            phaseName: String,
            riseHours: Double,
            setHours: Double,
            lastUpdated: Date = Date()
        ) {
            self.phase = phase
            self.illumination = illumination
            self.phaseName = phaseName
            self.riseHours = riseHours
            self.setHours = setHours
            self.lastUpdated = lastUpdated
        }
    }

    let selectedDate: Date
    let startTime: Date

    init(
        selectedDate: Date,
        startTime: Date = Date()
    ) {
        self.selectedDate = selectedDate
        self.startTime = startTime
    }
}
