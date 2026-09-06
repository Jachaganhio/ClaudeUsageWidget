import AppKit

// Original geometric artwork for ClaudeUsageWidget. Distributed under the repository's MIT license.
// No third-party icons, fonts, logos, or image assets are used.
@main
struct GenerateAppIcon {
    static let assetDirectory = URL(fileURLWithPath: "ClaudeUsageWidget/Assets.xcassets/AppIcon.appiconset")
    static let center = CGPoint(x: 512, y: 490)
    static let start = 135.0 * Double.pi / 180
    static let sweep = 270.0 * Double.pi / 180

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func draw(in context: CGContext) {
        let tile = CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
                          cornerWidth: 184, cornerHeight: 184, transform: nil)
        context.saveGState()
        context.addPath(tile)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [color(0.17, 0.21, 0.28), color(0.06, 0.08, 0.12)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 180, y: 96),
                                   end: CGPoint(x: 780, y: 928), options: [])
        context.restoreGState()
        context.addPath(tile)
        context.setStrokeColor(color(0.26, 0.31, 0.38))
        context.setLineWidth(3)
        context.strokePath()

        func arc(radius: CGFloat, fraction: Double, width: CGFloat, color: CGColor) {
            context.beginPath()
            context.addArc(center: center, radius: radius, startAngle: start,
                           endAngle: start + sweep * fraction, clockwise: false)
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.strokePath()
        }
        let track = color(0.24, 0.29, 0.35)
        arc(radius: 269, fraction: 1, width: 65, color: track)
        arc(radius: 167, fraction: 1, width: 60, color: track)
        arc(radius: 269, fraction: 0.79, width: 65, color: color(0.22, 0.85, 0.80))
        arc(radius: 167, fraction: 0.59, width: 60, color: color(1.0, 0.66, 0.36))
        context.setFillColor(color(0.92, 0.96, 0.98))
        context.fillEllipse(in: CGRect(x: 481, y: 459, width: 62, height: 62))
        let base = CGPath(roundedRect: CGRect(x: 421, y: 763, width: 182, height: 25),
                          cornerWidth: 12.5, cornerHeight: 12.5, transform: nil)
        context.addPath(base)
        context.setFillColor(color(0.47, 0.54, 0.62))
        context.fillPath()
    }

    static func svgArc(radius: Double, fraction: Double, width: Int, color: String) -> String {
        let end = start + sweep * fraction
        let x1 = 512 + radius * cos(start), y1 = 490 + radius * sin(start)
        let x2 = 512 + radius * cos(end), y2 = 490 + radius * sin(end)
        return "<path d=\"M \(x1) \(y1) A \(radius) \(radius) 0 \(sweep * fraction > .pi ? 1 : 0) 1 \(x2) \(y2)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(width)\" stroke-linecap=\"round\"/>"
    }

    static func main() throws {
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(size))
            context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
            draw(in: context)
            let image = context.makeImage()!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: assetDirectory.appendingPathComponent("icon_\(size).png"))
        }
        var images: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                images.append(["filename": "icon_\(size * scale).png", "idiom": "mac",
                               "size": "\(size)x\(size)", "scale": "\(scale)x"])
            }
        }
        let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: assetDirectory.appendingPathComponent("Contents.json"))
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
          <title>ClaudeUsageWidget — dual usage meters</title>
          <desc>Original geometric artwork. MIT license. No third-party imagery.</desc>
          <defs><linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#2b3647"/><stop offset="1" stop-color="#0f141f"/></linearGradient></defs>
          <rect x="96" y="96" width="832" height="832" rx="184" fill="url(#tile)" stroke="#424f61" stroke-width="3"/>
          \(svgArc(radius: 269, fraction: 1, width: 65, color: "#3d4a59"))
          \(svgArc(radius: 167, fraction: 1, width: 60, color: "#3d4a59"))
          \(svgArc(radius: 269, fraction: 0.79, width: 65, color: "#38d9cc"))
          \(svgArc(radius: 167, fraction: 0.59, width: 60, color: "#ffa85c"))
          <circle cx="512" cy="490" r="31" fill="#ebf5fa"/>
          <rect x="421" y="763" width="182" height="25" rx="12.5" fill="#788a9e"/>
        </svg>
        """
        try svg.write(toFile: "artwork/AppIcon.svg", atomically: true, encoding: .utf8)
        print("Generated vector source and all 10 macOS AppIcon slots (16–1024 px).")
    }
}
