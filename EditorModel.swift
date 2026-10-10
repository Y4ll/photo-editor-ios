import SwiftUI
import CoreImage

// MARK: - Tipos

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none, noir, chrome, fade, instant, mono, process, tonal, transfer, sepia
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Original"
        case .noir: return "Noir"
        case .chrome: return "Cromo"
        case .fade: return "Desvanecido"
        case .instant: return "Instantánea"
        case .mono: return "Mono"
        case .process: return "Proceso"
        case .tonal: return "Tonal"
        case .transfer: return "Transfer"
        case .sepia: return "Sepia"
        }
    }

    var ciName: String? {
        switch self {
        case .none: return nil
        case .noir: return "CIPhotoEffectNoir"
        case .chrome: return "CIPhotoEffectChrome"
        case .fade: return "CIPhotoEffectFade"
        case .instant: return "CIPhotoEffectInstant"
        case .mono: return "CIPhotoEffectMono"
        case .process: return "CIPhotoEffectProcess"
        case .tonal: return "CIPhotoEffectTonal"
        case .transfer: return "CIPhotoEffectTransfer"
        case .sepia: return "CISepiaTone"
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free = "Libre", square = "1:1", r43 = "4:3", r34 = "3:4", r169 = "16:9", r916 = "9:16"
    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .r43: return 4.0 / 3.0
        case .r34: return 3.0 / 4.0
        case .r169: return 16.0 / 9.0
        case .r916: return 9.0 / 16.0
        }
    }
}

enum TextColor: String, CaseIterable, Identifiable {
    case white, black, red, yellow, blue, green
    var id: String { rawValue }

    var ui: UIColor {
        switch self {
        case .white: return .white
        case .black: return .black
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .green: return .systemGreen
        }
    }
    var color: Color { Color(ui) }
}

struct TextOverlay: Equatable, Identifiable {
    var id = UUID()
    var text: String
    var x = 0.5          // 0...1 (posición horizontal del centro)
    var y = 0.5          // 0...1
    var size = 0.08      // fracción del lado menor
    var color: TextColor = .white
}

struct EditState: Equatable {
    var brightness = 0.0      // -0.5...0.5
    var contrast = 1.0        // 0.5...1.5
    var saturation = 1.0      // 0...2
    var exposure = 0.0        // -2...2
    var sharpness = 0.0       // 0...2
    var warmth = 0.0          // -1...1
    var filter: PhotoFilter = .none
    var filterIntensity = 1.0
    var rotation = 0          // cuartos de vuelta
    var flipH = false
    var aspect: CropAspect = .free
    var zoom = 1.0            // 1...3
    var panX = 0.0            // -1...1
    var panY = 0.0
    var texts: [TextOverlay] = []
}

// MARK: - Render

enum EditRenderer {
    static let context = CIContext()

    static func render(_ src: UIImage, _ s: EditState) -> UIImage {
        let base = src.normalized()
        guard let cg = base.cgImage else { return src }
        let input = CIImage(cgImage: cg)
        var ci = input

        if s.warmth != 0 {
            ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500 + s.warmth * 2500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }
        if s.exposure != 0 {
            ci = ci.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: s.exposure])
        }
        ci = ci.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: s.brightness,
            kCIInputContrastKey: s.contrast,
            kCIInputSaturationKey: s.saturation
        ])
        if s.sharpness > 0 {
            ci = ci.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: s.sharpness])
        }
        if let name = s.filter.ciName {
            var p: [String: Any] = [:]
            if s.filter == .sepia { p[kCIInputIntensityKey] = 1.0 }
            let filtered = ci.applyingFilter(name, parameters: p)
            if s.filterIntensity < 0.999 {
                ci = ci.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: filtered,
                    kCIInputTimeKey: s.filterIntensity
                ])
            } else {
                ci = filtered
            }
        }

        guard let out = context.createCGImage(ci, from: input.extent) else { return base }
        var img = UIImage(cgImage: out)
        img = transform(img, s)
        img = crop(img, s)
        img = draw(texts: s.texts, on: img)
        return img
    }

    private static func transform(_ img: UIImage, _ s: EditState) -> UIImage {
        let q = ((s.rotation % 4) + 4) % 4
        if q == 0 && !s.flipH { return img }
        let w = img.size.width, h = img.size.height
        let newSize = q % 2 == 0 ? CGSize(width: w, height: h) : CGSize(width: h, height: w)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: f).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: CGFloat(q) * .pi / 2)
            if s.flipH { c.scaleBy(x: -1, y: 1) }
            img.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
    }

    private static func crop(_ img: UIImage, _ s: EditState) -> UIImage {
        guard s.aspect != .free || s.zoom > 1.001, let cg = img.cgImage else { return img }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var cw = w, ch = h
        if let r = s.aspect.ratio {
            if w / h > r { cw = h * r } else { ch = w / r }
        }
        cw /= CGFloat(s.zoom)
        ch /= CGFloat(s.zoom)
        let x = (w - cw) / 2 + CGFloat(s.panX) * (w - cw) / 2
        let y = (h - ch) / 2 + CGFloat(s.panY) * (h - ch) / 2
        guard let c = cg.cropping(to: CGRect(x: x, y: y, width: cw, height: ch).integral) else { return img }
        return UIImage(cgImage: c)
    }

    private static func draw(texts: [TextOverlay], on img: UIImage) -> UIImage {
        guard !texts.isEmpty else { return img }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: f).image { _ in
            img.draw(at: .zero)
            let m = min(img.size.width, img.size.height)
            for t in texts where !t.text.isEmpty {
                let font = UIFont.systemFont(ofSize: max(8, t.size * m), weight: .bold)
                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
                shadow.shadowBlurRadius = font.pointSize * 0.08
                shadow.shadowOffset = CGSize(width: 0, height: font.pointSize * 0.04)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: t.color.ui, .shadow: shadow
                ]
                let str = NSAttributedString(string: t.text, attributes: attrs)
                let sz = str.size()
                str.draw(at: CGPoint(x: t.x * img.size.width - sz.width / 2,
                                     y: t.y * img.size.height - sz.height / 2))
            }
        }
    }
}

// MARK: - Modelo

@MainActor
final class EditorModel: ObservableObject {
    let original: UIImage
    let small: UIImage

    @Published var state = EditState() { didSet { rerender() } }
    @Published var preview: UIImage
    @Published var thumbs: [PhotoFilter: UIImage] = [:]

    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var renderTask: Task<Void, Never>?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: UIImage) {
        let n = image.normalized()
        original = n
        small = n.resized(maxSide: 1400)
        preview = small

        let t = small.resized(maxSide: 160)
        Task.detached { [weak self] in
            var d: [PhotoFilter: UIImage] = [:]
            for f in PhotoFilter.allCases {
                var s = EditState()
                s.filter = f
                d[f] = EditRenderer.render(t, s)
            }
            await MainActor.run { self?.thumbs = d }
        }
    }

    /// Llamar justo antes de un cambio para poder deshacerlo.
    func beginEdit() {
        undoStack.append(state)
        redoStack.removeAll()
        objectWillChange.send()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(state)
        state = last
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }

    func reset() {
        beginEdit()
        state = EditState()
    }

    private func rerender() {
        renderTask?.cancel()
        let s = state
        let src = small
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            let img = EditRenderer.render(src, s)
            if Task.isCancelled { return }
            await MainActor.run { self?.preview = img }
        }
    }

    func renderFull() async -> UIImage {
        let s = state
        let src = original
        return await Task.detached(priority: .userInitiated) {
            EditRenderer.render(src, s)
        }.value
    }
}
