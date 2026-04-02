import Foundation

actor ConstellationDataStore {
    static let shared = ConstellationDataStore()

    private var constellationsCache: [Constellation]?
    private var starsCache: [String: ConstellationStars]?
    private var illustrationToIdCache: [String: String]?

    private var constellationsTask: Task<[Constellation], Never>?
    private var starsTask: Task<[String: ConstellationStars], Never>?

    private init() {}

    func preload() async {
        _ = await constellations()
        _ = await stars()
    }

    func constellations() async -> [Constellation] {
        if let cache = constellationsCache {
            return cache
        }
        if let task = constellationsTask {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            Self.decodeConstellations()
        }
        constellationsTask = task

        let loaded = await task.value
        constellationsCache = loaded
        constellationsTask = nil
        if illustrationToIdCache == nil {
            illustrationToIdCache = Self.buildIllustrationMap(from: loaded)
        }
        return loaded
    }

    func stars() async -> [String: ConstellationStars] {
        if let cache = starsCache {
            return cache
        }
        if let task = starsTask {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            Self.decodeStars()
        }
        starsTask = task

        let loaded = await task.value
        starsCache = loaded
        starsTask = nil
        return loaded
    }

    func stars(for constellationId: String) async -> ConstellationStars? {
        guard !constellationId.isEmpty else {
            appDebugLog("⚠️ Empty constellation ID provided")
            return nil
        }
        return await stars()[constellationId]
    }

    func stars(forIllustration illustration: String) async -> ConstellationStars? {
        let filename = Self.normalizedIllustrationName(illustration)
        let map = await illustrationToIdMap()

        guard let id = map[filename] else {
            appDebugLog("❌ No constellation mapping found for illustration '\(filename)'")
            return nil
        }

        return await stars()[id]
    }

    private func illustrationToIdMap() async -> [String: String] {
        if let cache = illustrationToIdCache {
            return cache
        }

        let loadedConstellations = await constellations()
        let map = Self.buildIllustrationMap(from: loadedConstellations)
        illustrationToIdCache = map
        return map
    }

    private static func normalizedIllustrationName(_ illustration: String) -> String {
        illustration.replacingOccurrences(of: ".png", with: "").lowercased()
    }

    private static func buildIllustrationMap(from constellations: [Constellation]) -> [String: String] {
        Dictionary(
            constellations.map { (normalizedIllustrationName($0.illustration), $0.id) },
            uniquingKeysWith: { first, second in
                appDebugLog("⚠️ Duplicate illustration key '\(first)' — keeping first")
                return first
            }
        )
    }

    private static func decodeConstellations() -> [Constellation] {
        guard let url = Bundle.main.url(forResource: "constellations-map", withExtension: "json") else {
            appDebugLog("❌ constellations-map.json file not found")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            appDebugLog("❌ Failed to read constellations-map.json")
            return []
        }

        do {
            let dict = try JSONDecoder().decode([String: Constellation].self, from: data)
            return dict
                .map { key, value in
                    var constellation = value
                    constellation.id = key
                    return constellation
                }
                .sorted { $0.name < $1.name }
        } catch {
            appDebugLog("❌ Failed to decode constellations-map.json: \(error)")
            return []
        }
    }

    private static func decodeStars() -> [String: ConstellationStars] {
        guard let url = Bundle.main.url(forResource: "constellation-stars", withExtension: "json") else {
            appDebugLog("❌ constellation-stars.json file not found")
            return [:]
        }

        guard let data = try? Data(contentsOf: url) else {
            appDebugLog("❌ Failed to read constellation-stars.json")
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: ConstellationStars].self, from: data)
        } catch {
            appDebugLog("❌ Failed to decode constellation-stars.json: \(error)")
            return [:]
        }
    }
}
