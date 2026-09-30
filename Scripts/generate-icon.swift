import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.cgContext.setAllowsAntialiasing(true)

    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 76, width: 880, height: 880),
                            xRadius: 204, yRadius: 204)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.19, alpha: 0.2)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.986, green: 0.984, blue: 0.97, alpha: 1).setFill()
    tile.fill()
    NSShadow().set()

    let track = NSBezierPath()
    track.appendArc(withCenter: NSPoint(x: 512, y: 516), radius: 292,
                    startAngle: 0, endAngle: 360)
    track.lineWidth = 34
    NSColor(calibratedRed: 0.87, green: 0.92, blue: 0.86, alpha: 1).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 512, y: 516), radius: 292,
                  startAngle: 90, endAngle: 390, clockwise: true)
    arc.lineWidth = 34
    arc.lineCapStyle = .round
    NSColor(calibratedRed: 0.45, green: 0.59, blue: 0.46, alpha: 1).setStroke()
    arc.stroke()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: 354, y: 524))
    check.line(to: NSPoint(x: 463, y: 415))
    check.line(to: NSPoint(x: 682, y: 642))
    check.lineWidth = 61
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor(calibratedRed: 0.29, green: 0.45, blue: 0.32, alpha: 1).setStroke()
    check.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon PNG")
    }
    try png.write(to: destination.appendingPathComponent("icon-\(size).png"))
}
