import AppKit

let destination = URL(fileURLWithPath: "Companion/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not allocate the icon bitmap.")
}
let colors = [
    CGColor(colorSpace: colorSpace, components: [0.025, 0.22, 0.25, 1])!,
    CGColor(colorSpace: colorSpace, components: [0.04, 0.56, 0.53, 1])!
]
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])

context.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.96, 0.98, 0.94, 1])!)
context.setLineWidth(58)
context.setLineCap(.round)
context.move(to: CGPoint(x: 260, y: 410))
context.addLine(to: CGPoint(x: 260, y: 520))
context.addCurve(to: CGPoint(x: 764, y: 520),
                 control1: CGPoint(x: 260, y: 856), control2: CGPoint(x: 764, y: 856))
context.addLine(to: CGPoint(x: 764, y: 410))
context.strokePath()
context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.96, 0.98, 0.94, 1])!)
for x: CGFloat in [208, 696] {
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: 288, width: 120, height: 240),
                           cornerWidth: 56, cornerHeight: 56, transform: nil))
    context.fillPath()
}
context.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1, 0.78, 0.39, 1])!)
context.setLineWidth(30)
for (index, height) in [64.0, 144, 228, 144, 64].enumerated() {
    let x = 408 + Double(index) * 52
    context.move(to: CGPoint(x: x, y: 432 - height / 2))
    context.addLine(to: CGPoint(x: x, y: 432 + height / 2))
}
context.strokePath()
guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the icon.")
}
try png.write(to: destination, options: .atomic)
print("Wrote \(destination.path)")
