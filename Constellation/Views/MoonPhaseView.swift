import Combine
import CoreLocation
import SwiftUI
import UIKit

// MARK: - Moon Calculator

struct MoonData {
    let age: Double
    let phase: Double
    let illumination: Double
    let phaseIndex: Int
    let phaseName: String
    let phaseDescription: String
    let nextPhase: (label: String, days: Double)
    let riseHours: Double
    let setHours: Double
}

extension MoonData: Equatable {
    static func == (lhs: MoonData, rhs: MoonData) -> Bool {
        lhs.age == rhs.age &&
        lhs.phase == rhs.phase &&
        lhs.illumination == rhs.illumination &&
        lhs.phaseIndex == rhs.phaseIndex &&
        lhs.phaseName == rhs.phaseName &&
        lhs.phaseDescription == rhs.phaseDescription &&
        lhs.nextPhase.label == rhs.nextPhase.label &&
        lhs.nextPhase.days == rhs.nextPhase.days &&
        lhs.riseHours == rhs.riseHours &&
        lhs.setHours == rhs.setHours
    }
}

struct MoonCalculator {
    static let synodicMonth: Double = 29.530588853
    private static let phaseEpochJulianDay: Double = 2451550.09765
    private static let astronomicalUnitKm: Double = 149_597_870.7

    static let phaseLabels: [(name: String, icon: String, desc: String)] = [
        ("New Moon", "moon.fill", "The moon is between Earth and the Sun."),
        ("Waxing Crescent", "moon.fill", "A thin crescent appears in the evening."),
        ("First Quarter", "moon.righthalf.fill", "The right half is illuminated."),
        ("Waxing Gibbous", "moon.fill", "More than half is illuminated."),
        ("Full Moon", "moon.fill", "The entire face is illuminated."),
        ("Waning Gibbous", "moon.fill", "Illumination gradually decreases."),
        ("Last Quarter", "moon.lefthalf.fill", "The left half is illuminated."),
        ("Waning Crescent", "moon.fill", "A faint crescent before dawn.")
    ]

    private enum MajorPhase: CaseIterable {
        case newMoon
        case firstQuarter
        case fullMoon
        case lastQuarter

        var kOffset: Double {
            switch self {
            case .newMoon: return 0.0
            case .firstQuarter: return 0.25
            case .fullMoon: return 0.5
            case .lastQuarter: return 0.75
            }
        }

        var label: String {
            switch self {
            case .newMoon: return "New Moon"
            case .firstQuarter: return "First Quarter"
            case .fullMoon: return "Full Moon"
            case .lastQuarter: return "Last Quarter"
            }
        }
    }

    private enum SearchDirection {
        case forward
        case backward
    }

    // MARK: - Public API

    /// Returns moon data for the given date. Pass latitude/longitude for accurate rise/set times.
    static func getMoonData(
        for date: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeZone: TimeZone = .current
    ) -> MoonData {
        let jd = julianDay(date: date)
        let phaseState = phaseAndIllumination(forJulianDay: jd)
        let phase = normalizeUnitInterval(phaseState.phase)
        let illumination = phaseState.illumination

        let previousNewMoonJD = phaseEventJulianDay(
            phase: .newMoon,
            relativeTo: jd,
            direction: .backward,
            includeCurrent: true
        )
        let age = max(0.0, jd - previousNewMoonJD)

        let phaseIndex = Int(floor(phase * 8.0 + 0.5)) % 8

        let upcoming = nextMajorPhase(afterJulianDay: jd)
        let nextPhase: (label: String, days: Double) = (
            label: upcoming.phase.label,
            days: max(0.0, upcoming.jd - jd)
        )

        var riseHours = -1.0
        var setHours = -1.0
        if let lat = latitude, let lon = longitude {
            let times = moonRiseSet(date: date, latitude: lat, longitude: lon, timeZone: timeZone)
            riseHours = times.rise ?? -1.0
            setHours = times.set ?? -1.0
        }

        return MoonData(
            age: age,
            phase: phase,
            illumination: illumination,
            phaseIndex: phaseIndex,
            phaseName: phaseLabels[phaseIndex].name,
            phaseDescription: phaseLabels[phaseIndex].desc,
            nextPhase: nextPhase,
            riseHours: riseHours,
            setHours: setHours
        )
    }

    /// Returns only normalized phase (0...1) for lightweight callers like calendar rendering.
    static func phase(for date: Date) -> Double {
        let jd = julianDay(date: date)
        let phaseState = phaseAndIllumination(forJulianDay: jd)
        return normalizeUnitInterval(phaseState.phase)
    }

    // MARK: - Validation

    enum ValidationError: Error, LocalizedError {
        case emptyCSV
        case missingHeader(String)
        case invalidRow(Int, String)

        var errorDescription: String? {
            switch self {
            case .emptyCSV:
                return "CSV is empty."
            case .missingHeader(let name):
                return "Missing required CSV header: \(name)"
            case .invalidRow(let row, let message):
                return "Invalid row \(row): \(message)"
            }
        }
    }

    /// Loads a CSV reference dataset and returns a text report with error metrics.
    static func validationReport(csvAt url: URL) throws -> String {
        let csv = try String(contentsOf: url, encoding: .utf8)
        return try validationReport(csv: csv)
    }

    /// CSV columns (case-insensitive):
    /// timestamp (required), timezone, latitude, longitude,
    /// phase, illumination, rise_hours, set_hours.
    /// timezone defaults to UTC when blank.
    /// phase/illumination accept 0...1 or 0...100.
    /// rise_hours/set_hours accept 0...24, blank (skip), or "none" / "n/a".
    static func validationReport(csv: String) throws -> String {
        let samples = try parseValidationSamples(csv: csv)
        guard !samples.isEmpty else { throw ValidationError.emptyCSV }

        var phaseErrors = NumericErrorAccumulator()
        var illuminationErrors = NumericErrorAccumulator()
        var riseTimingErrors = NumericErrorAccumulator()
        var setTimingErrors = NumericErrorAccumulator()
        var riseAvailability = AvailabilityAccumulator()
        var setAvailability = AvailabilityAccumulator()

        for sample in samples {
            let data = getMoonData(
                for: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                timeZone: sample.timeZone
            )

            if let expectedPhase = sample.expectedPhase {
                let error = circularUnitDifference(a: data.phase, b: expectedPhase)
                phaseErrors.add(error)
            }

            if let expectedIllumination = sample.expectedIllumination {
                let errorPercentPoints = (data.illumination - expectedIllumination) * 100.0
                illuminationErrors.add(errorPercentPoints)
            }

            compareEvent(
                expected: sample.expectedRise,
                predictedHour: data.riseHours >= 0.0 ? data.riseHours : nil,
                availability: &riseAvailability,
                timing: &riseTimingErrors
            )
            compareEvent(
                expected: sample.expectedSet,
                predictedHour: data.setHours >= 0.0 ? data.setHours : nil,
                availability: &setAvailability,
                timing: &setTimingErrors
            )
        }

        var lines: [String] = []
        lines.append("Moon Validation Report")
        lines.append("Samples: \(samples.count)")

        if phaseErrors.count > 0 {
            lines.append(
                String(
                    format: "Phase error: n=%d, MAE=%.5f, RMSE=%.5f, p95=%.5f, max=%.5f",
                    phaseErrors.count,
                    phaseErrors.meanAbsolute,
                    phaseErrors.rmse,
                    phaseErrors.p95Absolute,
                    phaseErrors.maxAbsolute
                )
            )
            lines.append(
                String(
                    format: "Phase MAE in days: %.3f",
                    phaseErrors.meanAbsolute * synodicMonth
                )
            )
        } else {
            lines.append("Phase error: n=0")
        }

        if illuminationErrors.count > 0 {
            lines.append(
                String(
                    format: "Illumination error (percentage points): n=%d, MAE=%.3f, RMSE=%.3f, p95=%.3f, max=%.3f",
                    illuminationErrors.count,
                    illuminationErrors.meanAbsolute,
                    illuminationErrors.rmse,
                    illuminationErrors.p95Absolute,
                    illuminationErrors.maxAbsolute
                )
            )
        } else {
            lines.append("Illumination error: n=0")
        }

        lines.append(
            String(
                format: "Rise availability: n=%d, accuracy=%.2f%%, false_event=%d, missed_event=%d",
                riseAvailability.compared,
                riseAvailability.accuracyPercent,
                riseAvailability.falseEventCount,
                riseAvailability.missedEventCount
            )
        )
        if riseTimingErrors.count > 0 {
            lines.append(
                String(
                    format: "Rise timing error (minutes): n=%d, MAE=%.2f, RMSE=%.2f, p95=%.2f, max=%.2f",
                    riseTimingErrors.count,
                    riseTimingErrors.meanAbsolute,
                    riseTimingErrors.rmse,
                    riseTimingErrors.p95Absolute,
                    riseTimingErrors.maxAbsolute
                )
            )
        } else {
            lines.append("Rise timing error: n=0")
        }

        lines.append(
            String(
                format: "Set availability: n=%d, accuracy=%.2f%%, false_event=%d, missed_event=%d",
                setAvailability.compared,
                setAvailability.accuracyPercent,
                setAvailability.falseEventCount,
                setAvailability.missedEventCount
            )
        )
        if setTimingErrors.count > 0 {
            lines.append(
                String(
                    format: "Set timing error (minutes): n=%d, MAE=%.2f, RMSE=%.2f, p95=%.2f, max=%.2f",
                    setTimingErrors.count,
                    setTimingErrors.meanAbsolute,
                    setTimingErrors.rmse,
                    setTimingErrors.p95Absolute,
                    setTimingErrors.maxAbsolute
                )
            )
        } else {
            lines.append("Set timing error: n=0")
        }

        return lines.joined(separator: "\n")
    }

