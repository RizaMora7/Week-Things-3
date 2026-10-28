// iconpack — extracts an icon from a reference sheet and saves it as a square
// master, with rounded corners and real transparency (without the shadow halo
// that comes with the sheet).
//
//   xcrun swiftc -framework AppKit -o build/iconpack Tools/iconpack.swift
//   build/iconpack crop  sheet.png master.png x0 y0 x1 y1 [radius]
//   build/iconpack probe sheet.png y0 y1 [xa xb]  // edges row by row
//
// `probe` helps get the crop right: it compares each pixel with the page
// background (sampled at the left edge) and reports where it starts to differ,
// with two tolerances: 0.06 also catches the soft shadow and 0.30 only the
// squircle's hard edge. With `xa xb` the sweep is limited to one icon's column.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("uso: iconpack <crop|probe> <lamina> …\n".data(using: .utf8)!)
    exit(2)
}
let path = args[2]
guard let ns = NSImage(contentsOfFile: path),
      let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("no se pudo leer \(path)\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cg)
let W = rep.pixelsWide, H = rep.pixelsHigh

func px(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    guard let c = rep.colorAt(x: x, y: y) else { return (0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent)
}
func dist(_ a: (r: CGFloat, g: CGFloat, b: CGFloat), _ b: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
    abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
}

if args[1] == "probe" {
    let y0 = max(0, Int(args[3]) ?? 0), y1 = min(H - 1, Int(args[4]) ?? y0)
    let xa = args.count > 5 ? max(0, Int(args[5])!) : 0
    let xb = args.count > 6 ? min(W - 1, Int(args[6])!) : W - 1
    print("sheet \(W)x\(H)  column window \(xa)…\(xb)")
    var y = y0
    while y <= y1 {
        let bg = px(max(0, xa - 2), y)
        var soft = -1, hard = -1, softR = -1, hardR = -1
        for x in xa...xb {
            let d = dist(px(x, y), bg)
            if d > 0.06, soft < 0 { soft = x }
            if d > 0.30, hard < 0 { hard = x }
        }
        for x in stride(from: xb, through: xa, by: -1) {
            let d = dist(px(x, y), bg)
            if d > 0.06, softR < 0 { softR = x }
            if d > 0.30, hardR < 0 { hardR = x }
        }
        print(String(format: "y=%4d  soft %4d…%4d   hard %4d…%4d", y, soft, softR, hard, hardR))
        y += max(1, (y1 - y0) / 40)
    }
    exit(0)
}

guard args.count >= 8, args[1] == "crop" else {
    FileHandle.standardError.write("uso: iconpack crop <lamina> <salida> x0 y0 x1 y1 [radio]\n".data(using: .utf8)!)
    exit(2)
}
let x0 = Int(args[4])!, y0 = Int(args[5])!, x1 = Int(args[6])!, y1 = Int(args[7])!
let radiusFrac = args.count > 8 ? (Double(args[8]) ?? 0.20) : 0.20
let outPath = args[3]
let side = CGFloat(min(x1 - x0, y1 - y0))
let master: CGFloat = 1024
let scale = master / side

guard let ctx = CGContext(data: nil, width: Int(master), height: Int(master), bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

let r = master * CGFloat(radiusFrac)
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: master, height: master),
                   cornerWidth: r, cornerHeight: r, transform: nil))
ctx.clip()
ctx.interpolationQuality = .high
// `draw(_:in:)` already draws the image upright in a bottom-left-origin context,
// so no flipping is needed: the sheet's row `y0` (counted from the top) must
// land on the canvas's top edge, which is y = master.
ctx.draw(cg, in: CGRect(x: -CGFloat(x0) * scale,
                        y: master - (CGFloat(H) - CGFloat(y0)) * scale,
                        width: CGFloat(W) * scale, height: CGFloat(H) * scale))
guard let out = ctx.makeImage() else { exit(1) }

let dst = NSBitmapImageRep(cgImage: out)
guard let data = dst.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: outPath))
print("cropped \(Int(side)) px from the sheet → \(Int(master)) px with radius \(Int(radiusFrac * 100))% at \(outPath)")
