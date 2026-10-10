import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Dibuja un SVG con WebKit y lo devuelve como imagen.
@MainActor
final class SVGRenderer: NSObject, WKNavigationDelegate {
    private var cont: CheckedContinuation<Void, Never>?

    static func size(of svg: String) -> CGSize? {
        guard let r = svg.range(of: #"viewBox\s*=\s*["']([^"']+)["']"#, options: .regularExpression) else { return nil }
        let nums = String(svg[r])
            .components(separatedBy: CharacterSet(charactersIn: "\"' ,="))
            .compactMap { Double($0) }
        guard nums.count == 4, nums[2] > 0, nums[3] > 0 else { return nil }
        return CGSize(width: nums[2], height: nums[3])
    }

    /// `pixelSize` es el tamaño final en píxeles.
    func render(svgData: Data, pixelSize: CGSize) async -> UIImage? {
        let scale = UIScreen.main.scale
        let pts = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        let web = WKWebView(frame: CGRect(origin: CGPoint(x: -pts.width - 50, y: 0), size: pts))
        web.navigationDelegate = self
        web.isOpaque = true
        web.backgroundColor = .white

        // Algunas versiones de iOS solo pintan WKWebView si está en una ventana.
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.windows.first
        window?.addSubview(web)
        defer { web.removeFromSuperview() }

        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='margin:0;background:#fff'>
        <img src='data:image/svg+xml;base64,\(svgData.base64EncodedString())'
             style='width:100vw;height:100vh;object-fit:contain'>
        </body></html>
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            cont = c
            web.loadHTMLString(html, baseURL: nil)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return try? await web.takeSnapshot(configuration: WKSnapshotConfiguration())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        cont?.resume(); cont = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cont?.resume(); cont = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        cont?.resume(); cont = nil
    }
}

/// Conversión SVG → JPG.
struct SVGConvertView: View {
    @State private var svgData: Data?
    @State private var fileName = "imagen"
    @State private var width: CGFloat = 1024
    @State private var result: UIImage?
    @State private var quality = 0.92
    @State private var showFile = false
    @State private var loading = false
    @State private var message: String?
    @State private var share: ShareItem?
    @State private var renderer = SVGRenderer()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { showFile = true } label: { Label("Elegir archivo SVG", systemImage: "doc") }
                    .buttonStyle(.borderedProminent)

                if svgData != nil {
                    Picker("Ancho", selection: $width) {
                        Text("512").tag(CGFloat(512))
                        Text("1024").tag(CGFloat(1024))
                        Text("2048").tag(CGFloat(2048))
                        Text("4096").tag(CGFloat(4096))
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Calidad JPG").font(.subheadline)
                        Slider(value: $quality, in: 0.5...1)
                        Text(String(format: "%.0f%%", quality * 100)).font(.caption.monospacedDigit())
                    }

                    Button { convert() } label: { Label("Convertir", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.bordered)
                        .disabled(loading)
                }

                if loading { ProgressView() }

                if let result {
                    Image(uiImage: result).resizable().scaledToFit()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("\(Int(result.size.width * result.scale)) × \(Int(result.size.height * result.scale)) px")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { export(save: true) } label: { Label("Guardar en Fotos", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent)
                        Button { export(save: false) } label: { Label("Compartir", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Conversión SVG - JPG")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.svg]) { res in
            guard case .success(let url) = res, let d = readFile(url) else { return }
            svgData = d
            fileName = url.deletingPathExtension().lastPathComponent
            result = nil
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    private func convert() {
        guard let data = svgData else { return }
        let text = String(data: data, encoding: .utf8) ?? ""
        let ratio = SVGRenderer.size(of: text).map { $0.height / $0.width } ?? 1
        let size = CGSize(width: width, height: (width * ratio).rounded())
        loading = true
        Task {
            result = await renderer.render(svgData: data, pixelSize: size)
            loading = false
            if result == nil { message = "No se pudo convertir ese SVG." }
        }
    }

    private func export(save: Bool) {
        guard let result, let jpg = result.flattenedOnWhite().jpegData(compressionQuality: quality) else { return }
        let url = tempURL("jpg", name: fileName)
        do { try jpg.write(to: url) } catch { message = "No se pudo crear el JPG."; return }
        if save {
            Task {
                let ok = await PhotoSaver.saveFiles([url])
                message = ok ? "JPG guardado en Fotos." : "No se pudo guardar. Revisa el permiso de Fotos."
            }
        } else {
            share = ShareItem(urls: [url])
        }
    }
}