    private enum EventExpectation: Equatable {
        case unspecified
        case none
        case hour(Double)
    }

    private struct ValidationSample {
        let timestamp: Date
        let timeZone: TimeZone
        let latitude: Double?
        let longitude: Double?
        let expectedPhase: Double?
        let expectedIllumination: Double?
        let expectedRise: EventExpectation
        let expectedSet: EventExpectation
    }

    private struct TimestampParsers {
        let timestampFormatter: DateFormatter
        let dateOnlyFormatter: DateFormatter
    }

    private struct NumericErrorAccumulator {
        private(set) var count = 0
        private(set) var maxAbsolute = 0.0
        private var sumAbsolute = 0.0
        private var sumSquares = 0.0
        private var absoluteValues: [Double] = []

        mutating func add(_ error: Double) {
            let absolute = abs(error)
            count += 1
            sumAbsolute += absolute
            sumSquares += error * error
            maxAbsolute = max(maxAbsolute, absolute)
            absoluteValues.append(absolute)
        }

        var meanAbsolute: Double {
            guard count > 0 else { return 0.0 }
            return sumAbsolute / Double(count)
        }

        var rmse: Double {
            guard count > 0 else { return 0.0 }
            return sqrt(sumSquares / Double(count))
        }

        var p95Absolute: Double {
            guard !absoluteValues.isEmpty else { return 0.0 }
            let sorted = absoluteValues.sorted()
            let index = Int(floor(Double(sorted.count - 1) * 0.95))
            return sorted[index]
        }
    }

    private struct AvailabilityAccumulator {
        private(set) var compared = 0
        private(set) var matched = 0
        private(set) var falseEventCount = 0
        private(set) var missedEventCount = 0

        mutating func add(expectedEvent: Bool, predictedEvent: Bool) {
            compared += 1
            if expectedEvent == predictedEvent {
                matched += 1
                return
            }
            if expectedEvent {
                missedEventCount += 1
            } else {
                falseEventCount += 1
            }
        }

        var accuracyPercent: Double {
            guard compared > 0 else { return 0.0 }
            return Double(matched) * 100.0 / Double(compared)
        }
    }

    private static func parseValidationSamples(csv: String) throws -> [ValidationSample] {
        let lines = parseCSVRows(csv)

        guard !lines.isEmpty else { throw ValidationError.emptyCSV }

        let headers = parseCSVLine(lines[0]).map(normalizeHeader)

        func headerIndex(_ names: [String]) -> Int? {
            for name in names {
                if let index = headers.firstIndex(of: normalizeHeader(name)) {
                    return index
                }
            }
            return nil
        }

        guard let timestampIndex = headerIndex(["timestamp", "datetime", "date", "time"]) else {
            throw ValidationError.missingHeader("timestamp")
        }

        let timezoneIndex = headerIndex(["timezone", "tz"])
        let latitudeIndex = headerIndex(["latitude", "lat"])
        let longitudeIndex = headerIndex(["longitude", "lon", "lng"])
        let phaseIndex = headerIndex(["phase", "phase_fraction"])
        let illuminationIndex = headerIndex(["illumination", "illum", "illumination_fraction"])
        let riseIndex = headerIndex(["rise_hours", "rise"])
        let setIndex = headerIndex(["set_hours", "set"])

        var samples: [ValidationSample] = []
        samples.reserveCapacity(max(0, lines.count - 1))
        var timestampParserCache: [String: TimestampParsers] = [:]

        for (offset, line) in lines.dropFirst().enumerated() {
            let rowNumber = offset + 2
            let fields = parseCSVLine(line)

            func cell(_ index: Int?) -> String {
                guard let index, index >= 0, index < fields.count else { return "" }
                return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let timezoneRaw = cell(timezoneIndex)
            let sampleTimeZone: TimeZone
            if timezoneRaw.isEmpty {
                sampleTimeZone = TimeZone(secondsFromGMT: 0) ?? .current
            } else if let tz = TimeZone(identifier: timezoneRaw) {
                sampleTimeZone = tz
            } else {
                throw ValidationError.invalidRow(rowNumber, "invalid timezone '\(timezoneRaw)'")
            }

            let timestampRaw = cell(timestampIndex)
            guard let timestamp = parseTimestamp(timestampRaw, timeZone: sampleTimeZone, parserCache: &timestampParserCache) else {
                throw ValidationError.invalidRow(rowNumber, "invalid timestamp '\(timestampRaw)'")
            }

            let latitude = try parseOptionalDouble(cell(latitudeIndex), row: rowNumber, field: "latitude")
            let longitude = try parseOptionalDouble(cell(longitudeIndex), row: rowNumber, field: "longitude")
            if (latitude == nil) != (longitude == nil) {
                throw ValidationError.invalidRow(rowNumber, "latitude/longitude must both be present or blank")
            }
            if let latitude, let longitude {
                guard (-90.0...90.0).contains(latitude) else {
                    throw ValidationError.invalidRow(rowNumber, "latitude must be in -90...90")
                }
                guard (-180.0...180.0).contains(longitude) else {
                    throw ValidationError.invalidRow(rowNumber, "longitude must be in -180...180")
                }
            }

            let expectedPhase = try parseOptionalFraction(cell(phaseIndex), row: rowNumber, field: "phase")
            let expectedIllumination = try parseOptionalFraction(cell(illuminationIndex), row: rowNumber, field: "illumination")
            let expectedRise = try parseEventExpectation(cell(riseIndex), row: rowNumber, field: "rise_hours")
            let expectedSet = try parseEventExpectation(cell(setIndex), row: rowNumber, field: "set_hours")

            let needsLocation = expectedRise != .unspecified || expectedSet != .unspecified
            if needsLocation && (latitude == nil || longitude == nil) {
                throw ValidationError.invalidRow(rowNumber, "rise/set comparison requires latitude and longitude")
            }

            samples.append(
                ValidationSample(
                    timestamp: timestamp,
                    timeZone: sampleTimeZone,
                    latitude: latitude,
                    longitude: longitude,
                    expectedPhase: expectedPhase,
                    expectedIllumination: expectedIllumination,
                    expectedRise: expectedRise,
                    expectedSet: expectedSet
                )
            )
        }

        return samples
    }

    private static func parseCSVRows(_ csv: String) -> [String] {
        var rows: [String] = []
        var current = ""
        var inQuotes = false
        var index = csv.startIndex

        func commitCurrentRow() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                rows.append(trimmed)
            }
            current.removeAll(keepingCapacity: true)
        }

        while index < csv.endIndex {
            let char = csv[index]

            if char == "\"" {
                if inQuotes {
                    let next = csv.index(after: index)
                    if next < csv.endIndex, csv[next] == "\"" {
                        // Preserve escaped quote and keep quote state unchanged.
                        current.append(char)
                        current.append(csv[next])
                        index = csv.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    inQuotes = true
                }
                current.append(char)
                index = csv.index(after: index)
                continue
            }

            if !inQuotes && (char == "\n" || char == "\r") {
                commitCurrentRow()
                if char == "\r" {
                    let next = csv.index(after: index)
                    if next < csv.endIndex, csv[next] == "\n" {
                        index = csv.index(after: next)
                        continue
                    }
                }
                index = csv.index(after: index)
                continue
            }

            current.append(char)
            index = csv.index(after: index)
        }

        commitCurrentRow()
        return rows
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]

