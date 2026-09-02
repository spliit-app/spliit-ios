#!/usr/bin/env swift
//
// Wraps the raw App Store captures in the listing's own artwork: a brand gradient, a headline,
// and a device the screenshot sits inside.
//
//   swift Scripts/frame-screenshots.swift <captures> <destination> <captions.json>
//
// It walks <captures>/<locale>/<device>/*.png — the tree `Scripts/screenshots.sh` writes — and
// puts a framed copy of each at the same path under <destination>, under the same file name, so
// the numbering that orders the set in App Store Connect survives.
//
// The raw captures stay the source of truth, which is the point of doing this as a second pass:
// a new headline or a different green is seconds of work here, where re-photographing the app
// is a simulator per language per device and the better part of half an hour.
//
// AppKit does all of it. Nothing here needs a dependency, and the fonts are the system's own —
// the same SF the screenshots inside the frame were drawn with.

import AppKit
import Foundation

// MARK: - Palette
//
// The app's own tokens, read off Assets.xcassets rather than invented: AccentColor is the
// emerald, and its dark-appearance variant is the lighter end of the gradient. A listing that
// uses the product's colours looks like the product.

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Dark at the top, where the headline is, and bright at the bottom, where the device is.
///
/// The other way round is the more usual choice and it fails the only test that matters here:
/// white display type on `#10B981` is about 2.5:1, which is under the 3:1 large-text floor, and
/// an App Store thumbnail is exactly where that shows.
let gradientTop = rgb(0x064E3B)
let gradientBottom = rgb(0x10B981)
let bezelColor = rgb(0x0B1F17)

// MARK: - Device profiles

struct Profile {
    /// The canvas App Store Connect accepts for this device, which is also the size of the
    /// capture: the frame is drawn around a screenshot at its own scale, never a resized one.
    let canvas: NSSize
    /// The screen's width as a fraction of the canvas.
    let screenWidthFraction: CGFloat
    /// Corner radius as a fraction of the screen's width, taken from the real hardware — the
    /// iPhone's corners are dramatic and the iPad's are nearly square, and getting this wrong
    /// is the detail that makes a frame look drawn rather than photographed.
    let cornerFraction: CGFloat
    let bezel: CGFloat
    let headlineSize: CGFloat
    /// Distance from the top of the canvas to the top of the first line of the headline.
    let headlineTop: CGFloat
    /// From the last line of the headline to the top of the device.
    let headlineGap: CGFloat
    /// The clear space the headline keeps either side of it. A translation that would run past
    /// it shrinks to fit rather than crowding the edge — French is reliably the longer of the
    /// two, and a line that nearly touches the canvas reads as a mistake at thumbnail size.
    let headlineMargin: CGFloat

    static func named(_ name: String) -> Profile? {
        switch name {
        case "iphone-6.9":
            return Profile(
                canvas: NSSize(width: 1320, height: 2868),
                screenWidthFraction: 0.80,
                cornerFraction: 0.125,
                bezel: 14,
                headlineSize: 86,
                headlineTop: 150,
                headlineGap: 96,
                headlineMargin: 110
            )
        case "ipad-13":
            return Profile(
                canvas: NSSize(width: 2064, height: 2752),
                screenWidthFraction: 0.76,
                cornerFraction: 0.030,
                bezel: 18,
                headlineSize: 104,
                headlineTop: 180,
                headlineGap: 110,
                headlineMargin: 170
            )
        default:
            return nil
        }
    }
}

// MARK: - Drawing

/// One line of the headline, measured so it can be centred and stacked by hand.
///
/// Laid out a line at a time rather than handed to a text container: the breaks come from
/// `captions.json`, where somebody chose them, and automatic wrapping would quietly override
/// that the first time a translation ran a word longer.
func attributed(_ line: String, size: CGFloat) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    return NSAttributedString(
        string: line,
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            // Display type is drawn too loose at these sizes; a touch of negative tracking is
            // what the system does for itself in its own large titles.
            .kern: -size * 0.015,
        ]
    )
}

