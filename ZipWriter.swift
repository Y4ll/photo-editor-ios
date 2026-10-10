import Foundation
import UIKit

/// Escritor ZIP mínimo (sin compresión, "stored"). Compatible con Archivos, Windows y macOS.
enum ZipWriter {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    private static func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    static func zip(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0

        for f in files {
            let name = Data(f.name.utf8)
            let crc = crc32(f.data)
            let size = UInt32(f.data.count)
            let offset = UInt32(out.count)

            // Cabecera local
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0x0800))
            out.append(le16(0)); out.append(le16(0)); out.append(le16(0x21))
            out.append(le32(crc)); out.append(le32(size)); out.append(le32(size))
            out.append(le16(UInt16(name.count))); out.append(le16(0))
            out.append(name); out.append(f.data)

            // Directorio central
            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(size)); central.append(le32(size))
            central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
            central.append(le32(offset)); central.append(name)
            count += 1
        }

        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(count)); out.append(le16(count))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset)); out.append(le16(0))
        return out
    }

    static func zipFile(_ files: [(name: String, data: Data)], name: String) -> URL? {
        let url = tempURL("zip", name: name)
        do { try zip(files).write(to: url); return url } catch { return nil }
    }

    static func zipImages(_ images: [UIImage], baseName: String) -> URL? {
        let files = images.enumerated().compactMap { i, img -> (name: String, data: Data)? in
            guard let d = img.pngData() else { return nil }
            return (name: "\(baseName)_\(String(format: "%03d", i + 1)).png", data: d)
        }
        return zipFile(files, name: baseName)
    }
}