            if char == "\"" {
                if inQuotes {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        index = line.index(after: index)
                        continue
                    }
                } else {
                    inQuotes = true
                    index = line.index(after: index)
                    continue
                }
            }

            if char == ",", !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
                index = line.index(after: index)
                continue
            }

            current.append(char)
            index = line.index(after: index)
        }

        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func parseOptionalDouble(_ raw: String, row: Int, field: String) throws -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed) else {
            throw ValidationError.invalidRow(row, "invalid \(field) '\(raw)'")
        }
        return value
    }

    private static func parseOptionalFraction(_ raw: String, row: Int, field: String) throws -> Double? {
        guard let value = try parseOptionalDouble(raw, row: row, field: field) else { return nil }
        if value >= 0.0, value <= 1.0 {
            return value
        }
        if value >= 0.0, value <= 100.0 {
            return value / 100.0
        }
        throw ValidationError.invalidRow(row, "\(field) must be in 0...1 or 0...100")
    }

    private static func parseEventExpectation(_ raw: String, row: Int, field: String) throws -> EventExpectation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unspecified }

        let lower = trimmed.lowercased()
        if lower == "none" || lower == "n/a" || lower == "na" || lower == "-" {
            return .none
        }

        guard let hour = Double(trimmed) else {
            throw ValidationError.invalidRow(row, "invalid \(field) '\(raw)'")
        }
        guard hour >= 0.0, hour <= 24.0 else {
            throw ValidationError.invalidRow(row, "\(field) must be in 0...24, blank, or none")
        }

        let normalizedHour = (hour == 24.0) ? 0.0 : hour
        return .hour(normalizedHour)
    }

    private static func makeTimestampParsers(timeZone: TimeZone) -> TimestampParsers {
        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.timeZone = timeZone
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = timeZone
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"

        return TimestampParsers(
            timestampFormatter: timestampFormatter,
            dateOnlyFormatter: dateOnlyFormatter
        )
    }

    private static func parseTimestamp(
        _ raw: String,
        timeZone: TimeZone,
        parserCache: inout [String: TimestampParsers]
    ) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = iso8601WithFractional.date(from: trimmed) {
            return date
        }
        if let date = iso8601Basic.date(from: trimmed) {
            return date
        }

        let cacheKey = timeZone.identifier
        let parsers: TimestampParsers
        if let cached = parserCache[cacheKey] {
            parsers = cached
        } else {
            let created = makeTimestampParsers(timeZone: timeZone)
            parserCache[cacheKey] = created
            parsers = created
        }

        if let date = parsers.timestampFormatter.date(from: trimmed) {
            return date
        }

        if let date = parsers.dateOnlyFormatter.date(from: trimmed) {
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = timeZone
            let day = localCalendar.dateComponents([.year, .month, .day], from: date)
            var noonComponents = DateComponents()
            noonComponents.year = day.year
            noonComponents.month = day.month
            noonComponents.day = day.day
            noonComponents.hour = 12
            noonComponents.minute = 0
            noonComponents.second = 0
            if let localNoon = localCalendar.date(from: noonComponents) {
                return localNoon
            }
            return localCalendar.date(byAdding: .hour, value: 12, to: date)
        }

        return nil
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func compareEvent(
        expected: EventExpectation,
        predictedHour: Double?,
        availability: inout AvailabilityAccumulator,
        timing: inout NumericErrorAccumulator
    ) {
        switch expected {
        case .unspecified:
            return

        case .none:
            availability.add(expectedEvent: false, predictedEvent: predictedHour != nil)

        case .hour(let expectedHour):
            guard let predictedHour else {
                availability.add(expectedEvent: true, predictedEvent: false)
                return
            }
            availability.add(expectedEvent: true, predictedEvent: true)
            let minuteError = circularHourDifference(a: predictedHour, b: expectedHour) * 60.0
            timing.add(minuteError)
        }
    }

    private static func circularUnitDifference(a: Double, b: Double) -> Double {
        let diff = abs((a - b).truncatingRemainder(dividingBy: 1.0))
        return min(diff, 1.0 - diff)
    }

    private static func circularHourDifference(a: Double, b: Double) -> Double {
        let diff = abs((a - b).truncatingRemainder(dividingBy: 24.0))
        return min(diff, 24.0 - diff)
    }

    private static func phaseAndIllumination(forJulianDay jd: Double) -> (phase: Double, illumination: Double) {
        let moon = moonEclipticCoordinates(jd: jd)
        let sun = sunEclipticCoordinates(jd: jd)

        let elongation = normalizeAngle(moon.longitude - sun.apparentLongitude)
        let phase = elongation / 360.0

        let elongationRad = acos(clamp(
            cos(deg2rad(moon.latitude)) * cos(deg2rad(elongation)),
            min: -1.0,
            max: 1.0
        ))
        let moonDistanceAu = moon.distanceKm / astronomicalUnitKm
        let phaseAngle = atan2(
            sun.distanceAu * sin(elongationRad),
            moonDistanceAu - sun.distanceAu * cos(elongationRad)
        )
        let illumination = clamp((1.0 + cos(phaseAngle)) * 0.5, min: 0.0, max: 1.0)
        return (phase: phase, illumination: illumination)
    }

    private static func nextMajorPhase(afterJulianDay jd: Double) -> (phase: MajorPhase, jd: Double) {
        var nearest: (phase: MajorPhase, jd: Double)?
        for phase in MajorPhase.allCases {
            let eventJD = phaseEventJulianDay(phase: phase, relativeTo: jd, direction: .forward)
            if let current = nearest {
                if eventJD < current.jd {
                    nearest = (phase: phase, jd: eventJD)
                }
            } else {
                nearest = (phase: phase, jd: eventJD)
            }
        }
        return nearest ?? (phase: .newMoon, jd: jd + synodicMonth)
    }

    private static func phaseEventJulianDay(
        phase: MajorPhase,
        relativeTo jd: Double,
        direction: SearchDirection,
        includeCurrent: Bool = false
    ) -> Double {
        let kApprox = (jd - phaseEpochJulianDay) / synodicMonth
        let offset = phase.kOffset
        let epsilon = 1e-7

        switch direction {
        case .forward:
            var cycle = floor(kApprox - offset)
            var event = truePhaseJulianDay(k: cycle + offset, phase: phase)
            while includeCurrent ? (event < jd - epsilon) : (event <= jd + epsilon) {
                cycle += 1.0
                event = truePhaseJulianDay(k: cycle + offset, phase: phase)
            }
            return event

        case .backward:
            var cycle = ceil(kApprox - offset)
            var event = truePhaseJulianDay(k: cycle + offset, phase: phase)
            while includeCurrent ? (event > jd + epsilon) : (event >= jd - epsilon) {
                cycle -= 1.0
                event = truePhaseJulianDay(k: cycle + offset, phase: phase)
            }
            return event
        }
    }

    /// Meeus chapter 49 true phase approximation (converted from TT to UTC).
    private static func truePhaseJulianDay(k: Double, phase: MajorPhase) -> Double {
        let T = k / 1236.85
        let T2 = T * T
        let T3 = T2 * T
        let T4 = T3 * T

        var jde = phaseEpochJulianDay
            + 29.530588853 * k
            + 0.0001337 * T2
            - 0.000000150 * T3
            + 0.00000000073 * T4

        let E = 1.0 - 0.002516 * T - 0.0000074 * T2
        let E2 = E * E

        let M = deg2rad(normalizeAngle(2.5534 + 29.10535670 * k - 0.0000014 * T2 - 0.00000011 * T3))
        let Mprime = deg2rad(normalizeAngle(201.5643 + 385.81693528 * k + 0.0107582 * T2 + 0.00001238 * T3 - 0.000000058 * T4))
        let F = deg2rad(normalizeAngle(160.7108 + 390.67050284 * k - 0.0016118 * T2 - 0.00000227 * T3 + 0.000000011 * T4))
        let omega = deg2rad(normalizeAngle(124.7746 - 1.56375580 * k + 0.0020691 * T2 + 0.00000215 * T3))

        let phaseCorrection: Double
        switch phase {
        case .newMoon:
            phaseCorrection =
                -0.40720 * sin(Mprime)
                + 0.17241 * E * sin(M)
                + 0.01608 * sin(2 * Mprime)
                + 0.01039 * sin(2 * F)
                + 0.00739 * E * sin(Mprime - M)
                - 0.00514 * E * sin(Mprime + M)
                + 0.00208 * E2 * sin(2 * M)
                - 0.00111 * sin(Mprime - 2 * F)
                - 0.00057 * sin(Mprime + 2 * F)
                + 0.00056 * E * sin(2 * Mprime + M)
                - 0.00042 * sin(3 * Mprime)
                + 0.00042 * E * sin(M + 2 * F)
                + 0.00038 * E * sin(M - 2 * F)
                - 0.00024 * E * sin(2 * Mprime - M)
                - 0.00017 * sin(omega)
                - 0.00007 * sin(Mprime + 2 * M)
                + 0.00004 * sin(2 * Mprime - 2 * F)
                + 0.00004 * sin(3 * M)
                + 0.00003 * sin(Mprime + M - 2 * F)
                + 0.00003 * sin(2 * Mprime + 2 * F)
                - 0.00003 * sin(Mprime + M + 2 * F)
                + 0.00003 * sin(Mprime - M + 2 * F)
                - 0.00002 * sin(Mprime - M - 2 * F)
                - 0.00002 * sin(3 * Mprime + M)
                + 0.00002 * sin(4 * Mprime)

        case .fullMoon:
            phaseCorrection =
                -0.40614 * sin(Mprime)
                + 0.17302 * E * sin(M)
                + 0.01614 * sin(2 * Mprime)
                + 0.01043 * sin(2 * F)
                + 0.00734 * E * sin(Mprime - M)
                - 0.00515 * E * sin(Mprime + M)
                + 0.00209 * E2 * sin(2 * M)
                - 0.00111 * sin(Mprime - 2 * F)
                - 0.00057 * sin(Mprime + 2 * F)
                + 0.00056 * E * sin(2 * Mprime + M)
                - 0.00042 * sin(3 * Mprime)
                + 0.00042 * E * sin(M + 2 * F)
                + 0.00038 * E * sin(M - 2 * F)
                - 0.00024 * E * sin(2 * Mprime - M)
                - 0.00017 * sin(omega)
                - 0.00007 * sin(Mprime + 2 * M)
                + 0.00004 * sin(2 * Mprime - 2 * F)
                + 0.00004 * sin(3 * M)
                + 0.00003 * sin(Mprime + M - 2 * F)
                + 0.00003 * sin(2 * Mprime + 2 * F)
                - 0.00003 * sin(Mprime + M + 2 * F)
                + 0.00003 * sin(Mprime - M + 2 * F)
                - 0.00002 * sin(Mprime - M - 2 * F)
                - 0.00002 * sin(3 * Mprime + M)
                + 0.00002 * sin(4 * Mprime)

        case .firstQuarter, .lastQuarter:
            var correction =
                -0.62801 * sin(Mprime)
                + 0.17172 * E * sin(M)
                - 0.01183 * E * sin(Mprime + M)
                + 0.00862 * sin(2 * Mprime)
                + 0.00804 * sin(2 * F)
                + 0.00454 * E * sin(Mprime - M)
                + 0.00204 * E2 * sin(2 * M)
                - 0.00180 * sin(Mprime - 2 * F)
                - 0.00070 * sin(Mprime + 2 * F)
                - 0.00040 * sin(3 * Mprime)
                - 0.00034 * E * sin(2 * Mprime - M)
                + 0.00032 * E * sin(M + 2 * F)
                + 0.00032 * E * sin(M - 2 * F)
                - 0.00028 * E2 * sin(Mprime + 2 * M)
                + 0.00027 * E * sin(2 * Mprime + M)
                - 0.00017 * sin(omega)
                - 0.00005 * sin(Mprime - M - 2 * F)
                + 0.00004 * sin(2 * Mprime + 2 * F)
                - 0.00004 * sin(Mprime + M + 2 * F)
                + 0.00004 * sin(Mprime - 2 * M)
                + 0.00003 * sin(Mprime + M - 2 * F)
                + 0.00003 * sin(3 * M)
                + 0.00002 * sin(2 * Mprime - 2 * F)
                + 0.00002 * sin(Mprime - M + 2 * F)
                - 0.00002 * sin(3 * Mprime + M)

            let W =
                0.00306
                - 0.00038 * E * cos(M)
                + 0.00026 * cos(Mprime)
                - 0.00002 * cos(Mprime - M)
                + 0.00002 * cos(Mprime + M)
                + 0.00002 * cos(2 * F)

            correction += (phase == .firstQuarter) ? W : -W
            phaseCorrection = correction
        }

        let A1 = deg2rad(normalizeAngle(299.77 + 0.107408 * k - 0.009173 * T2))
        let A2 = deg2rad(normalizeAngle(251.88 + 0.016321 * k))
        let A3 = deg2rad(normalizeAngle(251.83 + 26.651886 * k))
        let A4 = deg2rad(normalizeAngle(349.42 + 36.412478 * k))
        let A5 = deg2rad(normalizeAngle(84.66 + 18.206239 * k))
        let A6 = deg2rad(normalizeAngle(141.74 + 53.303771 * k))
        let A7 = deg2rad(normalizeAngle(207.14 + 2.453732 * k))
        let A8 = deg2rad(normalizeAngle(154.84 + 7.306860 * k))
        let A9 = deg2rad(normalizeAngle(34.52 + 27.261239 * k))
        let A10 = deg2rad(normalizeAngle(207.19 + 0.121824 * k))
        let A11 = deg2rad(normalizeAngle(291.34 + 1.844379 * k))
        let A12 = deg2rad(normalizeAngle(161.72 + 24.198154 * k))
        let A13 = deg2rad(normalizeAngle(239.56 + 25.513099 * k))
        let A14 = deg2rad(normalizeAngle(331.55 + 3.592518 * k))

        let planetaryCorrection =
            0.000325 * sin(A1)
            + 0.000165 * sin(A2)
            + 0.000164 * sin(A3)
            + 0.000126 * sin(A4)
            + 0.000110 * sin(A5)
            + 0.000062 * sin(A6)
            + 0.000060 * sin(A7)
            + 0.000056 * sin(A8)
            + 0.000047 * sin(A9)
            + 0.000042 * sin(A10)
            + 0.000040 * sin(A11)
            + 0.000037 * sin(A12)
            + 0.000035 * sin(A13)
            + 0.000023 * sin(A14)

        jde += phaseCorrection + planetaryCorrection

        // Meeus outputs TT; convert to UTC with a modern Delta-T approximation.
        let deltaT = deltaTSeconds(forDecimalYear: decimalYear(fromJulianDay: jde))
        return jde - deltaT / 86400.0
    }

    // MARK: - Astronomical Rise/Set

    private enum HorizonEvent {
        case rise
        case set
    }

    /// Computes moon rise and set times as local hours (0–24).
    /// Returns nil for each event that does not occur on that local day.
    private static func moonRiseSet(
        date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> (rise: Double?, set: Double?) {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let dayStart = localCalendar.startOfDay(for: date)
        guard let dayEnd = localCalendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return (rise: nil, set: nil)
        }

        let step: TimeInterval = 30 * 60
        let searchStart = dayStart.addingTimeInterval(-step)
        let searchEnd = dayEnd.addingTimeInterval(step)

        var riseCandidates: [Date] = []
        var setCandidates: [Date] = []

        var t0 = searchStart
        var f0 = moonAltitudeDifference(date: t0, latitude: latitude, longitude: longitude)

        while t0 < searchEnd {
            let t1 = min(t0.addingTimeInterval(step), searchEnd)
            let f1 = moonAltitudeDifference(date: t1, latitude: latitude, longitude: longitude)

            if let bracket = crossingBracket(
                start: t0,
                end: t1,
                startValue: f0,
                endValue: f1,
                latitude: latitude,
                longitude: longitude
            ),
               let crossing = refineMoonCrossing(start: bracket.start, end: bracket.end, latitude: latitude, longitude: longitude),
               crossing >= dayStart, crossing < dayEnd,
               let event = classifyMoonCrossing(at: crossing, latitude: latitude, longitude: longitude) {
                switch event {
                case .rise:
                    riseCandidates.append(crossing)
                case .set:
                    setCandidates.append(crossing)
                }
            }

            t0 = t1
            f0 = f1
        }

        func localHours(from instant: Date) -> Double {
            let components = localCalendar.dateComponents([.hour, .minute, .second, .nanosecond], from: instant)
            return Double(components.hour ?? 0)
                + Double(components.minute ?? 0) / 60.0
                + Double(components.second ?? 0) / 3600.0
                + Double(components.nanosecond ?? 0) / 3_600_000_000_000.0
        }

        return (
            rise: riseCandidates.min().map(localHours),
            set: setCandidates.min().map(localHours)
        )
    }

    private static func crossingBracket(
        start: Date,
        end: Date,
        startValue: Double,
        endValue: Double,
        latitude: Double,
        longitude: Double
    ) -> (start: Date, end: Date)? {
        guard startValue.isFinite, endValue.isFinite else { return nil }
        if startValue == 0.0 || endValue == 0.0 || startValue * endValue < 0.0 {
            return (start: start, end: end)
        }

        // If both endpoints are far from the horizon, skip expensive sub-sampling.
        if min(abs(startValue), abs(endValue)) > 1.0 {
            return nil
        }

        var previousTime = start
        var previousValue = startValue
        let subdivisions = 6
        let duration = end.timeIntervalSince1970 - start.timeIntervalSince1970

        for index in 1...subdivisions {
            let fraction = Double(index) / Double(subdivisions)
            let time = Date(timeIntervalSince1970: start.timeIntervalSince1970 + duration * fraction)
            let value = moonAltitudeDifference(date: time, latitude: latitude, longitude: longitude)
            guard value.isFinite else { return nil }

            if previousValue == 0.0 || value == 0.0 || previousValue * value < 0.0 {
                return (start: previousTime, end: time)
            }

            previousTime = time
            previousValue = value
        }

        return nil
    }

    /// Geocentric altitude minus standard moon rise/set altitude (degrees).
    /// Root crossing from negative to positive is moonrise; positive to negative is moonset.
    private static func moonAltitudeDifference(
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> Double {
        let jd = julianDay(date: date)
        let (ra, dec, hp) = moonEquatorialCoords(jd: jd)

        let T = (jd - 2451545.0) / 36525.0
        var theta = 280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * T * T
            - T * T * T / 38710000.0
        theta = normalizeAngle(theta)

        var H = normalizeAngle(theta + longitude - ra * 15.0)
        if H > 180.0 { H -= 360.0 }

        let phi = deg2rad(latitude)
        let decRad = deg2rad(dec)
        let hourAngleRad = deg2rad(H)

        let altitude = rad2deg(asin(
            sin(phi) * sin(decRad) + cos(phi) * cos(decRad) * cos(hourAngleRad)
        ))

        let h0 = 0.7275 * hp - 34.0 / 60.0
        return altitude - h0
    }

    private static func refineMoonCrossing(
        start: Date,
        end: Date,
        latitude: Double,
        longitude: Double
    ) -> Date? {
        var a = start
        var b = end
        var fa = moonAltitudeDifference(date: a, latitude: latitude, longitude: longitude)
        let fb = moonAltitudeDifference(date: b, latitude: latitude, longitude: longitude)

        guard fa.isFinite, fb.isFinite else { return nil }

        let epsilon = 1e-7
        if abs(fa) < epsilon { return a }
        if abs(fb) < epsilon { return b }
        guard fa * fb < 0 else { return nil }

        for _ in 0..<32 {
            let midpoint = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) * 0.5)
            let fm = moonAltitudeDifference(date: midpoint, latitude: latitude, longitude: longitude)
            guard fm.isFinite else { return nil }

            if abs(fm) < 1e-5 || b.timeIntervalSince(a) <= 1.0 {
                return midpoint
            }

            if fa * fm <= 0 {
                b = midpoint
            } else {
                a = midpoint
                fa = fm
            }
        }

        return Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) * 0.5)
    }

    private static func classifyMoonCrossing(
        at date: Date,
        latitude: Double,
        longitude: Double
    ) -> HorizonEvent? {
        let sampleOffset: TimeInterval = 300
        let before = moonAltitudeDifference(
            date: date.addingTimeInterval(-sampleOffset),
            latitude: latitude,
            longitude: longitude
        )
        let after = moonAltitudeDifference(
            date: date.addingTimeInterval(sampleOffset),
            latitude: latitude,
            longitude: longitude
        )

        guard before.isFinite, after.isFinite else { return nil }

        if before <= 0.0, after > 0.0 { return .rise }
        if before >= 0.0, after < 0.0 { return .set }
        if after > before { return .rise }
        if after < before { return .set }
        return nil
    }

    // MARK: - Moon Position (Meeus ch. 47 truncated series)

    private static func moonEclipticCoordinates(jd: Double) -> (longitude: Double, latitude: Double, distanceKm: Double) {
        let T = (jd - 2451545.0) / 36525.0
        let T2 = T * T
        let E = 1.0 - 0.002516 * T - 0.0000074 * T2

        // Fundamental arguments (degrees)
        let L0 = normalizeAngle(218.3164477 + 481267.88123421 * T)   // Moon mean longitude
        let M  = normalizeAngle(134.9633964 + 477198.8676313  * T)   // Moon mean anomaly
        let Ms = normalizeAngle(357.5291092 +  35999.0502909  * T)   // Sun mean anomaly
        let F  = normalizeAngle( 93.2720950 + 483202.0175233  * T)   // Moon argument of latitude
        let D  = normalizeAngle(297.8501921 + 445267.1114034  * T)   // Moon mean elongation

        // Radians
        let Mr  = deg2rad(M)
        let Msr = deg2rad(Ms)
        let Fr  = deg2rad(F)
        let Dr  = deg2rad(D)

        // Longitude perturbations (0.000001°, dominant terms)
        var Σl: Double = 0.0
        Σl +=  6288774 * sin(Mr)
        Σl +=  1274027 * sin(2 * Dr - Mr)
        Σl +=   658314 * sin(2 * Dr)
        Σl +=   213618 * sin(2 * Mr)
        Σl -=   185116 * E * sin(Msr)
        Σl -=   114332 * sin(2 * Fr)
        Σl +=    58793 * sin(2 * Dr - 2 * Mr)
        Σl +=    57066 * E * sin(2 * Dr - Msr - Mr)
        Σl +=    53322 * sin(2 * Dr + Mr)
        Σl +=    45758 * E * sin(2 * Dr - Msr)
        Σl -=    40923 * E * sin(Msr - Mr)
        Σl -=    34720 * sin(Dr)
        Σl -=    30383 * E * sin(Msr + Mr)
        Σl +=    15327 * sin(2 * Dr - 2 * Fr)
        Σl -=    12528 * sin(Mr + 2 * Fr)
        Σl +=    10980 * sin(Mr - 2 * Fr)
        Σl +=    10675 * sin(4 * Dr - Mr)
        Σl +=    10034 * sin(3 * Mr)
        Σl +=     8548 * sin(4 * Dr - 2 * Mr)
        Σl -=     7888 * E * sin(2 * Dr + Msr - Mr)
        Σl -=     6766 * E * sin(2 * Dr + Msr)
        Σl -=     5163 * sin(Dr - Mr)
        Σl +=     4987 * E * sin(Dr + Msr)
        Σl +=     4036 * E * sin(2 * Dr - Msr + Mr)
        Σl +=     3994 * sin(2 * Dr + 2 * Mr)
        Σl +=     3861 * sin(4 * Dr)
        Σl +=     3665 * sin(2 * Dr - 3 * Mr)

        // Latitude perturbations (0.000001°, dominant terms)
        var Σb: Double = 0.0
        Σb +=  5128122 * sin(Fr)
        Σb +=   280602 * sin(Mr + Fr)
        Σb +=   277693 * sin(Mr - Fr)
        Σb +=   173237 * sin(2 * Dr - Fr)
        Σb +=    55413 * sin(2 * Dr + Fr - Mr)
        Σb +=    46271 * sin(2 * Dr - Fr - Mr)
        Σb +=    32573 * sin(2 * Dr + Fr)
        Σb +=    17198 * sin(2 * Mr + Fr)
        Σb +=     9266 * sin(2 * Dr + Mr - Fr)
        Σb +=     8822 * sin(2 * Mr - Fr)
        Σb +=     8216 * E * sin(2 * Dr - Msr - Fr)
        Σb +=     4324 * sin(2 * Dr - 2 * Mr - Fr)
        Σb +=     4200 * sin(2 * Dr + Fr + Mr)
        Σb -=     3359 * E * sin(2 * Dr + Msr - Fr)
        Σb +=     2463 * E * sin(2 * Dr - Msr - Fr - Mr)
        Σb +=     2211 * E * sin(2 * Dr - Msr - Fr)
        Σb +=     2065 * sin(2 * Dr - Fr + Mr)

        // Distance perturbations (0.001 km, dominant terms)
        var Σr: Double = 0.0
        Σr -= 20905355 * cos(Mr)
        Σr -=  3699111 * cos(2 * Dr - Mr)
        Σr -=  2955968 * cos(2 * Dr)
        Σr -=   569925 * cos(2 * Mr)
        Σr +=    48888 * E * cos(Msr)
        Σr -=     3149 * cos(2 * Fr)
        Σr +=   246158 * cos(2 * Dr - 2 * Mr)
        Σr -=   152138 * E * cos(2 * Dr - Msr - Mr)
        Σr -=   170733 * cos(2 * Dr + Mr)
        Σr -=   204586 * E * cos(2 * Dr - Msr)
        Σr -=   129620 * E * cos(Msr - Mr)
        Σr +=   108743 * cos(Dr)
        Σr +=   104755 * E * cos(Msr + Mr)
        Σr +=    10321 * cos(2 * Dr - 2 * Fr)
        Σr +=    79661 * cos(Mr - 2 * Fr)

        let longitude = normalizeAngle(L0 + Σl / 1_000_000.0)
        let latitude = Σb / 1_000_000.0
        let distance = 385000.56 + Σr / 1000.0

        return (longitude: longitude, latitude: latitude, distanceKm: distance)
    }

    private static func sunEclipticCoordinates(jd: Double) -> (apparentLongitude: Double, distanceAu: Double) {
        let T = (jd - 2451545.0) / 36525.0
        let T2 = T * T

        let L0 = normalizeAngle(280.46646 + 36000.76983 * T + 0.0003032 * T2)
        let M = normalizeAngle(357.52911 + 35999.05029 * T - 0.0001537 * T2)
        let Mr = deg2rad(M)
        let e = 0.016708634 - 0.000042037 * T - 0.0000001267 * T2

        let C =
            (1.914602 - 0.004817 * T - 0.000014 * T2) * sin(Mr)
            + (0.019993 - 0.000101 * T) * sin(2 * Mr)
            + 0.000289 * sin(3 * Mr)

        let trueLongitude = normalizeAngle(L0 + C)
        let trueAnomaly = M + C
        let omega = deg2rad(normalizeAngle(125.04 - 1934.136 * T))
        let apparentLongitude = normalizeAngle(trueLongitude - 0.00569 - 0.00478 * sin(omega))

        let distanceAu = (1.000001018 * (1 - e * e)) / (1 + e * cos(deg2rad(trueAnomaly)))

        return (apparentLongitude: apparentLongitude, distanceAu: distanceAu)
    }

    /// Returns geocentric (RA in hours, Dec in degrees, horizontal parallax in degrees).
    private static func moonEquatorialCoords(jd: Double) -> (ra: Double, dec: Double, parallax: Double) {
        let moon = moonEclipticCoordinates(jd: jd)
        let T = (jd - 2451545.0) / 36525.0
        let epsilon = 23.439291111 - 0.013004167 * T

        let λR = deg2rad(moon.longitude)
        let βR = deg2rad(moon.latitude)
        let εR = deg2rad(epsilon)

        let sinDec = sin(βR) * cos(εR) + cos(βR) * sin(εR) * sin(λR)
        let dec = rad2deg(asin(sinDec))

        var ra = rad2deg(atan2(sin(λR) * cos(εR) - tan(βR) * sin(εR), cos(λR)))
        if ra < 0 { ra += 360.0 }
        ra /= 15.0

        let hp = rad2deg(asin(6378.14 / moon.distanceKm))
        return (ra: ra, dec: dec, parallax: hp)
    }

    // MARK: - Helpers

    private static func julianDay(date: Date) -> Double {
        return date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func dateFromJulianDay(_ jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0)
    }

    private static func decimalYear(fromJulianDay jd: Double) -> Double {
        let date = dateFromJulianDay(jd)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let year = utcCalendar.component(.year, from: date)
        let start = utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: 1,
            day: 1
        ))!
        let next = utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year + 1,
            month: 1,
            day: 1
        ))!

        let fraction = date.timeIntervalSince(start) / next.timeIntervalSince(start)
        return Double(year) + fraction
    }

    /// Piecewise Delta-T approximation (seconds), sufficient for modern civil dates.
    private static func deltaTSeconds(forDecimalYear year: Double) -> Double {
        if year < 2005.0 {
            let t = year - 2000.0
            return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t
                + 0.000651814 * pow(t, 4) + 0.00002373599 * pow(t, 5)
        }
        if year <= 2050.0 {
            let t = year - 2000.0
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        }
        if year <= 2150.0 {
            let u = (year - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - year)
        }

        let u = (year - 1820.0) / 100.0
        return -20.0 + 32.0 * u * u
    }

    private static func normalizeAngle(_ degrees: Double) -> Double {
        let result = degrees.truncatingRemainder(dividingBy: 360.0)
        return result < 0 ? result + 360.0 : result
    }

    private static func normalizeUnitInterval(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 1.0)
        return result < 0 ? result + 1.0 : result
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    private static func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func rad2deg(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}

