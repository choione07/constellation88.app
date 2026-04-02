import Foundation

enum ConstellationStarLoader {
    static func loadStars() async -> [String: ConstellationStars] {
        await ConstellationDataStore.shared.stars()
    }

    static func getStars(for constellationId: String) async -> ConstellationStars? {
        await ConstellationDataStore.shared.stars(for: constellationId)
    }

    static func getStars(forIllustration illustration: String) async -> ConstellationStars? {
        await ConstellationDataStore.shared.stars(forIllustration: illustration)
    }
}
