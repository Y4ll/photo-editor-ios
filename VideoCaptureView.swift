import SwiftUI
import AVFoundation
import PhotosUI

/// Captura de Video: saca fotogramas sueltos o uno cada N segundos.
struct VideoCaptureView: View {
    @State private var videoURL: URL?
    @State private var duration = 0.0
    @State private var time = 0.0
    @State private var preview: UIImage?
    @State private var captured: [UIImage] = []
    @State private var interval = 1.0
    @State private var showPicker = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { showPicker = true } label: { Label("Elegir video", systemImage: "film") }
                    .buttonStyle(.borderedProminent)

                if videoURL != nil {
                    Group {
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit()
                        } else {
                            Color(white: 0.1).frame(height: 200)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(String(format: "%.2f s de %.2f s", time, duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Slider(value: $time, in: 0...max(duration, 0.1))

                    HStack {
                        Button { step(-0.1) } label: { Image(systemName: "backward.frame") }
                        Button { capture() } label: { Label("Capturar fotograma", systemImage: "camera.shutter.button") }
                            .buttonStyle(.borderedProminent)
                        Button { step(0.1) } label: { Image(systemName: "forward.frame") }
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    Stepper("Un fotograma cada \(String(format: "%.1f", interval)) s",
                            value: $interval, in: 0.2...10, step: 0.2)
                    Text("Total: \(Int(duration / interval) + 1) imágenes").font(.caption).foregroundStyle(.secondary)
                    Button { captureAll() } label: { Label("Capturar todo el video", systemImage: "square.grid.3x3") }
                        .buttonStyle(.bordered)
                        .disabled(loading || Int(duration / interval) + 1 > 200)
                }

                if loading { ProgressView("Capturando…") }
                if !captured.isEmpty {
                    HStack {
                        Text("Capturas").font(.headline)
                        Spacer()
                        Button("Borrar todas", role: .destructive) { captured = [] }.font(.footnote)
                    }
                    ResultsGrid(images: captured, baseName: "video")
                }
            }
            .padding()
        }
        .navigationTitle("Captura de Video")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(filter: .videos, limit: 1) { results in
                showPicker = false
                guard let r = results.first else { return }
                loading = true
                Task {
                    if let url = await r.loadFileCopy(type: .movie) {
                        videoURL = url
                        duration = await GIFTools.videoDuration(url)
                        time = 0
                        captured = []
                    } else {
                        message = "No se pudo leer el video."
                    }
                    loading = false
                }
            }
        }
        .task(id: time) {
            guard videoURL != nil else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            preview = await grab(at: time, exact: false)
        }
        .task(id: videoURL) {
            if videoURL != nil { preview = await grab(at: 0, exact: false) }
        }
        .messageAlert($message)
    }

    private func step(_ d: Double) {
        time = min(max(time + d, 0), duration)
    }

    private func grab(at t: Double, exact: Bool) async -> UIImage? {
        guard let url = videoURL else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        if exact {
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
        } else {
            gen.maximumSize = CGSize(width: 800, height: 800)
        }
        guard let (cg, _) = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func capture() {
        Task {
            if let img = await grab(at: time, exact: true) { captured.append(img) }
            else { message = "No se pudo capturar ese fotograma." }
        }
    }

    private func captureAll() {
        loading = true
        Task {
            var t = 0.0
            while t <= duration {
                if let img = await grab(at: t, exact: true) { captured.append(img) }
                t += interval
            }
            loading = false
        }
    }
}