// MARK: - Moon Shape

struct MoonPhaseShape: Shape {
    let phase: Double

    // Kappa constant for bezier circle/ellipse approximation
    private let kappa: CGFloat = 0.5522847498

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let cx = rect.midX
        let cy = rect.midY

        // Normalize phase to 0...1
        let p = ((phase.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)

        // Calculate terminator ellipse width
        // At new moon (0) and full moon (0.5), cos gives us the terminator position
        let angle = 2 * Double.pi * p
        let cosAngle = cos(angle)

        // Approximate projected terminator width from phase angle.
        let rx = abs(cosAngle) * r

        // Determine which side is lit
        let litOnRight = p < 0.5  // Waxing: right side lit

        // Determine if crescent (less than half lit) or gibbous (more than half lit)
        let isCrescent = (p < 0.25) || (p > 0.75)

        let top = CGPoint(x: cx, y: cy - r)

        path.move(to: top)

        // Draw outer semicircle arc (the edge of the moon)
        // For waxing (litOnRight), draw clockwise (right side)
        // For waning (!litOnRight), draw counter-clockwise (left side)
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: !litOnRight
        )

        // Now at bottom, draw terminator (elliptical arc) back to top
        // The terminator curves based on phase

        if rx < 0.5 {
            // Nearly quarter moon - just a straight line
            path.addLine(to: top)
        } else {
            // Draw half-ellipse for terminator using bezier curves
            // Direction depends on whether it's crescent or gibbous

            let k = kappa

            if litOnRight {
                // Waxing phases - terminator is on the left of the lit area
                if isCrescent {
                    // Waxing crescent - terminator curves RIGHT (into the lit area)
                    // Ellipse bulges toward +x
                    let midRight = CGPoint(x: cx + rx, y: cy)

                    // Bottom to middle-right
                    path.addCurve(
                        to: midRight,
                        control1: CGPoint(x: cx + rx * k, y: cy + r),
                        control2: CGPoint(x: cx + rx, y: cy + r * k)
                    )
                    // Middle-right to top
                    path.addCurve(
                        to: top,
                        control1: CGPoint(x: cx + rx, y: cy - r * k),
                        control2: CGPoint(x: cx + rx * k, y: cy - r)
                    )
                } else {
                    // Waxing gibbous - terminator curves LEFT (away from lit area)
                    // Ellipse bulges toward -x
                    let midLeft = CGPoint(x: cx - rx, y: cy)

                    // Bottom to middle-left
                    path.addCurve(
                        to: midLeft,
                        control1: CGPoint(x: cx - rx * k, y: cy + r),
                        control2: CGPoint(x: cx - rx, y: cy + r * k)
                    )
                    // Middle-left to top
                    path.addCurve(
                        to: top,
                        control1: CGPoint(x: cx - rx, y: cy - r * k),
                        control2: CGPoint(x: cx - rx * k, y: cy - r)
                    )
                }
            } else {
                // Waning phases - terminator is on the right of the lit area
                if isCrescent {
                    // Waning crescent - terminator curves LEFT (into the lit area)
                    // Ellipse bulges toward -x
                    let midLeft = CGPoint(x: cx - rx, y: cy)

                    // Bottom to middle-left
                    path.addCurve(
                        to: midLeft,
                        control1: CGPoint(x: cx - rx * k, y: cy + r),
                        control2: CGPoint(x: cx - rx, y: cy + r * k)
                    )
                    // Middle-left to top
                    path.addCurve(
                        to: top,
                        control1: CGPoint(x: cx - rx, y: cy - r * k),
                        control2: CGPoint(x: cx - rx * k, y: cy - r)
                    )
                } else {
                    // Waning gibbous - terminator curves RIGHT (away from lit area)
                    // Ellipse bulges toward +x
                    let midRight = CGPoint(x: cx + rx, y: cy)

                    // Bottom to middle-right
                    path.addCurve(
                        to: midRight,
                        control1: CGPoint(x: cx + rx * k, y: cy + r),
                        control2: CGPoint(x: cx + rx, y: cy + r * k)
                    )
                    // Middle-right to top
                    path.addCurve(
                        to: top,
                        control1: CGPoint(x: cx + rx, y: cy - r * k),
                        control2: CGPoint(x: cx + rx * k, y: cy - r)
                    )
                }
            }
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Moon Sphere View

struct MoonSphereView: View {
    let phase: Double
    let size: CGFloat
    var showShadow: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.12),
                            Color(white: 0.08),
                            Color(white: 0.03)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )

