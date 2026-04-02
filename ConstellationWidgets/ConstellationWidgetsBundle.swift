import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Activity Attributes (must match main app)

struct ConstellationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lastUpdated: Date
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
}

struct MoonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Double
        var illumination: Double
        var phaseName: String
        var riseHours: Double
        var setHours: Double
        var lastUpdated: Date
    }

    let selectedDate: Date
    let startTime: Date
}

// MARK: - Widget Bundle

@main
struct ConstellationWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ConstellationLiveActivity()
        MoonLiveActivity()
    }
}


// MARK: - Debug Toggle
private let DEBUG_SHOW_BOUNDARIES = false

private func formatMoonActivityTime(_ hours: Double) -> String {
    guard hours.isFinite, hours >= 0 else { return "Unavailable" }
    let adjusted = (hours + 24).truncatingRemainder(dividingBy: 24)
    let totalMinutes = Int((adjusted * 60.0).rounded()) % (24 * 60)
    let hour = totalMinutes / 60
    let minutes = totalMinutes % 60
    let period = hour >= 12 ? "PM" : "AM"
    let displayHour = ((hour + 11) % 12) + 1
    return String(format: "%d:%02d %@", displayHour, minutes, period)
}

// ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
// ┃                    DYNAMIC ISLAND CONFIGURATION                         ┃
// ┃                                                                         ┃
// ┃   EXPANDED VIEW LAYOUT:                                                 ┃
// ┃   ┌─────────────┬─────────────────┬─────────────┐                      ┃
// ┃   │             │     CENTER      │             │                      ┃
// ┃   │   LEFT      │  ┌───────────┐  │   RIGHT     │                      ┃
// ┃   │   BOX       │  │  SENSOR   │  │   BOX       │                      ┃
// ┃   │  (visual)   │  │   AREA    │  │  (info)     │                      ┃
// ┃   │             │  └───────────┘  │             │                      ┃
// ┃   └─────────────┴─────────────────┴─────────────┘                      ┃
// ┃                                                                         ┃
// ┃   COMPACT VIEW LAYOUT:                                                  ┃
// ┃   ┌──────┐ ┌─────────────┐ ┌──────┐                                    ┃
// ┃   │ LEFT │ │   SENSOR    │ │RIGHT │                                    ┃
// ┃   └──────┘ └─────────────┘ └──────┘                                    ┃
// ┃                                                                         ┃
// ┃   MINIMAL VIEW: Just one small circle                                   ┃
// ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

// ============================================================================
// EXPANDED VIEW - Edit these values
// ============================================================================

// LEFT BOX (Star pattern or Moon visual)
let LEFT_BOX_WIDTH: CGFloat = 110
let LEFT_BOX_HEIGHT: CGFloat = 110
let LEFT_BOX_X: CGFloat = 0           // move right(+) or left(-)
let LEFT_BOX_Y: CGFloat = 0           // move down(+) or up(-)
let LEFT_BOX_PADDING: CGFloat = 0     // padding from edge

// RIGHT BOX (Info text)
let RIGHT_BOX_WIDTH: CGFloat = 220    // width of right box
let RIGHT_BOX_HEIGHT: CGFloat = 60    // height of right box
let RIGHT_BOX_X: CGFloat = -10          // move right(+) or left(-)
let RIGHT_BOX_Y: CGFloat = 14         // move down(+) or up(-)
let RIGHT_BOX_PADDING: CGFloat = 0    // padding from edge
let RIGHT_BOX_SPACING: CGFloat = 0    // spacing between text lines

// BOTTOM BOX (below sensor)
let BOTTOM_BOX_WIDTH: CGFloat = 220   // width of bottom box
let BOTTOM_BOX_HEIGHT: CGFloat = 45   // height of bottom box
let BOTTOM_BOX_X: CGFloat = -10         // move right(+) or left(-)
let BOTTOM_BOX_Y: CGFloat = 0         // move down(+) or up(-)

