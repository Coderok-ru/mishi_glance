import AppKit
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let side = Double(CommandLine.arguments[3])!
guard let img = NSImage(contentsOfFile: src) else { print("NSImage не смог"); exit(1) }
let out = NSImage(size: NSSize(width: side, height: side))
out.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
out.unlockFocus()
guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: dst))
print("отрендерено \(rep.pixelsWide)x\(rep.pixelsHigh)")
