#!/usr/bin/env swift

import AppKit

/// Generate Openly app icon — light + dark variants — at all required sizes
/// Usage: cd Assets && swift generate_icon.swift && iconutil -c icns AppIcon-light.iconset -o AppIcon.icns && iconutil -c icns AppIcon-dark.iconset -o AppIcon-dark.icns

let baseDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let fm = FileManager.default

let sizes: [(name: String, width: Int)] = [
    ("icon_16x16", 16),      ("icon_16x16@2x", 32),
    ("icon_32x32", 32),      ("icon_32x32@2x", 64),
    ("icon_128x128", 128),   ("icon_128x128@2x", 256),
    ("icon_256x256", 256),   ("icon_256x256@2x", 512),
    ("icon_512x512", 512),   ("icon_512x512@2x", 1024),
]

// MARK: - Render

func renderIcon(size: Int, dark: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.224  // macOS icon radius ~22.4%

    // Background
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    if dark {
        NSColor(white: 0.16, alpha: 1.0).setFill()
    } else {
        NSColor.white.setFill()
    }
    bgPath.fill()

    // SF Symbol
    let symbolSize = CGFloat(size) * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: dark ? .white : .systemBlue))

    guard let symbol = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        image.unlockFocus()
        return image
    }

    let symRect = NSRect(
        x: (CGFloat(size) - symbolSize) / 2,
        y: (CGFloat(size) - symbolSize) / 2,
        width: symbolSize,
        height: symbolSize
    )

    // Apply tint color
    let tint = dark ? NSColor.white : NSColor.systemBlue
    tint.setFill()

    symbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, path: String) {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("  ✗ CGImage failed: \(path)"); return
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = image.size
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("  ✗ PNG encode failed: \(path)"); return
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("  ✓ \(path)")
}

// MARK: - Generate

for (variant, dark, dirName) in [
    ("Light", false, "AppIcon-light.iconset"),
    ("Dark", true, "AppIcon-dark.iconset"),
] {
    let dir = "\(baseDir)/\(dirName)"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    print("Generating \(variant) icons → \(dirName)/")

    for (name, size) in sizes {
        let img = renderIcon(size: size, dark: dark)
        savePNG(image: img, path: "\(dir)/\(name).png")
    }
}

print("""

Done. Now run:
  cd \(baseDir)
  iconutil -c icns AppIcon-light.iconset -o AppIcon.icns
  iconutil -c icns AppIcon-dark.iconset -o AppIcon-dark.icns
  cp AppIcon*.icns ../Sources/Resources/
""")