// FONT SIZES
let FONT_TITLE: CGFloat = 21          // main title
let FONT_SUBTITLE: CGFloat = 16       // secondary text
let FONT_DETAIL: CGFloat = 14         // small details

// ============================================================================
// COMPACT VIEW - Edit these values
// ============================================================================

// LEFT SIDE (small visual)
let COMPACT_LEFT_WIDTH: CGFloat = 34
let COMPACT_LEFT_HEIGHT: CGFloat = 26
let COMPACT_LEFT_X: CGFloat = 2
let COMPACT_LEFT_Y: CGFloat = 0

// RIGHT SIDE (small text)
let COMPACT_RIGHT_WIDTH: CGFloat = 40
let COMPACT_RIGHT_HEIGHT: CGFloat = 26
let COMPACT_RIGHT_FONT: CGFloat = 13
let COMPACT_RIGHT_X: CGFloat = 0
let COMPACT_RIGHT_Y: CGFloat = 0

// ============================================================================
// MINIMAL VIEW - Edit these values
// ============================================================================

let MINIMAL_SIZE: CGFloat = 22
let MINIMAL_X: CGFloat = 0
let MINIMAL_Y: CGFloat = 0

// Helper to add debug border
extension View {
    @ViewBuilder
    func debugBorder(_ color: Color = .red) -> some View {
        if DEBUG_SHOW_BOUNDARIES {
            self.overlay(Rectangle().stroke(color, lineWidth: 1))
        } else {
            self
        }
    }

    @ViewBuilder
    func debugBorderWithSize(_ color: Color = .red, label: String? = nil) -> some View {
        if DEBUG_SHOW_BOUNDARIES {
            self.overlay(
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Rectangle().stroke(color, lineWidth: 1)
                        Text(label ?? "\(Int(geo.size.width))×\(Int(geo.size.height))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                            .padding(2)
                            .background(Color.black.opacity(0.7))
                    }
                }
            )
        } else {
            self
        }
    }
}

// Debug view to show the Dynamic Island sensor area (camera cutout)
// This represents the hardware area that CANNOT display content
struct DynamicIslandSensorOverlay: View {
    // MARK: - Adjust these values to match the actual sensor position
    static let sensorWidth: CGFloat = 126    // Width of the sensor pill
    static let sensorHeight: CGFloat = 37    // Height of the sensor pill
    static let offsetX: CGFloat = 0          // + moves right, - moves left
    static let offsetY: CGFloat = -37.1       // + moves down, - moves up

    var body: some View {
        if DEBUG_SHOW_BOUNDARIES {
            // The sensor pill area - approximately 126x37 points (iPhone 14 Pro/15 Pro)
            // This is the "dead zone" where no content can appear
            Capsule()
                .fill(Color.red.opacity(0.3))
                .overlay(
                    Capsule()
                        .stroke(Color.red, lineWidth: 2)
                )
                .overlay(
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10))
                        Text("SENSOR")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.red)
                )
                .frame(width: Self.sensorWidth, height: Self.sensorHeight)
                .offset(x: Self.offsetX, y: Self.offsetY)
        }
    }
}

// MARK: - Constellation Live Activity

