import SwiftUI
import PhotosUI

/// Tareas por Lotes: redimensionar, convertir, comprimir y aplicar filtro a muchas imágenes.
struct BatchView: View {
    enum OutFormat: String, CaseIterable, Identifiable {
        case jpg = "JPG", png = "PNG"
        var id: String { rawValue }
        var ext: String { rawValue.lowercased() }
    }

    @State private var picked: [PHPickerResult] = []
    @State private var maxSide: CGFloat = 0
    @State private var format: OutFormat = .jpg
    @State private var quality = 0.85
    @State private var filter: PhotoFilter = .none
    @State private var prefix = "imagen"

    @State private var showPicker = false
    @State private var busy = false
    @State private var progress = 0
    @State private var outputs: [URL] = []
    @State private var message: String?
    @State private var share: ShareItem?

    var body: some View {
        Form {
            Section {
                Button { showPicker = true } label: {
                    Label(picked.isEmpty ? "Elegir imágenes" : "\(picked.count) imágenes elegidas", systemImage: "photo.stack")
                }
            }

            Section("Tamaño") {
                Picker("Lado más largo", selection: $maxSide) {
                    Text("Original").tag(CGFloat(0))
                    Text("512 px").tag(CGFloat(512))
                    Text("1024 px").tag(CGFloat(1024))
                    Text("2048 px").tag(CGFloat(2048))
                }
            }

            Section("Formato") {
                Picker("Formato", selection: $format) {
                    ForEach(OutFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if format == .jpg {
                    HStack {
                        Text("Calidad")
                        Slider(value: $quality, in: 0.3...1)
                        Text(String(format: "%.0f%%", quality * 100)).font(.caption.monospacedDigit())
                    }
                }
            }

            Section("Filtro") {
                Picker("Filtro", selection: $filter) {
                    ForEach(PhotoFilter.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Nombre") {
                TextField("Prefijo", text: $prefix)
            }

            Section {
                Button { run() } label: { Label("Procesar", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty || busy)
                if busy { ProgressView(value: Double(progress), total: Double(max(picked.count, 1))) }
            }

            if !outputs.isEmpty {
                Section("Resultado: \(outputs.count) archivos") {
                    Button {
                        Task {
                            let ok = await PhotoSaver.saveFiles(outputs)
                            message = ok ? "Guardadas en Fotos." : "No se pudo guardar. Revisa el permiso de Fotos."
                        }
                    } label: { Label("Guardar en Fotos", systemImage: "square.and.arrow.down") }

                    Button { zip() } label: { Label("Compartir como ZIP", systemImage: "doc.zipper") }
                    Button { share = ShareItem(urls: outputs) } label: { Label("Compartir archivos", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Tareas por Lotes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(filter: .images, limit: 0) { results in
                showPicker = false
                picked = results
                outputs = []
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    private func run() {
        busy = true
        progress = 0
        outputs = []
        let (side, fmt, q, flt) = (maxSide, format, quality, filter)
        let name = prefix.trimmingCharacters(in: .whitespaces).isEmpty ? "imagen" : prefix
        Task {
            var urls: [URL] = []
            for (i, r) in picked.enumerated() {
                if let img = await r.loadUIImage() {
                    let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                        var out = img.resized(maxSide: side)
                        if flt != .none {
                            var s = EditState()
                            s.filter = flt
                            out = EditRenderer.render(out, s)
                        }
                        return fmt == .jpg
                            ? out.flattenedOnWhite().jpegData(compressionQuality: q)
                            : out.pngData()
                    }.value
                    if let data {
                        let url = tempURL(fmt.ext, name: "\(name)_\(String(format: "%03d", i + 1))")
                        if (try? data.write(to: url)) != nil { urls.append(url) }
                    }
                }
                progress = i + 1
            }
            outputs = urls
            busy = false
            if urls.isEmpty { message = "No se pudo procesar ninguna imagen." }
        }
    }

    private func zip() {
        let files = outputs.compactMap { u -> (name: String, data: Data)? in
            guard let d = try? Data(contentsOf: u) else { return nil }
            return (u.lastPathComponent, d)
        }
        if let url = ZipWriter.zipFile(files, name: "lote") { share = ShareItem(urls: [url]) }
        else { message = "No se pudo crear el ZIP." }
    }
}
