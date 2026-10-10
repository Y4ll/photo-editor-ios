import UIKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

struct GIFFrame {
    var image: UIImage
    var delay: Double   // segundos
}

enum GIFTools {

    /// Lee todos los cuadros de un GIF con su duración.
    static func decode(_ data: Data) -> [GIFFrame] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        var out: [GIFFrame] = []
        for i in 0..<n {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let g = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                delay = (g[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (g[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                if delay < 0.02 { delay = 0.1 }
            }
            out.append(GIFFrame(image: UIImage(cgImage: cg), delay: delay))
        }
        return out
    }

    /// Escribe un GIF animado (bucle infinito) en un archivo temporal.
    static func encode(_ frames: [GIFFrame]) -> URL? {
        guard !frames.isEmpty else { return nil }
        let url = tempURL("gif", name: "animacion")
        try? FileManager.default.removeItem(at: url)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for f in frames {
            guard let cg = f.image.cgImage else { continue }
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: f.delay]] as CFDictionary
            CGImageDestinationAddImage(dest, cg, props)
        }
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    /// Aplica velocidad, orden, tamaño y texto a una lista de cuadros.
    static func process(_ frames: [GIFFrame], speed: Double, reversed: Bool, pingpong: Bool,
                        maxSide: CGFloat, caption: String) -> [GIFFrame] {
        var list = frames
        if reversed { list.reverse() }
        if pingpong, list.count > 2 { list += list.dropFirst().dropLast().reversed() }
        guard let first = list.first else { return [] }

        let canvas = first.image.resized(maxSide: maxSide).size
        return list.map { f in
            var img = f.image.resized(maxSide: maxSide)
            if img.size != canvas { img = img.filled(to: canvas) }
            if !caption.isEmpty { img = drawCaption(caption, on: img) }
            return GIFFrame(image: img, delay: max(0.02, f.delay / max(speed, 0.1)))
        }
    }

    private static func drawCaption(_ text: String, on img: UIImage) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: f).image { _ in
            img.draw(at: .zero)
            let font = UIFont.systemFont(ofSize: max(12, img.size.height * 0.09), weight: .heavy)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -4,
                .paragraphStyle: para
            ]
            let margin = img.size.width * 0.05
            let rect = CGRect(x: margin, y: 0, width: img.size.width - margin * 2, height: img.size.height)
            let bounds = (text as NSString).boundingRect(with: rect.size, options: .usesLineFragmentOrigin,
                                                         attributes: attrs, context: nil)
            let drawRect = CGRect(x: margin, y: img.size.height - bounds.height - img.size.height * 0.05,
                                  width: rect.width, height: bounds.height)
            (text as NSString).draw(with: drawRect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        }
    }

    static func videoDuration(_ url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return 0 }
        let s = CMTimeGetSeconds(d)
        return s.isFinite ? s : 0
    }

    /// Extrae cuadros de un video entre `start` y `end` segundos.
    static func framesFromVideo(url: URL, start: Double, end: Double, fps: Double,
                                maxSide: CGFloat) async -> [GIFFrame] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSide, height: maxSide)
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        let step = 1.0 / fps
        var t = start
        var out: [GIFFrame] = []
        while t <= end {
            if let (cg, _) = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                out.append(GIFFrame(image: UIImage(cgImage: cg), delay: step))
            }
            t += step
        }
        return out
    }
}

/// Vista que reproduce los cuadros en bucle.
struct AnimatedImageView: UIViewRepresentable {
    let frames: [GIFFrame]

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        guard !frames.isEmpty else { v.image = nil; return }
        let total = frames.reduce(0) { $0 + $1.delay }
        v.image = UIImage.animatedImage(with: frames.map(\.image), duration: max(total, 0.05))
    }
}
