// Herramienta de un solo uso: genera Resources/AppIcon.icns sin dependencias.
// Dibuja un tablero semanal (7 columnas, una destacada) con CoreGraphics.
//
//   swift Tools/makeicon.swift  (desde la carpeta del proyecto)
import AppKit
import Foundation

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

func drawIcon(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(px) / 512.0          // todo el trazado se define en un lienzo de 512
    let rect = CGRect(x: 0, y: 0, width: 512, height: 512)

    // Fondo: redondeado con degradado azul profundo (legible en claro y oscuro).
    let radius: CGFloat = 108 * s
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(bg)
    cg.clip()
    let colors = [CGColor(red: 0.07, green: 0.36, blue: 0.78, alpha: 1),
                  CGColor(red: 0.02, green: 0.18, blue: 0.45, alpha: 1)] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                             locations: [0, 1]) {
        cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 512), end: CGPoint(x: 0, y: 0),
                              options: [])
    }
    cg.restoreGState()

    // Cabecera del tablero.
    let head = CGRect(x: 64 * s, y: 372 * s, width: 200 * s, height: 34 * s)
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    cg.addPath(CGPath(roundedRect: head, cornerWidth: 17 * s, cornerHeight: 17 * s, transform: nil))
    cg.fillPath()

    // Siete columnas; la tercera destacada (hoy).
    let cols = 7, gap: CGFloat = 12 * s
    let areaW = 512 - 128 * s
    let colW = (areaW - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let baseX: CGFloat = 64 * s
    let topY: CGFloat = 330 * s
    let botY: CGFloat = 76 * s
    for i in 0..<cols {
        let x = baseX + CGFloat(i) * (colW + gap)
        let highlighted = (i == 2)
        let colRect = CGRect(x: x, y: botY, width: colW, height: topY - botY)
        cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: highlighted ? 0.30 : 0.14))
        cg.addPath(CGPath(roundedRect: colRect, cornerWidth: 12 * s, cornerHeight: 12 * s, transform: nil))
        cg.fillPath()

        // Tareas dentro de la columna.
        let rows = highlighted ? 4 : (i % 2 == 0 ? 3 : 2)
        var y = topY - 16 * s
        for r in 0..<rows {
            let h = 26 * s
            let w = colW - (r % 2 == 0 ? 10 * s : 26 * s)
            let cardRect = CGRect(x: x + 5 * s, y: y - h, width: w, height: h)
            cg.setFillColor(CGColor(red: 1, green: 1, blue: 1,
                                    alpha: highlighted ? 0.98 : 0.62))
            cg.addPath(CGPath(roundedRect: cardRect, cornerWidth: 8 * s, cornerHeight: 8 * s, transform: nil))
            cg.fillPath()
            y -= h + 12 * s
            if y < botY + 20 * s { break }
        }
    }

    // Punto de acento en la columna destacada.
    cg.setFillColor(CGColor(red: 0.20, green: 0.86, blue: 0.60, alpha: 1))
    cg.fillEllipse(in: CGRect(x: baseX + 2 * (colW + gap) + colW - 22 * s,
                              y: topY - 6 * s, width: 16 * s, height: 16 * s))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources", isDirectory: true)
let iconSet = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

for (px, name) in sizes {
    guard let data = drawIcon(px: px) else { FileHandle.standardError.write("fallo dibujando \(px)\n".data(using: .utf8)!); continue }
    try? data.write(to: iconSet.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconSet.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try? task.run()
task.waitUntilExit()
if task.terminationStatus == 0 {
    print("→ Resources/AppIcon.icns generado")
} else {
    print("⚠ iconutil falló (status \(task.terminationStatus)); PNGs quedaron en \(iconSet.path)")
}
