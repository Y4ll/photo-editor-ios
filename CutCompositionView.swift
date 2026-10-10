import SwiftUI

/// Cortar (Composición): divide una imagen en una cuadrícula de partes.
struct CutCompositionView: View {
    @State private var image: UIImage?
    @State private var cols = 3
    @State private var rows = 1
    @State private var tiles: [UIImage] = []
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { showPicker = true } label: { Label("Elegir imagen", systemImage: "photo") }
                    .buttonStyle(.borderedProminent)

                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .overlay { gridLines }

                    Stepper("Columnas: \(cols)", value: $cols, in: 1...10)
                    Stepper("Filas: \(rows)", value: $rows, in: 1...10)

                    HStack {
                        preset("3×1", 3, 1); preset("3×3", 3, 3); preset("2×2", 2, 2); preset("1×3", 1, 3)
                    }

                    Button { tiles = cut(image) } label: {
                        Label("Cortar en \(cols * rows) partes", systemImage: "scissors")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !tiles.isEmpty { ResultsGrid(images: tiles, baseName: "parte") }
            }
            .padding()
        }
        .navigationTitle("Cortar (Composición)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: cols) { _ in tiles = [] }
        .onChange(of: rows) { _ in tiles = [] }
        .sheet(isPresented: $showPicker) {
            PhotoPicker(filter: .images, limit: 1) { results in
                showPicker = false
                guard let r = results.first else { return }
                Task {
                    if let img = await r.loadUIImage() { image = img; tiles = [] }
                }
            }
        }
    }

    private var gridLines: some View {
        GeometryReader { geo in
            Path { p in
                for c in 1..<max(cols, 1) {
                    let x = geo.size.width * CGFloat(c) / CGFloat(cols)
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for r in 1..<max(rows, 1) {
                    let y = geo.size.height * CGFloat(r) / CGFloat(rows)
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .shadow(color: .black, radius: 1)
        }
    }

    private func preset(_ t: String, _ c: Int, _ r: Int) -> some View {
        Button(t) { cols = c; rows = r }.buttonStyle(.bordered)
    }

    private func cut(_ img: UIImage) -> [UIImage] {
        guard let cg = img.normalized().cgImage else { return [] }
        let w = cg.width / cols, h = cg.height / rows
        var out: [UIImage] = []
        for r in 0..<rows {
            for c in 0..<cols {
                if let t = cg.cropping(to: CGRect(x: c * w, y: r * h, width: w, height: h)) {
                    out.append(UIImage(cgImage: t))
                }
            }
        }
        return out
    }
}