            MoonPhaseShape(phase: phase)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.95, blue: 0.86),
                            Color(red: 0.84, green: 0.77, blue: 0.63),
                            Color(red: 0.61, green: 0.52, blue: 0.37)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: showShadow ? .purple.opacity(0.3) : .clear, radius: showShadow ? 20 : 0)
    }
}

// MARK: - Info Row

struct MoonInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30)

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

// MARK: - Calendar Day

struct CalendarDayCell: View {
    let date: Date
    let phase: Double
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

    private var day: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                let cellSize = geo.size.width
                let sphereSize = max(14, cellSize * 0.28)
                let fontSize = max(10, cellSize * 0.12)
                let spacing = max(2, cellSize * 0.05)

                VStack(spacing: spacing) {
                    Text("\(day)")
                        .font(.system(size: fontSize))
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(.white.opacity(isCurrentMonth ? 0.8 : 0.3))

                    MoonSphereView(phase: phase, size: sphereSize)
                        .opacity(isCurrentMonth ? 1 : 0.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: max(4, cellSize * 0.08))
                        .fill(isSelected ? .white.opacity(0.1) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(4, cellSize * 0.08))
                        .stroke(isToday ? .white.opacity(0.4) : .clear, lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1.0, contentMode: .fit)
        .contentShape(Rectangle())
        .disabled(!isCurrentMonth)
    }
}

