import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// GIF Animado: crear desde fotos o video, o editar un GIF existente.
struct GIFStudioView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case photos = "Fotos", video = "Video", gif = "Editar GIF"
        var id: String { rawValue }
    }

    struct Params: Equatable {
        var speed = 1.0
        var reversed = false
        var pingpong = false
        var maxSide: CGFloat = 480
        var caption = ""
        var version = 0
    }

    @State private var mode: Mode = .photos
    @State private var source: [GIFFrame] = []
    @State private var output: [GIFFrame] = []
    @State private var params = Params()

    @State private var showPicker = false
    @State private var showGIFFile = false
    @State private var loading = false
    @State private var message: String?
    @State private var share: ShareItem?

    // Video
    @State private var videoURL: URL?
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 3.0
    @State private var fps = 10.0

    private var maxFrames: Int { 150 }
    private var plannedFrames: Int { Int(max(0, end - start) * fps) + 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Origen", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                loadSection

                if loading { ProgressView("Procesando…") }

                if !output.isEmpty {
                    AnimatedImageView(frames: output)
                        .frame(height: 260)
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("\(output.count) cuadros · \(String(format: "%.1f", output.reduce(0) { $0 + $1.delay })) s")
                        .font(.caption).foregroundStyle(.secondary)

                    frameStrip
                    controls
                    actions
                }
            }
            .padding()
        }
        .navigationTitle("GIF Animado")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { picker }
        .fileImporter(isPresented: $showGIFFile, allowedContentTypes: [.gif]) { result in
            if case .success(let url) = result, let d = readFile(url) { loadGIF(data: d) }
        }
        .task(id: params) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let src = source, p = params
            let result = await Task.detached(priority: .userInitiated) {
                GIFTools.process(src, speed: p.speed, reversed: p.reversed, pingpong: p.pingpong,
                                 maxSide: p.maxSide, caption: p.caption)
            }.value
            if !Task.isCancelled { output = result }
        }
        .messageAlert($message)
        .shareSheet($share)
        .onChange(of: mode) { _ in
            source = []; output = []; videoURL = nil
            params.version += 1
        }
    }

    // MARK: Carga

    @ViewBuilder private var loadSection: some View {
        switch mode {
        case .photos:
            Button { showPicker = true } label: {
                Label("Elegir fotos (hasta 30)", systemImage: "photo.stack")
            }
            .buttonStyle(.borderedProminent)
            Text("Cada foto será un cuadro. Se ajustan al tamaño de la primera.")
                .font(.caption).foregroundStyle(.secondary)

        case .video:
            Button { showPicker = true } label: { Label("Elegir video", systemImage: "film") }
                .buttonStyle(.borderedProminent)
            if videoURL != nil, duration > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inicio: \(String(format: "%.1f", start)) s")
                    Slider(value: $start, in: 0...max(duration - 0.1, 0.1)) { _ in
                        if end <= start { end = min(start + 1, duration) }
                    }
                    Text("Fin: \(String(format: "%.1f", end)) s")
                    Slider(value: $end, in: 0.1...max(duration, 0.2)) { _ in
                        if start >= end { start = max(end - 1, 0) }
                    }
                    Stepper("Cuadros por segundo: \(Int(fps))", value: $fps, in: 5...20, step: 1)
                    Text("\(plannedFrames) cuadros" + (plannedFrames > maxFrames ? " (máximo \(maxFrames))" : ""))
                        .font(.caption)
                        .foregroundStyle(plannedFrames > maxFrames ? .red : .secondary)
                    Button { extractVideo() } label: { Label("Crear GIF del tramo", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                        .disabled(plannedFrames > maxFrames || loading)
                }
            }

        case .gif:
            HStack {
                Button { showPicker = true } label: { Label("Desde Fotos", systemImage: "photo") }
                    .buttonStyle(.borderedProminent)
                Button { showGIFFile = true } label: { Label("Desde Archivos", systemImage: "folder") }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var picker: some View {
        switch mode {
        case .photos:
            PhotoPicker(filter: .images, limit: 30) { results in
                showPicker = false
                loadPhotos(results)
            }
        case .video:
            PhotoPicker(filter: .videos, limit: 1) { results in
                showPicker = false
                loadVideo(results)
            }
        case .gif:
            PhotoPicker(filter: .images, limit: 1) { results in
                showPicker = false
                if let r = results.first {
                    loading = true
                    Task {
                        if let d = await r.loadData(type: .gif) { loadGIF(data: d) }
                        else { message = "Ese archivo no es un GIF." }
                        loading = false
                    }
                }
            }
        }
    }

    private func loadPhotos(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { return }
        loading = true
        Task {
            var frames: [GIFFrame] = []
            for r in results {
                if let img = await r.loadUIImage() {
                    frames.append(GIFFrame(image: img.resized(maxSide: 1080), delay: 0.5))
                }
            }
            source = frames
            params.version += 1
            loading = false
        }
    }

    private func loadVideo(_ results: [PHPickerResult]) {
        guard let r = results.first else { return }
        loading = true
        Task {
            if let url = await r.loadFileCopy(type: .movie) {
                videoURL = url
                duration = await GIFTools.videoDuration(url)
                start = 0
                end = min(3, duration)
            } else {
                message = "No se pudo leer el video."
            }
            loading = false
        }
    }

    private func extractVideo() {
        guard let url = videoURL else { return }
        loading = true
        let (s, e, f) = (start, end, fps)
        Task {
            let frames = await GIFTools.framesFromVideo(url: url, start: s, end: e, fps: f, maxSide: 720)
            source = frames
            params.version += 1
            loading = false
            if frames.isEmpty { message = "No se pudieron extraer cuadros." }
        }
    }

    private func loadGIF(data: Data) {
        let frames = GIFTools.decode(data)
        if frames.isEmpty { message = "No se pudo leer ese GIF." }
        source = frames
        params.version += 1
    }

    // MARK: Edición

    private var frameStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cuadros (mantén pulsado para quitar)").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(source.indices, id: \.self) { i in
                        Image(uiImage: source[i].image)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(i + 1)").font(.system(size: 9, weight: .bold))
                                    .padding(2).background(.black.opacity(0.6)).foregroundStyle(.white)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if source.count > 1 { source.remove(at: i); params.version += 1 }
                                } label: { Label("Quitar cuadro", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Velocidad").font(.subheadline)
                Slider(value: $params.speed, in: 0.25...4)
                Text(String(format: "%.2f×", params.speed)).font(.caption.monospacedDigit()).frame(width: 52)
            }
            HStack {
                Text("Tamaño").font(.subheadline)
                Picker("Tamaño", selection: $params.maxSide) {
                    Text("240").tag(CGFloat(240))
                    Text("360").tag(CGFloat(360))
                    Text("480").tag(CGFloat(480))
                    Text("720").tag(CGFloat(720))
                }
                .pickerStyle(.segmented)
            }
            Toggle("Invertir", isOn: $params.reversed)
            Toggle("Ida y vuelta (boomerang)", isOn: $params.pingpong)
            TextField("Texto sobre el GIF (opcional)", text: $params.caption)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actions: some View {
        HStack {
            Button { Task { await export(save: true) } } label: {
                Label("Guardar en Fotos", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            Button { Task { await export(save: false) } } label: {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .disabled(loading)
    }

    private func export(save: Bool) async {
        loading = true
        let out = output
        let url = await Task.detached { GIFTools.encode(out) }.value
        loading = false
        guard let url else { message = "No se pudo crear el GIF."; return }
        let kb = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) / 1024
        if save {
            let ok = await PhotoSaver.saveFiles([url])
            message = ok ? "GIF guardado en Fotos (\(kb) KB)." : "No se pudo guardar. Revisa el permiso de Fotos."
        } else {
            share = ShareItem(urls: [url])
        }
    }
}
