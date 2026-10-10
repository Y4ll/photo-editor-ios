import SwiftUI

/// Cuadrícula de imágenes resultado con selección, guardar en Fotos y compartir ZIP.
/// Si no hay nada seleccionado, las acciones se aplican a todas.
struct ResultsGrid: View {
    let images: [UIImage]
    let baseName: String

    @State private var selected: Set<Int> = []
    @State private var message: String?
    @State private var share: ShareItem?

    private var target: [UIImage] {
        selected.isEmpty ? images : selected.sorted().compactMap { images.indices.contains($0) ? images[$0] : nil }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(images.count) imágenes").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(selected.count == images.count ? "Quitar selección" : "Seleccionar todo") {
                    selected = selected.count == images.count ? [] : Set(images.indices)
                }
                .font(.footnote)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                ForEach(images.indices, id: \.self) { i in
                    Color.clear
                        .frame(height: 90)
                        .overlay(Image(uiImage: images[i]).resizable().scaledToFill())
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(i) ? Color.accentColor : .white.opacity(0.8))
                                .padding(4)
                        }
                        .onTapGesture {
                            if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                        }
                }
            }

            HStack {
                Button {
                    Task {
                        let ok = await PhotoSaver.save(target)
                        message = ok ? "Guardadas \(target.count) imágenes en Fotos." : "No se pudo guardar. Revisa el permiso de Fotos."
                    }
                } label: { Label("Guardar en Fotos", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)

                Button {
                    if let url = ZipWriter.zipImages(target, baseName: baseName) {
                        share = ShareItem(urls: [url])
                    } else {
                        message = "No se pudo crear el ZIP."
                    }
                } label: { Label("ZIP", systemImage: "doc.zipper") }
                .buttonStyle(.bordered)
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }
}
