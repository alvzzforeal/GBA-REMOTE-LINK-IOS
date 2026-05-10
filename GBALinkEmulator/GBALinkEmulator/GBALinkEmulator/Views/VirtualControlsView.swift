import SwiftUI

// MARK: - Virtual Controls View
// Fully responsive: adapts to iPhone mini (360pt) through Pro Max (430pt+).
// All sizes derived from the actual screen geometry — no fixed constants.

struct VirtualControlsView: View {
    @Binding var inputState: GBAInputState
    let screenSize: CGSize
    var onInputChanged: ((GBAInputState) -> Void)?

    // MARK: - Layout metrics (all derived from screen width)

    /// Normalised scale: 1.0 = iPhone 15 (390pt wide)
    private var scale: CGFloat {
        let s = (screenSize.width / 390.0).clamped(to: 0.82...1.20)
        return s
    }

    /// Height of the entire controls panel
    private var panelHeight: CGFloat {
        // Base 200pt at scale 1.0; capped at 44% of screen height
        let base = 200.0 * scale
        return base.clamped(to: 172...screenSize.height * 0.44)
    }

    private var dpadSize: CGFloat  { (134 * scale).clamped(to: 110...160) }
    private var abSize: CGFloat    { (122 * scale).clamped(to: 100...148) }
    private var sideInset: CGFloat { (16 * scale).clamped(to: 12...24) }

    var body: some View {
        ZStack {
            // Panel background
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.08, blue: 0.15),
                            Color(red: 0.06, green: 0.05, blue: 0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.white.opacity(0.07)),
                    alignment: .top
                )

            VStack(spacing: 0) {
                // ── Row 1: Shoulder buttons + Start/Select ──────────────────
                HStack(alignment: .center) {
                    ShoulderButton(label: "L", scale: scale, isPressed: inputState.l) {
                        inputState.l = $0; notify()
                    }
                    .padding(.leading, sideInset)

                    Spacer()

                    HStack(spacing: (14 * scale).clamped(to: 10...20)) {
                        SmallButton(label: "SELECT", scale: scale, isPressed: inputState.select) {
                            inputState.select = $0; notify()
                        }
                        SmallButton(label: "START", scale: scale, isPressed: inputState.start) {
                            inputState.start = $0; notify()
                        }
                    }

                    Spacer()

                    ShoulderButton(label: "R", scale: scale, isPressed: inputState.r) {
                        inputState.r = $0; notify()
                    }
                    .padding(.trailing, sideInset)
                }
                .padding(.top, (10 * scale).clamped(to: 8...16))

                Spacer()

                // ── Row 2: D-Pad + AB ────────────────────────────────────
                HStack(alignment: .center) {
                    DPadView(inputState: $inputState, onChanged: notify, size: dpadSize)
                        .padding(.leading, sideInset)

                    Spacer()

                    ABButtonsView(inputState: $inputState, onChanged: notify, containerSize: abSize)
                        .padding(.trailing, sideInset)
                }
                .padding(.bottom, (14 * scale).clamped(to: 10...22))
            }
        }
        .frame(height: panelHeight)
    }

    private func notify() { onInputChanged?(inputState) }
}

// MARK: - D-Pad

struct DPadView: View {
    @Binding var inputState: GBAInputState
    var onChanged: (() -> Void)?
    let size: CGFloat

    private var armW: CGFloat { size * 0.34 }
    private var armH: CGFloat { size * 0.34 }

    var body: some View {
        ZStack {
            // Horizontal arm
            RoundedRectangle(cornerRadius: armW * 0.28)
                .fill(dpadFill)
                .frame(width: size, height: armH)

            // Vertical arm
            RoundedRectangle(cornerRadius: armW * 0.28)
                .fill(dpadFill)
                .frame(width: armW, height: size)

            // Centre disc
            Circle()
                .fill(Color(white: 0.22))
                .frame(width: armW * 0.88, height: armW * 0.88)

            // Hit zones
            dirButton("arrow.up",    offset: CGPoint(x: 0, y: -(size * 0.33))) { inputState.up = $0; onChanged?() }
            dirButton("arrow.down",  offset: CGPoint(x: 0, y:  (size * 0.33))) { inputState.down = $0; onChanged?() }
            dirButton("arrow.left",  offset: CGPoint(x: -(size * 0.33), y: 0)) { inputState.left = $0; onChanged?() }
            dirButton("arrow.right", offset: CGPoint(x:  (size * 0.33), y: 0)) { inputState.right = $0; onChanged?() }
        }
        .frame(width: size, height: size)
    }

