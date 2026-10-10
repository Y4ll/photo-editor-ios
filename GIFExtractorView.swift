import SwiftUI
import UniformTypeIdentifiers

/// Extractor de Marcos GIF: separa un GIF en sus cuadros.
struct GIFExtractorView: View {
    @State private var frames: [GIFFrame] = []
    @State private var showPicker = false
    @State private var showFile = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { showPicker = true } label: { Label("Desde Fotos", systemImage: "photo") }
                        .buttonStyle(.borderedProminent)
                    Button { showFile = true } label: { Label("Desde Archivos", systemImage: "folder") }
                        .buttonStyle(.bordered)
                }
                if loading { ProgressView() }
                if !frames.isEmpty {
                    Text("\(frames.count) cuadros · \(String(format: "%.2f", frames.reduce(0) { $0 + $1.delay })) s")
                        .font(.caption).foregroundStyle(.secondary)
                    ResultsGrid(images: frames.map(\.image), baseName: "cuadro")
                }
            }
            .padding()
        }
        .navigationTitle("Extractor de Marcos GIF")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(filter: .images, limit: 1) { results in
                showPicker = false
                guard let r = results.first else { return }
                loading = true
                Task {
                    if let d = await r.loadData(type: .gif) { load(d) } else { message = "Ese archivo no es un GIF." }
                    loading = false
                }
            }
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.gif]) { result in
            if case .success(let url) = result, let d = readFile(url) { load(d) }
        }
        .messageAlert($message)
    }

    private func load(_ data: Data) {
        frames = GIFTools.decode(data)
        if frames.isEmpty { message = "No se pudo leer ese GIF." }
    }
}