struct ConstellationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConstellationActivityAttributes.self) { context in
            ConstellationLockScreenView(attributes: context.attributes)
                .debugBorder(.red)
                .activityBackgroundTint(Color(red: 0.02, green: 0.02, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // LEFT BOX - Star pattern visual
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.leading) {
                    StarPatternView(
                        stars: context.attributes.normalizedStars,
                        connections: context.attributes.connections,
                        size: LEFT_BOX_WIDTH
                    )
                    .frame(width: LEFT_BOX_WIDTH, height: LEFT_BOX_HEIGHT)
                    .offset(x: LEFT_BOX_X, y: LEFT_BOX_Y)
                    .padding(.leading, LEFT_BOX_PADDING)
                    .debugBorderWithSize(.red, label: "LEFT")
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // RIGHT BOX - Info text
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{
                        Spacer()
                        VStack(alignment: .trailing, spacing: RIGHT_BOX_SPACING) {
                            Text(context.attributes.name)
                                .font(.system(size: FONT_TITLE, weight: .bold))
                                .foregroundStyle(.white)

                            Text(context.attributes.meaning)
                                .font(.system(size: FONT_SUBTITLE))
                                .foregroundStyle(.white.opacity(0.7))

                        }
                    }
                    
                    .frame(width: RIGHT_BOX_WIDTH, height: RIGHT_BOX_HEIGHT)
                    .offset(x: RIGHT_BOX_X, y: RIGHT_BOX_Y)
                    .padding(.trailing, RIGHT_BOX_PADDING)
                    .debugBorderWithSize(.blue, label: "RIGHT")
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // BOTTOM BOX
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{
                        Spacer()
                        VStack(alignment: .trailing, spacing: RIGHT_BOX_SPACING) {
                            HStack{
                                Text("Hemisphere: ")
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                
                                Text(context.attributes.hemisphere)
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            HStack{
                                Text("RA / DEC :")
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(String(format: "%.1f° / %.1f°", context.attributes.centerRa, context.attributes.centerDec))
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                        }
                    }
                        .frame(width: BOTTOM_BOX_WIDTH, height: BOTTOM_BOX_HEIGHT)
                        .offset(x: BOTTOM_BOX_X, y: BOTTOM_BOX_Y)
                        .padding(.trailing, RIGHT_BOX_PADDING)
                        .debugBorderWithSize(.green, label: "BOTTOM")
                }

                //
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandSensorOverlay()
                }
            } compactLeading: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // COMPACT LEFT
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                StarPatternView(
                    stars: context.attributes.normalizedStars,
                    connections: context.attributes.connections,
                    size: min(COMPACT_LEFT_WIDTH, COMPACT_LEFT_HEIGHT)
                )
                .frame(width: COMPACT_LEFT_WIDTH, height: COMPACT_LEFT_HEIGHT)
                .offset(x: COMPACT_LEFT_X, y: COMPACT_LEFT_Y)
                .debugBorderWithSize(.red, label: "L")
                
            } compactTrailing: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // COMPACT RIGHT
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Text(context.attributes.constellationId.uppercased())
                    .font(.system(size: COMPACT_RIGHT_FONT, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: COMPACT_RIGHT_WIDTH, height: COMPACT_RIGHT_HEIGHT)
                    .offset(x: COMPACT_RIGHT_X, y: COMPACT_RIGHT_Y)
                    .debugBorderWithSize(.blue, label: "R")
                
            } minimal: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // MINIMAL - Show constellation abbreviation
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Text(context.attributes.constellationId.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(x: MINIMAL_X, y: MINIMAL_Y)
                    .debugBorderWithSize(.red, label: "MIN")
            }
        }
    }
}

// MARK: - Moon Live Activity