    private var dpadFill: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.26), Color(white: 0.16)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func dirButton(
        _ icon: String,
        offset: CGPoint,
        action: @escaping (Bool) -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: armW * 0.36, weight: .semibold))
            .foregroundColor(.white.opacity(0.70))
            .frame(width: armW, height: armH)
            .contentShape(Rectangle())
            .offset(x: offset.x, y: offset.y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in action(true) }
                    .onEnded   { _ in action(false) }
            )
    }
}

// MARK: - A / B Buttons

struct ABButtonsView: View {
    @Binding var inputState: GBAInputState
    var onChanged: (() -> Void)?
    let containerSize: CGFloat

    private var btnSize: CGFloat { containerSize * 0.44 }
    private var offset: CGFloat  { containerSize * 0.24 }

    var body: some View {
        ZStack {
            ActionButton(label: "B", color: .red, size: btnSize, isPressed: inputState.b) {
                inputState.b = $0; onChanged?()
            }
            .offset(x: -offset, y: offset * 0.70)

            ActionButton(label: "A", color: Color(red: 0.10, green: 0.85, blue: 0.30), size: btnSize, isPressed: inputState.a) {
                inputState.a = $0; onChanged?()
            }
            .offset(x: offset, y: -offset * 0.30)
        }
        .frame(width: containerSize, height: containerSize)
    }
}

// MARK: - Action Button (A / B)

struct ActionButton: View {
    let label: String
    let color: Color
    let size: CGFloat
    let isPressed: Bool
    let action: (Bool) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size + 10, height: size + 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(isPressed ? 1.0 : 0.85),
                            color.opacity(isPressed ? 0.70 : 0.55)
                        ],
                        center: .init(x: 0.4, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: color.opacity(isPressed ? 0.25 : 0.55),
                    radius: isPressed ? 3 : 10,
                    x: 0,
                    y: isPressed ? 1 : 4
                )

            Text(label)
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
        }
        .scaleEffect(isPressed ? 0.91 : 1.0)
        .animation(.easeInOut(duration: 0.07), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
    }
}

// MARK: - Shoulder Button (L / R)

struct ShoulderButton: View {
    let label: String
    let scale: CGFloat
    let isPressed: Bool
    let action: (Bool) -> Void

    private var w: CGFloat { (64 * scale).clamped(to: 52...80) }
    private var h: CGFloat { (28 * scale).clamped(to: 24...36) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: (8 * scale).clamped(to: 6...12))
                .fill(
                    LinearGradient(
                        colors: isPressed
                            ? [Color(white: 0.38), Color(white: 0.30)]
                            : [Color(white: 0.28), Color(white: 0.20)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: (8 * scale).clamped(to: 6...12))
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.40), radius: 4, x: 0, y: 2)

            Text(label)
                .font(.system(size: (15 * scale).clamped(to: 12...20), weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.easeInOut(duration: 0.07), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
    }
}

// MARK: - Small Button (Start / Select)

struct SmallButton: View {
    let label: String
    let scale: CGFloat
    let isPressed: Bool
    let action: (Bool) -> Void

    private var w: CGFloat { (68 * scale).clamped(to: 56...86) }
    private var h: CGFloat { (22 * scale).clamped(to: 18...28) }

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: isPressed
                            ? [Color(white: 0.38), Color(white: 0.30)]
                            : [Color(white: 0.26), Color(white: 0.18)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: w, height: h)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))

            Text(label)
                .font(.system(size: (9.5 * scale).clamped(to: 8...13), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .kerning(0.4)
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.easeInOut(duration: 0.07), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
    }
}

// MARK: - Comparable clamped helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
