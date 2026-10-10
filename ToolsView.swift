import SwiftUI

struct ToolsView: View {
    var body: some View {
        List {
            Section("Imágenes") {
                link("Cortar (Composición)", "squareshape.split.2x2") { CutCompositionView() }
                link("Comparar Imágenes", "rectangle.split.2x1") { CompareView() }
                link("Conversión SVG - JPG", "arrow.triangle.2.circlepath") { SVGConvertView() }
            }
            Section("GIF") {
                link("GIF Animado", "play.square") { GIFStudioView() }
                link("Extractor de Marcos GIF", "square.stack.3d.down.right") { GIFExtractorView() }
            }
            Section("Archivos") {
                link("Comprimir en ZIP", "doc.zipper") { ZipToolView() }
                link("Crear PDF", "doc.richtext") { PDFCreateView() }
            }
            Section("Capturas") {
                link("Captura de Páginas Web", "globe") { WebCaptureView() }
                link("Captura de Video", "film") { VideoCaptureView() }
                link("Captura de PDF's", "doc.viewfinder") { PDFCaptureView() }
            }
        }
        .navigationTitle("Herramientas")
    }

    private func link<D: View>(_ title: String, _ icon: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: { Label(title, systemImage: icon) }
    }
}
