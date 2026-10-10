import SwiftUI

/// Comparar Imágenes: dos imágenes con divisor deslizable.
struct CompareView: View {
    enum Slot: String, Identifiable {
        case a, b
        var id: String { rawValue }
    }

    @State private var a: UIImage?
    @State private var b: UIImage?
    @State private var pos: CGFloat = 0.5
    @State private var picking: Slot?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { picking = .a } label: { Label(a == nil ? "Imagen A" : "Cambiar A", systemImage: "a.square") }
                    .buttonStyle(.borderedProminent)
                Button { picking = .b } label: { Label(b == nil ? "Imagen B" : "Cambiar B", systemImage: "b.square") }
                    .buttonStyle(.borderedProminent)
            }

            if let a, let b {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Image(uiImage: a).resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                        Image(uiImage: b).resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * pos)
                            }

                        Rectangle().fill(.white).frame(width: 2)
                            .offset(x: geo.size.width * pos - 1)
                        Circle().fill(.white).frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.and.right").foregroundStyle(.black))
                            .offset(x: geo.size.width * pos - 17)

                        VStack {
                            HStack {
                                badge("B"); Spacer(); badge("A")
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged {
                        pos = min(max($0.location.x / geo.size.width, 0), 1)
                    })
                }
            } else {
                Spacer()
                Text("Elige dos imágenes para compararlas.\nArrastra el divisor para ver las diferencias.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Comparar Imágenes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picking) { slot in
            PhotoPicker(filter: .images, limit: 1) { results in
                picking = nil
                guard let r = results.first else { return }
                Task {
                    guard let img = await r.loadUIImage() else { return }
                    if slot == .a { a = img } else { b = img }
                }
            }
        }
    }

    private func badge(_ t: String) -> some View {
        Text(t).font(.caption.bold()).padding(6)
            .background(.black.opacity(0.6)).foregroundStyle(.white).clipShape(Circle())
    }
}