struct MoonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MoonActivityAttributes.self) { context in
            MoonLockScreenView(state: context.state)
                .debugBorder(.red)
                .activityBackgroundTint(Color(red: 0.02, green: 0.02, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // LEFT BOX - Moon visual
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.leading) {
                    MoonView(phase: context.state.phase, size: LEFT_BOX_WIDTH)
                        .frame(width: LEFT_BOX_WIDTH, height: LEFT_BOX_HEIGHT)
                        .offset(x: LEFT_BOX_X, y: LEFT_BOX_Y)
                        .padding(.leading, LEFT_BOX_PADDING)
                        .debugBorderWithSize(.red, label: "LEFT")
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // RIGHT BOX - Info text
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(context.state.phaseName)
                                .font(.system(size: FONT_TITLE, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Illumination : \(Int(context.state.illumination * 100))%")
                                .font(.system(size: FONT_SUBTITLE))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(width: RIGHT_BOX_WIDTH, height: RIGHT_BOX_HEIGHT)
                    .offset(x: RIGHT_BOX_X, y: RIGHT_BOX_Y)
                    .padding(.trailing, RIGHT_BOX_PADDING)
                    .debugBorderWithSize(.blue, label: "RIGHT")
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // BOTTOM BOX
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.trailing) {
                    HStack{
                        Spacer()
                        VStack(alignment: .trailing) {
                            HStack(spacing: 4) {
                                Image(systemName: "sunrise.fill")
                                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.9))
                                Text(formatTime(context.state.riseHours))
                                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.9))

                                Image(systemName: "sunset.fill")
                                    .foregroundStyle(Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.9))
                                Text(formatTime(context.state.setHours))
                                    .foregroundStyle(Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.9))
                            }
                            .font(.system(size: FONT_DETAIL, weight: .medium))
                            HStack{
                                Text("Moon Age :")
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(String(format: "%.1f days", context.state.phase * 29.53))
                                    .font(.system(size: FONT_DETAIL, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                        }
                    }
                    .frame(width: BOTTOM_BOX_WIDTH, height: BOTTOM_BOX_HEIGHT)
                    .offset(x: BOTTOM_BOX_X, y: BOTTOM_BOX_Y)
                    .padding(.trailing, RIGHT_BOX_PADDING)
                    .debugBorderWithSize(.green, label: "BOTTOM")

                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // CENTER - Sensor area (debug only)
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandSensorOverlay()
                }
            } compactLeading: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // COMPACT LEFT
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                MoonView(phase: context.state.phase, size: min(COMPACT_LEFT_WIDTH, COMPACT_LEFT_HEIGHT))
                    .frame(width: COMPACT_LEFT_WIDTH, height: COMPACT_LEFT_HEIGHT)
                    .offset(x: COMPACT_LEFT_X, y: COMPACT_LEFT_Y)
                    .debugBorderWithSize(.red, label: "L")
            } compactTrailing: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // COMPACT RIGHT
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Text("\(Int(context.state.illumination * 100))%")
                    .font(.system(size: COMPACT_RIGHT_FONT, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.86))
                    .frame(width: COMPACT_RIGHT_WIDTH, height: COMPACT_RIGHT_HEIGHT)
                    .offset(x: COMPACT_RIGHT_X, y: COMPACT_RIGHT_Y)
                    .debugBorderWithSize(.blue, label: "R")
            } minimal: {
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // MINIMAL
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                MoonView(phase: context.state.phase, size: MINIMAL_SIZE)
                    .offset(x: MINIMAL_X, y: MINIMAL_Y)
                    .debugBorderWithSize(.red, label: "MIN")
            }
        }
    }

    private func formatTime(_ hours: Double) -> String {
        let adjusted = (hours + 24).truncatingRemainder(dividingBy: 24)
        let hour = Int(adjusted)
        let minutes = Int((adjusted - Double(hour)) * 60)
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = ((hour + 11) % 12) + 1
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}

// MARK: - Lock Screen Views

struct ConstellationLockScreenView: View {
    let attributes: ConstellationActivityAttributes

