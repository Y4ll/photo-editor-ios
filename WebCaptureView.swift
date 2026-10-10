import SwiftUI
import WebKit
import PDFKit

final class WebHolder: ObservableObject {
    let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
}

struct WebViewRep: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Captura de Páginas Web: navega y guarda la página completa o lo visible.
struct WebCaptureView: View {
    @StateObject private var holder = WebHolder()
    @State private var address = "https://www.apple.com"
    @State private var captured: ImageBox?
    @State private var busy = false
    @State private var message: String?
    @State private var share: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Dirección web", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(go)
                Button("Ir", action: go).buttonStyle(.borderedProminent)
            }
            .padding(8)

            WebViewRep(web: holder.web)

            HStack {
                Button { captureFull() } label: { Label("Página completa", systemImage: "arrow.up.and.down.text.horizontal") }
                    .buttonStyle(.borderedProminent)
                Button { captureVisible() } label: { Label("Vista actual", systemImage: "rectangle.dashed") }
                    .buttonStyle(.bordered)
                Button { exportPDF() } label: { Label("PDF", systemImage: "doc") }
                    .buttonStyle(.bordered)
            }
            .disabled(busy)
            .padding(8)
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .navigationTitle("Captura de Páginas Web")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if holder.web.url == nil { go() } }
        .sheet(item: $captured) { box in CaptureResultSheet(image: box.image) }
        .messageAlert($message)
        .shareSheet($share)
    }

    private func go() {
        var s = address.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        address = s
        holder.web.load(URLRequest(url: url))
    }

    private func captureVisible() {
        busy = true
        Task {
            let img = try? await holder.web.takeSnapshot(configuration: WKSnapshotConfiguration())
            busy = false
            if let img { captured = ImageBox(image: img) } else { message = "No se pudo capturar la página." }
        }
    }

    private func pageSize() -> CGSize {
        let c = holder.web.scrollView.contentSize
        return CGSize(width: max(c.width, 1), height: max(c.height, 1))
    }

    private func captureFull() {
        busy = true
        Task {
            defer { busy = false }
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(origin: .zero, size: pageSize())
            guard let data = try? await holder.web.pdf(configuration: cfg),
                  let page = PDFDocument(data: data)?.page(at: 0) else {
                message = "No se pudo capturar la página."
                return
            }
            captured = ImageBox(image: PDFRender.image(page: page, scale: 2, maxPixels: 16000))
        }
    }

    private func exportPDF() {
        busy = true
        Task {
            defer { busy = false }
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(origin: .zero, size: pageSize())
            guard let data = try? await holder.web.pdf(configuration: cfg) else {
                message = "No se pudo crear el PDF."
                return
            }
            let url = tempURL("pdf", name: "pagina_web")
            try? data.write(to: url)
            share = ShareItem(urls: [url])
        }
    }
}

/// Hoja con la imagen capturada y botones de guardar/compartir.
struct CaptureResultSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image).resizable().scaledToFit().padding()
            }
            .navigationTitle("Captura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { save() } label: { Image(systemName: "square.and.arrow.down") }
                    Button { exportShare() } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    private func jpgFile() -> URL? {
        guard let d = image.flattenedOnWhite().jpegData(compressionQuality: 0.92) else { return nil }
        let url = tempURL("jpg", name: "captura")
        return (try? d.write(to: url)) != nil ? url : nil
    }

    private func save() {
        guard let url = jpgFile() else { return }
        Task {
            let ok = await PhotoSaver.saveFiles([url])
            message = ok ? "Captura guardada en Fotos." : "No se pudo guardar. Revisa el permiso de Fotos."
        }
    }

    private func exportShare() {
        if let url = jpgFile() { share = ShareItem(urls: [url]) }
    }
}