// MARK: - Phase Card

struct PhaseCard: View {
    let index: Int
    let name: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            MoonSphereView(phase: Double(index) / 8.0, size: 36, showShadow: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

// MARK: - Helper

private func formatTime(_ hours: Double) -> String {
    guard hours.isFinite, hours >= 0 else { return "—" }
    let adjusted = (hours + 24).truncatingRemainder(dividingBy: 24)
    let totalMinutes = Int((adjusted * 60.0).rounded()) % (24 * 60)
    let hour = totalMinutes / 60
    let minutes = totalMinutes % 60
    let period = hour >= 12 ? "PM" : "AM"
    let displayHour = ((hour + 11) % 12) + 1
    return String(format: "%d:%02d %@", displayHour, minutes, period)
}

private func formatRiseSet(rise: Double, set: Double) -> String {
    let hasRise = rise.isFinite && rise >= 0
    let hasSet = set.isFinite && set >= 0

    if !hasRise, !hasSet {
        return "Unavailable"
    }
    let riseText = hasRise ? formatTime(rise) : "No rise"
    let setText = hasSet ? formatTime(set) : "No set"
    return "\(riseText) / \(setText)"
}

// MARK: - Date Wheel Picker

struct DateWheelPicker: View {
    @Binding var selectedDate: Date
    @State private var scrolledDate: Date?
    @State private var initialSelectionWorkItem: DispatchWorkItem?

    private let calendar = Calendar.current
    private let itemWidth: CGFloat = 52

    // Pre-computed dates array (cached)
    private let dates: [Date]
    private let today: Date
    private let initialDate: Date
    private let minDay: Date
    private let maxDay: Date

    // Pre-computed formatters (expensive to create)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    init(selectedDate: Binding<Date>, minDate: Date, maxDate: Date) {
        self._selectedDate = selectedDate
        let cal = Calendar.current
        let normalizedMin = cal.startOfDay(for: min(minDate, maxDate))
        let normalizedMax = cal.startOfDay(for: max(minDate, maxDate))
        let clampedInitial = min(max(cal.startOfDay(for: selectedDate.wrappedValue), normalizedMin), normalizedMax)
        let todayStart = cal.startOfDay(for: Date())

        self.minDay = normalizedMin
        self.maxDay = normalizedMax
        self.today = todayStart
        self.initialDate = clampedInitial

        var generated: [Date] = []
        let estimatedCount = (cal.dateComponents([.day], from: normalizedMin, to: normalizedMax).day ?? 0) + 1
        generated.reserveCapacity(max(1, estimatedCount))
        var cursor = normalizedMin
        while cursor <= normalizedMax {
            generated.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.dates = generated
    }

    private func normalizedDay(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        return min(max(day, minDay), maxDay)
    }

    private func selectDate(_ date: Date, animated: Bool = false) {
        let target = normalizedDay(date)

        if !calendar.isDate(selectedDate, inSameDayAs: target) {
            selectedDate = target
        }

        if scrolledDate != target {
            if animated {
                withAnimation {
                    scrolledDate = target
                }
            } else {
                scrolledDate = target
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.monthYearFormatter.string(from: selectedDate))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.6))

            GeometryReader { geometry in
                let horizontalPadding = (geometry.size.width - itemWidth) / 2

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(dates, id: \.self) { date in
                            DateCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: date == today,
                                itemWidth: itemWidth
                            )
                            .id(date)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectDate(date)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledDate, anchor: .center)
                .safeAreaPadding(.horizontal, horizontalPadding)
            }
            .frame(height: 60)
            .onChange(of: scrolledDate) { _, newDate in
                if let newDate = newDate {
                    let day = normalizedDay(newDate)
                    if !calendar.isDate(day, inSameDayAs: selectedDate) {
                        selectedDate = day
                    }
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                let startOfDay = normalizedDay(newDate)
                if scrolledDate != startOfDay {
                    scrolledDate = startOfDay
                }
            }
            .onAppear {
                initialSelectionWorkItem?.cancel()
                // Use a short deferred write so ScrollView has created its layout.
                let workItem = DispatchWorkItem {
                    selectDate(initialDate)
                    initialSelectionWorkItem = nil
                }
                initialSelectionWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }
            .onDisappear {
                initialSelectionWorkItem?.cancel()
                initialSelectionWorkItem = nil
            }

            // Today button
            Button {
                selectDate(today)
            } label: {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(calendar.isDateInToday(selectedDate) || today < minDay || today > maxDay ? 0.3 : 1)
            .disabled(calendar.isDateInToday(selectedDate) || today < minDay || today > maxDay)
        }
    }
}

// Extracted cell for better performance
private struct DateCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let itemWidth: CGFloat

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))

            Text(Self.dayFormatter.string(from: date))
                .font(.body)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
        }
        .frame(width: itemWidth, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? .white.opacity(0.2) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isToday && !isSelected ? .white.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Main View

struct MoonPhaseView: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = Date()
    @State private var isViewActive = false
    @State private var liveNow = Date()
    @State private var currentMoonData = MoonCalculator.getMoonData(for: Date())
    @State private var calendarPhaseCache: [Date: Double] = [:]
    @State private var cachedPhaseMonth: Date?
    @State private var pendingContextRegistration: DispatchWorkItem?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var locationManager = LocationManager.shared

    private let calendar = Calendar.current
    private let phaseTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return ["S", "M", "T", "W", "T", "F", "S"] }
        let firstIndex = (calendar.firstWeekday - 1 + symbols.count) % symbols.count
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    // Date limits: +/- 2 years from today
    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private var minDate: Date {
        calendar.date(byAdding: .year, value: -2, to: todayStart) ?? todayStart
    }

    private var maxDate: Date {
        calendar.date(byAdding: .year, value: 2, to: todayStart) ?? todayStart
    }

    private var minMonth: Date {
        startOfMonth(for: minDate)
    }

    private var maxMonth: Date {
        startOfMonth(for: maxDate)
    }

    private var canGoBack: Bool {
        let currentMonth = startOfMonth(for: displayedMonth)
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else { return false }
        return previousMonth >= minMonth
    }

    private var canGoForward: Bool {
        let currentMonth = startOfMonth(for: displayedMonth)
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { return false }
        return nextMonth <= maxMonth
    }

    private var selectedDay: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private func phaseEvaluationDate(for day: Date) -> Date {
        if calendar.isDateInToday(day) {
            return liveNow
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    private var monthYearString: String {
        Self.monthYearFormatter.string(from: startOfMonth(for: displayedMonth))
    }

    private var calendarDays: [Date] {
        calendarDays(for: displayedMonth)
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func calendarDays(for month: Date) -> [Date] {
        var days: [Date] = []
        let monthStart = startOfMonth(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return days
        }

        let firstOfMonth = monthStart
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let startOffset = (firstWeekday - calendar.firstWeekday + 7) % 7

        for i in 0..<startOffset {
            if let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth) {
                days.append(date)
            }
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }

        let remaining = 42 - days.count
        if remaining > 0, let lastOfMonth = calendar.date(byAdding: .day, value: range.count - 1, to: firstOfMonth) {
            for i in 1...remaining {
                if let date = calendar.date(byAdding: .day, value: i, to: lastOfMonth) {
                    days.append(date)
                }
            }
        }

        return days
    }

    private func rebuildCalendarPhaseCache(for month: Date, force: Bool = false) {
        let monthStart = startOfMonth(for: month)
        guard force || cachedPhaseMonth != monthStart else { return }
        let days = calendarDays(for: monthStart)
        var cache: [Date: Double] = [:]
        cache.reserveCapacity(days.count)
        for date in days {
            cache[date] = MoonCalculator.phase(for: phaseEvaluationDate(for: date))
        }
        calendarPhaseCache = cache
        cachedPhaseMonth = monthStart
    }

    @discardableResult
    private func refreshMoonData(for date: Date? = nil, force: Bool = false) -> MoonData {
        let targetDay = calendar.startOfDay(for: date ?? selectedDate)
        let coord = locationManager.coordinate
        let updated = MoonCalculator.getMoonData(
            for: phaseEvaluationDate(for: targetDay),
            latitude: coord?.latitude,
            longitude: coord?.longitude
        )

        if force || updated != currentMoonData {
            currentMoonData = updated
        }

        return updated
    }

    private func scheduleContextRegistration(for date: Date, data: MoonData) {
        pendingContextRegistration?.cancel()
        let registrationDate = calendar.startOfDay(for: date)
        let moonData = data
        let workItem = DispatchWorkItem {
            registerMoonContext(for: registrationDate, data: moonData)
        }
        pendingContextRegistration = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func cancelPendingContextRegistration() {
        pendingContextRegistration?.cancel()
        pendingContextRegistration = nil
    }

    var body: some View {
        let visibleCalendarDays = calendarDays

        NavigationStack {
            GeometryReader { geometry in
                let metrics = ResponsiveLayoutMetrics(
                    width: geometry.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )
                let primarySideWidth = metrics.splitPaneWidth(fraction: 0.48, minWidth: 340, maxWidth: 490)
                let secondarySideWidth = metrics.splitPaneWidth(fraction: 0.36, minWidth: 300, maxWidth: 380)

                VStack(spacing: 0) {
                    HStack {
                        Text("Moon")
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
                        VStack(spacing: metrics.sectionSpacing) {
                            if metrics.isWideTablet {
                                HStack(alignment: .top, spacing: metrics.cardSpacing) {
                                    VStack(spacing: 20) {
                                        moonDisplaySection(data: currentMoonData, size: 220)
                                        DateWheelPicker(selectedDate: $selectedDate, minDate: minDate, maxDate: maxDate)
                                    }
                                    .frame(width: primarySideWidth, alignment: .top)

                                    VStack(spacing: 16) {
                                        moonInfoCard(data: currentMoonData)
                                        locationStatusFootnote
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }

                                calendarCard(visibleCalendarDays: visibleCalendarDays)
                                    .frame(maxWidth: geometry.size.width * 0.9, alignment: .top)
                                    .frame(maxWidth: .infinity)

                                phasesCard(twoColumn: true)
                                    .frame(maxWidth: .infinity, alignment: .top)
                            } else {
                                moonDisplaySection(data: currentMoonData, size: metrics.isTablet ? 200 : 180)
                                DateWheelPicker(selectedDate: $selectedDate, minDate: minDate, maxDate: maxDate)
                                moonInfoCard(data: currentMoonData)
                                calendarCard(visibleCalendarDays: visibleCalendarDays)
                                    .frame(maxWidth: metrics.isTablet ? geometry.size.width * 0.9 : .infinity)
                                    .frame(maxWidth: .infinity)
                                phasesCard(twoColumn: false)
                                locationStatusFootnote
                            }

                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: metrics.contentMaxWidth)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.bottom, metrics.horizontalPadding)
                        .frame(maxWidth: .infinity)
                    }
                }
                .toolbar(metrics.hidesTopLevelNavigationBar ? .hidden : .visible, for: .navigationBar)
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
            .onChange(of: selectedDate) { _, newDate in
                let selectedDay = calendar.startOfDay(for: newDate)
                let monthStart = startOfMonth(for: selectedDay)
                if !calendar.isDate(monthStart, equalTo: displayedMonth, toGranularity: .month) {
                    displayedMonth = monthStart
                }
                let updated = refreshMoonData(for: selectedDay, force: true)
                if isViewActive {
                    scheduleContextRegistration(for: selectedDay, data: updated)
                }
            }
            .onChange(of: displayedMonth) { _, newMonth in
                rebuildCalendarPhaseCache(for: newMonth)
            }
            .onReceive(phaseTimer) { now in
                liveNow = now
                guard isViewActive else { return }

                if calendar.isDateInToday(selectedDay) {
                    let updated = refreshMoonData(for: selectedDay, force: true)
                    scheduleContextRegistration(for: selectedDay, data: updated)
                }
                if calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month) {
                    rebuildCalendarPhaseCache(for: displayedMonth, force: true)
                }
            }
            .onReceive(locationManager.$coordinate) { _ in
                let updated = refreshMoonData(for: selectedDay, force: true)
                if isViewActive {
                    scheduleContextRegistration(for: selectedDay, data: updated)
                }
            }
            .onAppear {
                isViewActive = true
                liveNow = Date()
                let monthStart = startOfMonth(for: selectedDay)
                displayedMonth = monthStart
                rebuildCalendarPhaseCache(for: monthStart, force: true)
                locationManager.requestLocation()
                cancelPendingContextRegistration()
                let updated = refreshMoonData(for: selectedDay, force: true)
                registerMoonContext(for: selectedDay, data: updated)
                // Start from foreground — ActivityKit forbids starting from background.
                LiveActivityManager.shared.startActivityIfNeeded(caller: "MoonPhaseView.onAppear")
            }
            .onDisappear {
                isViewActive = false
                cancelPendingContextRegistration()
                // Only clear when app is still active (user switched tabs / navigated away).
                // Don't clear when the app is backgrounding — the context is needed to start the activity.
                if scenePhase == .active {
                    ViewStateManager.shared.clearMoonPhaseContext(
                        selectedDate: calendar.startOfDay(for: selectedDay)
                    )
                    LiveActivityManager.shared.endMoonActivity(caller: "MoonPhaseView.onDisappear")
                }
            }
        }
    }

    private func moonDisplaySection(data: MoonData, size: CGFloat) -> some View {
        VStack(spacing: 16) {
            MoonSphereView(phase: data.phase, size: size)

            VStack(spacing: 6) {
                Text(data.phaseName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(data.phaseDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }

    private func moonInfoCard(data: MoonData) -> some View {
        VStack(spacing: 16) {
            MoonInfoRow(icon: "clock", label: "Moon Age", value: String(format: "%.1f days", data.age))
            Divider().background(.white.opacity(0.1))
            MoonInfoRow(icon: "sun.max", label: "Illumination", value: "\(Int(data.illumination * 100))%")
            Divider().background(.white.opacity(0.1))
            MoonInfoRow(icon: "sunrise", label: "Rise / Set", value: formatRiseSet(rise: data.riseHours, set: data.setHours))
            Divider().background(.white.opacity(0.1))
            MoonInfoRow(icon: "arrow.forward.circle", label: "Next Phase", value: "\(data.nextPhase.label) in \(String(format: "%.0f", data.nextPhase.days))d")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func calendarCard(visibleCalendarDays: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lunar Calendar")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        withAnimation {
                            let currentMonth = startOfMonth(for: displayedMonth)
                            let target = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                            displayedMonth = startOfMonth(for: target)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(canGoBack ? 0.6 : 0.2))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .disabled(!canGoBack)

                    Text(monthYearString)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 140)

                    Button {
                        withAnimation {
                            let currentMonth = startOfMonth(for: displayedMonth)
                            let target = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                            displayedMonth = startOfMonth(for: target)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(canGoForward ? 0.6 : 0.2))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .disabled(!canGoForward)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                    GeometryReader { geo in
                        Text(day)
                            .font(.system(size: max(10, geo.size.width * 0.12)))
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 30)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(visibleCalendarDays, id: \.self) { date in
                    let phase = calendarPhaseCache[date] ?? MoonCalculator.phase(for: phaseEvaluationDate(for: date))
                    let isInDisplayedMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    let isWithinRange = date >= minDate && date <= maxDate
                    CalendarDayCell(
                        date: date,
                        phase: phase,
                        isCurrentMonth: isInDisplayedMonth && isWithinRange,
                        isToday: calendar.isDateInToday(date),
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        onTap: { withAnimation { selectedDate = date } }
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func phasesCard(twoColumn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lunar Phases")
                .font(.headline)
                .foregroundStyle(.white)

            if twoColumn {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(0..<8, id: \.self) { index in
                        PhaseCard(
                            index: index,
                            name: MoonCalculator.phaseLabels[index].name,
                            description: MoonCalculator.phaseLabels[index].desc
                        )
                        .padding(12)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                ForEach(0..<8, id: \.self) { index in
                    if index > 0 {
                        Divider().background(.white.opacity(0.1))
                    }
                    PhaseCard(
                        index: index,
                        name: MoonCalculator.phaseLabels[index].name,
                        description: MoonCalculator.phaseLabels[index].desc
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var locationStatusFootnote: some View {
        if locationManager.isDenied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Enable location for accurate rise/set times", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } else if locationManager.coordinate == nil {
            Text("Rise/set times are unavailable until location access is granted.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func registerMoonContext(for date: Date, data: MoonData) {
        pendingContextRegistration = nil
        let contextDate = calendar.startOfDay(for: date)
        ViewStateManager.shared.registerMoonPhase(
            selectedDate: contextDate,
            phase: data.phase,
            illumination: data.illumination,
            phaseName: data.phaseName,
            riseHours: data.riseHours,
            setHours: data.setHours
        )
        // Activity is started only when the app goes to background (see ConstellationApp.swift)
    }
}

#Preview {
    MoonPhaseView()
}