func frame(capture: NSImage, caption: String, profile: Profile) -> NSBitmapImageRep {
    let canvas = profile.canvas
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = canvas

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(origin: .zero, size: canvas)

    // The background. Angle 270 puts the starting colour at the top; AppKit's zero is to the
    // right and it turns anticlockwise.
    NSGradient(starting: gradientTop, ending: gradientBottom)?.draw(in: bounds, angle: 270)

    // The headline, stacked downwards from `headlineTop`. The context is unflipped, so a line's
    // drawing origin is its lower-left corner and the arithmetic runs from the top of the canvas.
    let lines = caption.components(separatedBy: "\n")
    // One size for the whole headline, chosen so its longest line clears the margin. Scaling
    // the offending line alone would be the smaller change and would look like a mistake.
    let available = canvas.width - profile.headlineMargin * 2
    let widest = lines
        .map { attributed($0, size: profile.headlineSize).size().width }
        .max() ?? 0
    let headlineSize = widest > available
        ? (profile.headlineSize * available / widest).rounded(.down)
        : profile.headlineSize
    // The grid the lines sit on stays at the profile's size even when the glyphs shrink, so the
    // device below starts at the same height in every shot and every language. Sizing the grid
    // to the fitted text instead would lift the phone a few pixels wherever French ran long,
    // and the set is looked at as a strip.
    let lineHeight = profile.headlineSize * 1.16
    for (index, line) in lines.enumerated() {
        let text = attributed(line, size: headlineSize)
        let width = text.size().width
        let bottom = canvas.height - profile.headlineTop - lineHeight * CGFloat(index + 1)
        text.draw(at: NSPoint(x: (canvas.width - width) / 2, y: bottom))
    }

    // The device. Its width is fixed by the profile and its height follows the capture's own
    // aspect, so a screenshot is never stretched to fit a frame that disagrees with it.
    let screenWidth = (canvas.width * profile.screenWidthFraction).rounded()
    let screenHeight = (screenWidth * canvas.height / canvas.width).rounded()
    let screenTop = profile.headlineTop + lineHeight * CGFloat(lines.count) + profile.headlineGap
    let screen = NSRect(
        x: ((canvas.width - screenWidth) / 2).rounded(),
        y: canvas.height - screenTop - screenHeight,
        width: screenWidth,
        height: screenHeight
    )
    let body = screen.insetBy(dx: -profile.bezel, dy: -profile.bezel)
    let screenRadius = screenWidth * profile.cornerFraction

    // Shadow on the body only: set on the fill and cleared before the screenshot goes in, or
    // every pixel of the app picks it up as a halo.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -profile.bezel * 2)
    shadow.shadowBlurRadius = profile.bezel * 4
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    bezelColor.setFill()
    NSBezierPath(
        roundedRect: body,
        xRadius: screenRadius + profile.bezel,
        yRadius: screenRadius + profile.bezel
    ).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: screenRadius, yRadius: screenRadius).addClip()
    capture.draw(
        in: screen,
        from: NSRect(origin: .zero, size: capture.size),
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Walking the tree

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("usage: frame-screenshots.swift <captures> <destination> <captions.json>")
}
let captures = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
let captionsPath = URL(fileURLWithPath: arguments[3])

guard
    let raw = try? Data(contentsOf: captionsPath),
    let parsed = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
else {
    fail("could not read captions from \(captionsPath.path)")
}
let captions = parsed.compactMapValues { $0 as? [String: String] }

let manager = FileManager.default

func directories(in url: URL) -> [URL] {
    ((try? manager.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
    )) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

var written = 0
for localeDirectory in directories(in: captures) {
    let locale = localeDirectory.lastPathComponent
    guard let localeCaptions = captions[locale] else {
        fail("captions.json says nothing about \(locale)")
    }

    for deviceDirectory in directories(in: localeDirectory) {
        let device = deviceDirectory.lastPathComponent
        guard let profile = Profile.named(device) else {
            fail("no frame is defined for the \(device) canvas")
        }

        let out = destination.appendingPathComponent(locale).appendingPathComponent(device)
        try? manager.removeItem(at: out)
        try! manager.createDirectory(at: out, withIntermediateDirectories: true)

        let shots = ((try? manager.contentsOfDirectory(
            at: deviceDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for shot in shots {
            let name = shot.deletingPathExtension().lastPathComponent
            // A shot with no headline is a shot nobody wrote copy for, and shipping it untitled
            // beside four that are titled is worse than stopping here.
            guard let caption = localeCaptions[name] else {
                fail("captions.json has no \(locale) headline for \(name)")
            }
            guard let capture = NSImage(contentsOf: shot) else {
                fail("could not read \(shot.path)")
            }

            let rep = frame(capture: capture, caption: caption, profile: profile)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                fail("could not encode \(name) for \(locale) on \(device)")
            }
            let target = out.appendingPathComponent(shot.lastPathComponent)
            try! png.write(to: target)
            print("  \(target.path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
            written += 1
        }
    }
}

if written == 0 {
    fail("there was nothing to frame in \(captures.path)")
}