    var body: some View {
        HStack(spacing: 14) {
            StarPatternView(
                stars: attributes.normalizedStars,
                connections: attributes.connections,
                size: 72
            )
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.3), lineWidth: 1)
                    )
            )
            .debugBorder(.yellow)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text(attributes.meaning)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .debugBorder(.cyan)

                HStack(spacing: 10) {
                    Label(attributes.hemisphere, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("•")
                        .foregroundStyle(.white.opacity(0.3))

                    Text(String(format: "%.0f° / %.0f°", attributes.centerRa, attributes.centerDec))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.9))
                }
                .debugBorder(.green)
            }
            .debugBorder(.blue)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct MoonLockScreenView: View {
    let state: MoonActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            MoonView(phase: state.phase, size: 64)
                .frame(width: 72, height: 72)
                .debugBorder(.yellow)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.phaseName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Illumination: \(Int(state.illumination * 100))%")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .debugBorder(.cyan)

                HStack(spacing: 14) {
                    Label(formatMoonActivityTime(state.riseHours), systemImage: "sunrise.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.9))

                    Label(formatMoonActivityTime(state.setHours), systemImage: "sunset.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.9))
                }
                .debugBorder(.green)
            }
            .debugBorder(.blue)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Star Pattern View

struct StarPatternView: View {
    let stars: [[Double]]
    let connections: [[Int]]
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            let scale = min(canvasSize.width, canvasSize.height) * 0.4

            var positions: [CGPoint] = []
            for star in stars {
                guard star.count >= 2 else { continue }
                let x = centerX + star[0] * scale
                let y = centerY - star[1] * scale
                positions.append(CGPoint(x: x, y: y))
            }

            for connection in connections {
                guard connection.count >= 2,
                      connection[0] < positions.count,
                      connection[1] < positions.count else { continue }

                var path = Path()
                path.move(to: positions[connection[0]])
                path.addLine(to: positions[connection[1]])

                context.stroke(
                    path,
                    with: .color(Color(red: 0.58, green: 0.44, blue: 0.86).opacity(0.6)),
                    lineWidth: 1
                )
            }

            for position in positions {
                let starPath = Circle().path(in: CGRect(
                    x: position.x - 2,
                    y: position.y - 2,
                    width: 4,
                    height: 4
                ))
                context.fill(starPath, with: .color(.white))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Moon Phase View

struct MoonView: View {
    let phase: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.08))

            MoonShape(phase: phase)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.95, blue: 0.86),
                            Color(red: 0.84, green: 0.77, blue: 0.63)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct MoonShape: Shape {
    let phase: Double
    private let kappa: CGFloat = 0.5522847498

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let cx = rect.midX
        let cy = rect.midY

        let p = ((phase.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
        let angle = 2 * Double.pi * p
        let cosAngle = cos(angle)
        let rx = abs(cosAngle) * r
        let litOnRight = p < 0.5
        let isCrescent = (p < 0.25) || (p > 0.75)

        let top = CGPoint(x: cx, y: cy - r)

        path.move(to: top)

        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: !litOnRight
        )

        if rx < 0.5 {
            path.addLine(to: top)
        } else {
            let k = kappa

            if litOnRight {
                if isCrescent {
                    let mid = CGPoint(x: cx + rx, y: cy)
                    path.addCurve(to: mid, control1: CGPoint(x: cx + rx * k, y: cy + r), control2: CGPoint(x: cx + rx, y: cy + r * k))
                    path.addCurve(to: top, control1: CGPoint(x: cx + rx, y: cy - r * k), control2: CGPoint(x: cx + rx * k, y: cy - r))
                } else {
                    let mid = CGPoint(x: cx - rx, y: cy)
                    path.addCurve(to: mid, control1: CGPoint(x: cx - rx * k, y: cy + r), control2: CGPoint(x: cx - rx, y: cy + r * k))
                    path.addCurve(to: top, control1: CGPoint(x: cx - rx, y: cy - r * k), control2: CGPoint(x: cx - rx * k, y: cy - r))
                }
            } else {
                if isCrescent {
                    let mid = CGPoint(x: cx - rx, y: cy)
                    path.addCurve(to: mid, control1: CGPoint(x: cx - rx * k, y: cy + r), control2: CGPoint(x: cx - rx, y: cy + r * k))
                    path.addCurve(to: top, control1: CGPoint(x: cx - rx, y: cy - r * k), control2: CGPoint(x: cx - rx * k, y: cy - r))
                } else {
                    let mid = CGPoint(x: cx + rx, y: cy)
                    path.addCurve(to: mid, control1: CGPoint(x: cx + rx * k, y: cy + r), control2: CGPoint(x: cx + rx, y: cy + r * k))
                    path.addCurve(to: top, control1: CGPoint(x: cx + rx, y: cy - r * k), control2: CGPoint(x: cx + rx * k, y: cy - r))
                }
            }
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Debug Overlay for Previews

struct DebugBoundaryOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                Path { path in
                    let step: CGFloat = 10
                    // Vertical lines
                    for x in stride(from: 0, through: geometry.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    // Horizontal lines
                    for y in stride(from: 0, through: geometry.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.green.opacity(0.3), lineWidth: 0.5)

                // Border
                Rectangle()
                    .stroke(Color.red, lineWidth: 2)

                // Center lines
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.yellow, lineWidth: 1)

                // Size label
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(geometry.size.width))x\(Int(geometry.size.height))")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.7))
                    }
                }
            }
        }
    }
}

