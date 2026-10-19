#!/usr/bin/env bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
# Run it after editing the SVG and commit both files; package_app.sh only copies the .icns.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SVG="$ROOT/Resources/AppIcon.svg"
ICNS="$ROOT/Resources/AppIcon.icns"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$WORK/render.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("Could not load \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    }
}
SWIFT

swift "$WORK/render.swift" "$SVG" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Created $ICNS"
