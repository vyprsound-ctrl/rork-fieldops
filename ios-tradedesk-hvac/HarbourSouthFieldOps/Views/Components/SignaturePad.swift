import SwiftUI

/// Captures a customer signature as strokes and renders them to a PNG.
///
/// The strokes are held as points rather than as a bitmap while the finger is
/// down, so the line stays crisp at any size and the export is a small, clean
/// image — a signature is a few kilobytes, not a photograph.
struct SignaturePad: View {
    @Binding var image: Data?
    var height: CGFloat = 190

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    private var isEmpty: Bool { strokes.isEmpty && current.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isEmpty ? Theme.border : Theme.primary.opacity(0.4), lineWidth: 1)

                if isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "signature")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.meta)
                        Text("Ask the customer to sign here")
                            .font(.footnote)
                            .foregroundStyle(Theme.meta)
                    }
                    .allowsHitTesting(false)
                }

                Canvas { context, _ in
                    for stroke in strokes + [current] {
                        guard stroke.count > 1 else { continue }
                        var path = Path()
                        path.move(to: stroke[0])
                        for point in stroke.dropFirst() { path.addLine(to: point) }
                        context.stroke(
                            path,
                            with: .color(Theme.ink),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                        )
                    }
                }

                // The baseline the customer signs on, so the pad reads as a
                // signature box rather than a drawing area.
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 34)
                }
                .allowsHitTesting(false)
            }
            .frame(height: height)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in current.append(value.location) }
                    .onEnded { _ in
                        if current.count > 1 { strokes.append(current) }
                        current = []
                        render()
                    }
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { canvasSize = proxy.size }
                }
            }

            HStack {
                Text(isEmpty ? "Not signed" : "Signed")
                    .font(.caption)
                    .foregroundStyle(isEmpty ? Theme.meta : Theme.green)
                Spacer()
                Button("Clear") {
                    strokes = []
                    current = []
                    image = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.red)
                .disabled(isEmpty)
                .opacity(isEmpty ? 0.4 : 1)
            }
        }
    }

    /// Renders the strokes to a compact PNG on a white background.
    @MainActor
    private func render() {
        guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
            image = nil
            return
        }

        let size = canvasSize
        let capturedStrokes = strokes
        let renderer = ImageRenderer(
            content: ZStack {
                Color.white
                Canvas { context, _ in
                    for stroke in capturedStrokes {
                        guard stroke.count > 1 else { continue }
                        var path = Path()
                        path.move(to: stroke[0])
                        for point in stroke.dropFirst() { path.addLine(to: point) }
                        context.stroke(
                            path,
                            with: .color(.black),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        )
        // 1× keeps the file to a few kilobytes; a signature needs legibility,
        // not resolution.
        renderer.scale = 1
        image = renderer.uiImage?.pngData()
    }
}

#Preview {
    struct Harness: View {
        @State private var data: Data?
        var body: some View {
            SignaturePad(image: $data)
                .padding()
                .background(Theme.canvas)
        }
    }
    return Harness()
}
