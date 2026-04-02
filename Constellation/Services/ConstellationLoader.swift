import Foundation

enum ConstellationLoader {
    static func loadConstellations() async -> [Constellation] {
        await ConstellationDataStore.shared.constellations()
    }
}
