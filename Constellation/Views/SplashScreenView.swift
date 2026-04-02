import SwiftUI

// Animation values for the star
struct StarAnimationValues {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0
    var rotation: Double = 0
    var glowRadius: CGFloat = 30
}

struct SplashScreenView: View {
    @State private var animateStar = false
    @State private var isPulsing = false
    @State private var pulseGlow: CGFloat = 30
    @State private var textOpacity: Double = 0
    @State private var textScale: CGFloat = 0.9
    @State private var dotComOpacity: Double = 0

    var onAnimationComplete: () -> Void

    private let goldColor = Color(red: 1.0, green: 0.843, blue: 0.0) // #FFD700

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Radial gradient background
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 0.106, green: 0.078, blue: 0.392), location: 0),
                        .init(color: Color(red: 0.039, green: 0.039, blue: 0.180), location: 0.45),
                        .init(color: Color.black, location: 0.85)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.height * 0.7
                )
                .ignoresSafeArea()

                // Logo container
                HStack(spacing: 20) {
                    // Star with keyframe animation
                    KeyframeAnimator(
                        initialValue: StarAnimationValues(
                            offsetX: 800,
                            offsetY: -100,
                            scale: 0.3,
                            rotation: -360,
                            glowRadius: 50
                        ),
                        trigger: animateStar
                    ) { values in
                        StarShape()
                            .fill(goldColor)
                            .frame(width: 80, height: 80)
                            .shadow(color: goldColor, radius: isPulsing ? pulseGlow : values.glowRadius)
                            .scaleEffect(values.scale)
                            .rotationEffect(.degrees(values.rotation))
                            .offset(x: values.offsetX, y: values.offsetY)
                    } keyframes: { _ in
                        KeyframeTrack(\.offsetX) {
                            CubicKeyframe(200, duration: 1)
                            CubicKeyframe(-8, duration: 0.5)
                            CubicKeyframe(0, duration: 0.4)
                        }
                        KeyframeTrack(\.offsetY) {
                            CubicKeyframe(-20, duration: 1)
                            CubicKeyframe(0, duration: 0.5)
                            CubicKeyframe(0, duration: 0.4)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(0.8, duration: 1)
                            CubicKeyframe(1.05, duration: 0.5)
                            CubicKeyframe(1.0, duration: 0.4)
                        }
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(180, duration: 1)
                            CubicKeyframe(-10, duration: 0.5)
                            CubicKeyframe(0, duration: 0.4)
                        }
                        KeyframeTrack(\.glowRadius) {
                            CubicKeyframe(40, duration: 1)
                            CubicKeyframe(35, duration: 0.5)
                            CubicKeyframe(30, duration: 0.4)
                        }
                    }

                    // Text container
                    VStack(alignment: .leading, spacing: -6) {
                        HStack(spacing: 0) {
                            Text("constellation")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(.white)
                            Text("88")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            goldColor,
                                            Color(red: 1.0, green: 0.647, blue: 0.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                        .shadow(color: .white.opacity(textOpacity * 0.3), radius: 10)

                        Text(".com")
                            .font(.system(size: 25, weight: .light))
                            .foregroundColor(goldColor)
                            .opacity(dotComOpacity)
                            .shadow(color: goldColor.opacity(0.8), radius: 15)
                            .padding(.leading, 175)
                    }
                }
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Trigger the keyframe animation
        animateStar = true

        // Start pulsing after star lands (1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isPulsing = true
            startPulseAnimation()
        }

        // Text illuminate animation (starts at 1.0s, duration 1.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 1.0)) {
                textOpacity = 1.0
                textScale = 1.0
            }
        }

        // .com shine animation (starts at 1.8s, duration 0.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.8)) {
                dotComOpacity = 1.0
            }
        }

        // Complete animation and transition (after 4.5s for more viewing time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            onAnimationComplete()
        }
    }

    private func startPulseAnimation() {
        // intensePulse: 2s ease-in-out infinite
        // glow oscillates between 30px and 50px
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseGlow = 50
        }
    }
}

// Exact 4-pointed star shape from the HTML SVG (viewBox 0 0 384 384)
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Scale factor to fit the 384x384 SVG into the given rect
        let scaleX = rect.width / 384.0
        let scaleY = rect.height / 384.0

        // Helper to scale points
        func s(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        // Converted from SVG path: M370.95,184.73 c... Z
        path.move(to: s(370.95, 184.73))

        path.addCurve(to: s(369.62, 199.37),
                      control1: s(375.07, 188.84),
                      control2: s(374.54, 196.18))

        path.addCurve(to: s(363.18, 201.89),
                      control1: s(367.65, 200.65),
                      control2: s(365.36, 201.14))

        path.addCurve(to: s(310.13, 216.94),
                      control1: s(346.10, 207.78),
                      control2: s(327.32, 211.19))

        path.addCurve(to: s(217.77, 308.27),
                      control1: s(266.05, 231.67),
                      control2: s(232.72, 264.12))

        path.addCurve(to: s(201.01, 366.79),
                      control1: s(211.65, 326.33),
                      control2: s(208.26, 349.90))

        path.addCurve(to: s(183.07, 366.79),
                      control1: s(197.26, 375.53),
                      control2: s(186.83, 375.55))

        path.addCurve(to: s(166.31, 308.27),
                      control1: s(175.82, 349.89),
                      control2: s(172.43, 326.34))

        path.addCurve(to: s(75.36, 217.32),
                      control1: s(151.69, 265.10),
                      control2: s(118.52, 231.94))

        path.addCurve(to: s(16.84, 200.56),
                      control1: s(57.30, 211.20),
                      control2: s(33.73, 207.81))

        path.addCurve(to: s(16.84, 182.62),
                      control1: s(8.10, 196.81),
                      control2: s(8.08, 186.38))

        path.addCurve(to: s(75.36, 165.86),
                      control1: s(33.74, 175.37),
                      control2: s(57.29, 171.98))

        path.addCurve(to: s(166.31, 74.91),
                      control1: s(118.53, 151.24),
                      control2: s(151.69, 118.08))

        path.addCurve(to: s(182.39, 18.41),
                      control1: s(172.31, 57.18),
                      control2: s(175.55, 35.30))

        path.addCurve(to: s(201.44, 17.77),
                      control1: s(186.40, 8.50),
                      control2: s(197.22, 7.83))

        path.addCurve(to: s(217.77, 74.91),
                      control1: s(208.49, 34.36),
                      control2: s(211.78, 57.23))

        path.addCurve(to: s(310.13, 166.24),
                      control1: s(232.72, 119.04),
                      control2: s(266.09, 161.52))

        path.addCurve(to: s(363.87, 181.50),
                      control1: s(327.51, 172.05),
                      control2: s(346.69, 175.43))

        path.addCurve(to: s(370.95, 184.73),
                      control1: s(366.08, 182.28),
                      control2: s(369.28, 183.06))

        path.closeSubpath()

        return path
    }
}

#Preview {
    SplashScreenView(onAnimationComplete: {})
}
