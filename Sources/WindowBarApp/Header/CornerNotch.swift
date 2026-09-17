import AppKit
import QuartzCore

/// Alpha mask of the notch that a rectangular header leaves outside a window's rounded top corner:
/// opaque where the desktop would show through, transparent over the window itself. The shape is rendered
/// by Core Animation with `cornerCurve = .continuous`, the same curve the window server applies to
/// standard windows, so the fill meets the window edge without covering it. Cached per radius and scale.
@MainActor enum CornerNotch {
    private static var cache: [String: CGImage] = [:]

    /// A square mask of `extent` points at `scale` pixels per point. The notch sits at the bottom-left
    /// corner in Core Graphics orientation, which is the top-left corner when drawn into a flipped view.
    static func mask(radius: Double, extent: Double, scale: Double) -> CGImage? {
        let key = "\(radius)/\(extent)/\(scale)"
        if let hit = cache[key] { return hit }
        let pixels = Int((extent * scale).rounded(.up))
        guard pixels > 0, radius > 0, scale > 0,
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: extent * 4, height: extent * 4)
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.contentsScale = scale
        layer.render(in: context)
        guard let data = context.data else { return nil }
        // The layer covered everything except the notch. Invert the alpha so the notch is what remains.
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: pixels * pixels * 4, by: 4) {
            let alpha = 255 - bytes[offset + 3]
            bytes[offset] = alpha; bytes[offset + 1] = alpha; bytes[offset + 2] = alpha; bytes[offset + 3] = alpha
        }
        let image = context.makeImage()
        cache[key] = image
        return image
    }
}
