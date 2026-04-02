import Combine
import Foundation
import SwiftUI

/// Tracks the current view context for Live Activity management
@MainActor
final class ViewStateManager: ObservableObject {
    static let shared = ViewStateManager()

    /// Represents the current view state of the app
    enum CurrentViewContext: Equatable {
        /// User is viewing a constellation detail
        case constellationDetail(constellation: ConstellationContext)
        /// User is viewing moon phase
        case moonPhase(moon: MoonContext)
        /// User is in any other view
        case other

        static func == (lhs: CurrentViewContext, rhs: CurrentViewContext) -> Bool {
            switch (lhs, rhs) {
            case (.constellationDetail(let l), .constellationDetail(let r)):
                return l.id == r.id
            case (.moonPhase(let l), .moonPhase(let r)):
                return l.selectedDate == r.selectedDate
            case (.other, .other):
                return true
            default:
                return false
            }
        }
    }

    /// Context data for a constellation
    struct ConstellationContext {
        let id: String
        let name: String
        let meaning: String
        let centerRa: Double
        let centerDec: Double
        let hemisphere: String
        let stars: [StarPosition]
        let connections: [[Int]]

        struct StarPosition {
            let x: Double
            let y: Double
        }
    }

    /// Context data for moon phase
    struct MoonContext {
        let selectedDate: Date
        let phase: Double
        let illumination: Double
        let phaseName: String
        let riseHours: Double
        let setHours: Double
    }

    /// The current view context
    @Published private(set) var currentContext: CurrentViewContext = .other

    private init() {}

    /// Register that the user is viewing a constellation detail
    func registerConstellationDetail(
        id: String,
        name: String,
        meaning: String,
        centerRa: Double,
        centerDec: Double,
        hemisphere: String,
        stars: [(x: Double, y: Double)],
        connections: [[Int]]
    ) {
        let starPositions = stars.map { ConstellationContext.StarPosition(x: $0.x, y: $0.y) }
        let context = ConstellationContext(
            id: id,
            name: name,
            meaning: meaning,
            centerRa: centerRa,
            centerDec: centerDec,
            hemisphere: hemisphere,
            stars: starPositions,
            connections: connections
        )
        currentContext = .constellationDetail(constellation: context)
        appDebugTrace {
            print("═══════════════════════════════════════════")
            print("📍 ViewStateManager: REGISTERED constellation")
            print("📍 Name: \(name)")
            print("📍 ID: \(id)")
            print("📍 Stars count: \(stars.count)")
            print("📍 Connections count: \(connections.count)")
            print("📍 Current context is now: \(currentContext)")
            print("═══════════════════════════════════════════")
        }
    }

    /// Register that the user is viewing moon phase
    func registerMoonPhase(
        selectedDate: Date,
        phase: Double,
        illumination: Double,
        phaseName: String,
        riseHours: Double,
        setHours: Double
    ) {
        let context = MoonContext(
            selectedDate: selectedDate,
            phase: phase,
            illumination: illumination,
            phaseName: phaseName,
            riseHours: riseHours,
            setHours: setHours
        )
        currentContext = .moonPhase(moon: context)
        appDebugTrace {
            print("═══════════════════════════════════════════")
            print("📍 ViewStateManager: REGISTERED moon phase")
            print("📍 Phase name: \(phaseName)")
            print("📍 Phase: \(phase)")
            print("📍 Illumination: \(illumination)")
            print("📍 Current context is now: \(currentContext)")
            print("═══════════════════════════════════════════")
        }
    }

    /// Clear the current context (user left the tracked view)
    func clearContext() {
        appDebugTrace {
            print("═══════════════════════════════════════════")
            print("📍 ViewStateManager: CLEARING context")
            print("📍 Previous context was: \(currentContext)")
        }
        currentContext = .other
        appDebugTrace {
            print("📍 Context is now: .other")
            print("═══════════════════════════════════════════")
        }
    }

    /// Clear the constellation context only if it still belongs to the provided view.
    func clearConstellationDetailContext(id: String) {
        guard case .constellationDetail(let context) = currentContext,
              context.id == id else {
            return
        }
        clearContext()
    }

    /// Clear the moon context only if it still belongs to the provided view.
    func clearMoonPhaseContext(selectedDate: Date) {
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        guard case .moonPhase(let context) = currentContext,
              Calendar.current.startOfDay(for: context.selectedDate) == targetDate else {
            return
        }
        clearContext()
    }
}
