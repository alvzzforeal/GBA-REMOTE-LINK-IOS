import SwiftUI

// MARK: - Virtual Controls View

struct VirtualControlsView: View {
    @Binding var inputState: GBAInputState
    var onInputChanged: ((GBAInputState) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // ── Left side: D-Pad ──
            DPadView(inputState: $inputState, onChanged: notify)
                .frame(width: 130, height: 130)
                .padding(.leading, 16)
                .padding(.bottom, 8)

            Spacer()

            // ── Center bottom: L / R shoulder buttons ──
            VStack(spacing: 0) {
                HStack(spacing: 120) {
                    ShoulderButton(label: "L", isPressed: inputState.l) {
                        inputState.l = $0; notify()
                    }
                    ShoulderButton(label: "R", isPressed: inputState.r) {
                        inputState.r = $0; notify()
                    }
                }
                .padding(.bottom, 4)

                // ── Start / Select ──
                HStack(spacing: 20) {
                    SmallButton(label: "SELECT", isPressed: inputState.select) {
                        inputState.select = $0; notify()
                    }
                    SmallButton(label: "START", isPressed: inputState.start) {
                        inputState.start = $0; notify()
                    }
                }
            }
            .padding(.bottom, 8)

            Spacer()

            // ── Right side: A / B ──
            ABButtonsView(inputState: $inputState, onChanged: notify)
                .frame(width: 110, height: 110)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
        }
        .frame(height: 160)
        .background(Color.black.opacity(0.5))
    }

    private func notify() {
        onInputChanged?(inputState)
    }
}

// MARK: - D-Pad

struct DPadView: View {
    @Binding var inputState: GBAInputState
    var onChanged: (() -> Void)?

    private let size: CGFloat = 42

    var body: some View {
        ZStack {
            // Horizontal bar
            Capsule()
                .fill(dpadColor)
                .frame(width: size * 3, height: size)

            // Vertical bar
            Capsule()
                .fill(dpadColor)
                .frame(width: size, height: size * 3)

            // Arrow labels
            VStack(spacing: 0) {
                arrowButton("▲") { inputState.up = $0; onChanged?() }
                    .frame(width: size, height: size)
                Spacer().frame(height: size)
                arrowButton("▼") { inputState.down = $0; onChanged?() }
                    .frame(width: size, height: size)
            }
            .frame(height: size * 3)

            HStack(spacing: 0) {
                arrowButton("◀") { inputState.left = $0; onChanged?() }
                    .frame(width: size, height: size)
                Spacer().frame(width: size)
                arrowButton("▶") { inputState.right = $0; onChanged?() }
                    .frame(width: size, height: size)
            }
            .frame(width: size * 3)

            // Center dot
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 18, height: 18)
        }
    }

    private var dpadColor: Color { Color(white: 0.18) }

    private func arrowButton(_ label: String, action: @escaping (Bool) -> Void) -> some View {
        Text(label)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white.opacity(0.8))
            .contentShape(Rectangle())
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

    var body: some View {
        ZStack {
            // B (left)
            ActionButton(label: "B", color: .red, isPressed: inputState.b) {
                inputState.b = $0; onChanged?()
            }
            .offset(x: -36, y: 20)

            // A (right)
            ActionButton(label: "A", color: .green, isPressed: inputState.a) {
                inputState.a = $0; onChanged?()
            }
            .offset(x: 20, y: -10)
        }
    }
}

// MARK: - Action Button (A / B)

struct ActionButton: View {
    let label: String
    let color: Color
    let isPressed: Bool
    let action: (Bool) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? color : color.opacity(0.7))
                .frame(width: 46, height: 46)
                .shadow(color: color.opacity(0.5), radius: isPressed ? 2 : 6)

            Text(label)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }
}

// MARK: - Shoulder Button (L / R)

struct ShoulderButton: View {
    let label: String
    let isPressed: Bool
    let action: (Bool) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isPressed ? Color.gray : Color(white: 0.25))
                .frame(width: 52, height: 26)

            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }
}

// MARK: - Small Button (Start / Select)

struct SmallButton: View {
    let label: String
    let isPressed: Bool
    let action: (Bool) -> Void

    var body: some View {
        ZStack {
            Capsule()
                .fill(isPressed ? Color.gray : Color(white: 0.25))
                .frame(width: 62, height: 20)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded   { _ in action(false) }
        )
    }
}
