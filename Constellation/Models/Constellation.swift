import Foundation

struct Constellation: Identifiable, Codable, Sendable {
    var id: String = ""  // JSON에 없는 필드
    let name: String
    let meaning: String
    let illustration: String
    let centerRa: Double
    let centerDec: Double
    let observableSeasons: String
    let description: String
    let constellationScale: Double
    let constellationRotation: Double
    let xShift: Double
    let yShift: Double
    let hemisphere: String
    
    enum CodingKeys: String, CodingKey {
        case name, meaning, illustration, description, hemisphere
        case centerRa = "center_ra"
        case centerDec = "center_dec"
        case observableSeasons = "observable_seasons"
        case constellationScale = "constellation_scale"
        case constellationRotation = "constellation_rotation"
        case xShift = "x_shift"
        case yShift = "y_shift"
        // 주의: 'id'는 여기에 없음! (JSON에 없는 필드라서)
    }
}

// JSON 파일 구조에 맞게 Dictionary로 읽기
struct ConstellationData: Codable, Sendable {
    var constellations: [String: Constellation]
}
