//
//  ConstellationTests.swift
//  ConstellationTests
//
//  Created by 최원 on 1/22/26.
//

import Testing
@testable import Constellation

struct ConstellationTests {

    @Test @MainActor
    func clearMoonPhaseContextIgnoresDifferentDay() {
        let manager = ViewStateManager.shared
        manager.clearContext()

        let registeredDate = Date(timeIntervalSince1970: 1_710_000_000)
        manager.registerMoonPhase(
            selectedDate: registeredDate,
            phase: 0.25,
            illumination: 0.5,
            phaseName: "First Quarter",
            riseHours: 6.0,
            setHours: 18.0
        )

        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: registeredDate)!
        manager.clearMoonPhaseContext(selectedDate: nextDay)

        #expect(manager.currentContext == .moonPhase(moon: ViewStateManager.MoonContext(
            selectedDate: registeredDate,
            phase: 0.25,
            illumination: 0.5,
            phaseName: "First Quarter",
            riseHours: 6.0,
            setHours: 18.0
        )))
    }

    @Test @MainActor
    func clearMoonPhaseContextClearsMatchingDay() {
        let manager = ViewStateManager.shared
        manager.clearContext()

        let registeredDate = Date(timeIntervalSince1970: 1_710_000_000)
        manager.registerMoonPhase(
            selectedDate: registeredDate,
            phase: 0.9,
            illumination: 0.95,
            phaseName: "Full Moon",
            riseHours: -1.0,
            setHours: 4.5
        )

        let laterSameDay = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: registeredDate)!
        manager.clearMoonPhaseContext(selectedDate: laterSameDay)

        #expect(manager.currentContext == .other)
    }

    @Test @MainActor
    func clearConstellationDetailContextClearsOnlyMatchingId() {
        let manager = ViewStateManager.shared
        manager.clearContext()

        manager.registerConstellationDetail(
            id: "ori",
            name: "Orion",
            meaning: "The Hunter",
            centerRa: 83.8,
            centerDec: -1.2,
            hemisphere: "Both",
            stars: [(x: 0.0, y: 0.0)],
            connections: [[0, 0]]
        )

        manager.clearConstellationDetailContext(id: "uma")
        #expect(manager.currentContext == .constellationDetail(constellation: ViewStateManager.ConstellationContext(
            id: "ori",
            name: "Orion",
            meaning: "The Hunter",
            centerRa: 83.8,
            centerDec: -1.2,
            hemisphere: "Both",
            stars: [ViewStateManager.ConstellationContext.StarPosition(x: 0.0, y: 0.0)],
            connections: [[0, 0]]
        )))

        manager.clearConstellationDetailContext(id: "ori")
        #expect(manager.currentContext == .other)
    }

}
