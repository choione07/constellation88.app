import Foundation

struct ConstellationStars: Codable, Sendable {
    let stars: [Star]
    let connections: [[String]]
    
    struct Star: Codable, Sendable {
        let hip: String
        let x: Double
        let y: Double
    }
}