// Debug wrapper for Lock Screen view
struct DebugLockScreenView<Content: View>: View {
    let content: Content
    let showDebug: Bool

    init(showDebug: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDebug = showDebug
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            if showDebug {
                DebugBoundaryOverlay()
            }
        }
    }
}

// MARK: - Previews

// Sample data for previews
private let sampleConstellationAttributes = ConstellationActivityAttributes(
    constellationId: "WWW",
    name: "Triangulum Australe",
    meaning: "Scorpion",
    centerRa: 85.25,
    centerDec: -2.5,
    hemisphere: "Both",
    normalizedStars: [
        [-1, 1],   // Betelgeuse
        [1, 1],    // Bellatrix
        [-0.2, 0.0],   // Alnitak
        [0.0, 0.0],    // Alnilam
        [0.2, 0.0],    // Mintaka
        [-1, -1],  // Saiph
        [1, -1]    // Rigel
    ],
    connections: [[0, 2], [1, 4], [2, 3], [3, 4], [2, 5], [4, 6]],
    startTime: Date()
)

private let sampleConstellationState = ConstellationActivityAttributes.ContentState(
    lastUpdated: Date()
)

private let sampleMoonAttributes = MoonActivityAttributes(
    selectedDate: Date(),
    startTime: Date()
)

private let sampleMoonState = MoonActivityAttributes.ContentState(
    phase: 0.5,
    illumination: 1,
    phaseName: "Waxing Crescent",
    riseHours: 12.5,
    setHours: 0.5,
    lastUpdated: Date()
)

// Constellation Previews
#Preview("Constellation - Lock Screen", as: .content, using: sampleConstellationAttributes) {
    ConstellationLiveActivity()
} contentStates: {
    sampleConstellationState
}

#Preview("Constellation - Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: sampleConstellationAttributes) {
    ConstellationLiveActivity()
} contentStates: {
    sampleConstellationState
}

#Preview("Constellation - Dynamic Island Compact", as: .dynamicIsland(.compact), using: sampleConstellationAttributes) {
    ConstellationLiveActivity()
} contentStates: {
    sampleConstellationState
}

#Preview("Constellation - Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: sampleConstellationAttributes) {
    ConstellationLiveActivity()
} contentStates: {
    sampleConstellationState
}

// Moon Previews
#Preview("Moon - Lock Screen", as: .content, using: sampleMoonAttributes) {
    MoonLiveActivity()
} contentStates: {
    sampleMoonState
}

#Preview("Moon - Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: sampleMoonAttributes) {
    MoonLiveActivity()
} contentStates: {
    sampleMoonState
}

#Preview("Moon - Dynamic Island Compact", as: .dynamicIsland(.compact), using: sampleMoonAttributes) {
    MoonLiveActivity()
} contentStates: {
    sampleMoonState
}

#Preview("Moon - Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: sampleMoonAttributes) {
    MoonLiveActivity()
} contentStates: {
    sampleMoonState
}
