import SwiftUI
import PDFKit

enum PDFRender {
    /// Dibuja una página como imagen. `scale` 1 = tamaño en puntos del PDF.
    static func image(page: PDFPage, scale: CGFloat, maxPixels: CGFloat = 8000) -> UIImage {
        let b = page.bounds(for: .mediaBox)
        var w = b.width, h = b.height
        if page.rotation % 180 != 0 { swap(&w, &h) }
        let s = min(scale, maxPixels / max(w, h))
        let size = CGSize(width: w * s, height: h * s)
        return page.thumbnail(of: size, for: .mediaBox).atScale1().flattenedOnWhite()
    }
}

/// Captura de PDF's: convierte cada página de un PDF en imagen.
struct PDFCaptureView: View {
    @State private var images: [UIImage] = []
    @State private var scale: CGFloat = 2
    @State private var pdfData: Data?
    @State private var showFile = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { showFile = true } label: { Label("Elegir PDF", systemImage: "doc") }
                    .buttonStyle(.borderedProminent)

                if pdfData != nil {
                    Picker("Calidad", selection: $scale) {
                        Text("Normal").tag(CGFloat(1))
                        Text("Alta").tag(CGFloat(2))
                        Text("Máxima").tag(CGFloat(3))
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: scale) { _ in render() }
                }

                if loading { ProgressView("Convirtiendo páginas…") }
                if !images.isEmpty { ResultsGrid(images: images, baseName: "pagina") }
            }
            .padding()
        }
        .navigationTitle("Captura de PDF's")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result, let d = readFile(url) {
                pdfData = d
                render()
            }
        }
        .messageAlert($message)
    }

    private func render() {
        guard let data = pdfData, let doc = PDFDocument(data: data) else {
            message = "No se pudo abrir ese PDF."
            return
        }
        loading = true
        images = []
        Task {
            var out: [UIImage] = []
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i) { out.append(PDFRender.image(page: p, scale: scale)) }
                await Task.yield()
            }
            images = out
            loading = false
        }
    }
}
