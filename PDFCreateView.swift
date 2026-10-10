import SwiftUI
import PhotosUI

/// Crear PDF a partir de imágenes, con orden editable.
struct PDFCreateView: View {
    enum PageSize: String, CaseIterable, Identifiable {
        case fit = "Tamaño de la imagen", a4 = "A4"
        var id: String { rawValue }
    }

    @State private var images: [UIImage] = []
    @State private var pageSize: PageSize = .fit
    @State private var showPicker = false
    @State private var message: String?
    @State private var share: ShareItem?

    var body: some View {
        List {
            Section {
                Button { showPicker = true } label: { Label("Añadir imágenes", systemImage: "photo.badge.plus") }
            }

            if !images.isEmpty {
                Section("Páginas (arrastra para reordenar)") {
                    ForEach(images.indices, id: \.self) { i in
                        HStack {
                            Image(uiImage: images[i]).resizable().scaledToFill()
                                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("Página \(i + 1)")
                        }
                    }
                    .onMove { images.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { images.remove(atOffsets: $0) }
                }

                Section("Tamaño de página") {
                    Picker("Tamaño", selection: $pageSize) {
                        ForEach(PageSize.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button { create() } label: { Label("Crear y compartir PDF", systemImage: "doc.richtext") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Crear PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !images.isEmpty { EditButton() } }
        .sheet(isPresented: $showPicker) {
            PhotoPicker(filter: .images, limit: 0) { results in
                showPicker = false
                Task {
                    for r in results {
                        if let img = await r.loadUIImage() { images.append(img) }
                    }
                }
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    private func create() {
        guard !images.isEmpty else { return }
        let a4 = CGSize(width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: a4))
        let data = renderer.pdfData { ctx in
            for img in images {
                switch pageSize {
                case .a4:
                    ctx.beginPage(withBounds: CGRect(origin: .zero, size: a4), pageInfo: [:])
                    let r = min(a4.width / img.size.width, a4.height / img.size.height)
                    let w = img.size.width * r, h = img.size.height * r
                    img.draw(in: CGRect(x: (a4.width - w) / 2, y: (a4.height - h) / 2, width: w, height: h))
                case .fit:
                    let r = min(1, 842 / max(img.size.width, img.size.height))
                    let size = CGSize(width: img.size.width * r, height: img.size.height * r)
                    ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                    img.draw(in: CGRect(origin: .zero, size: size))
                }
            }
        }
        let url = tempURL("pdf", name: "documento")
        do {
            try data.write(to: url)
            share = ShareItem(urls: [url])
        } catch {
            message = "No se pudo crear el PDF."
        }
    }
}
