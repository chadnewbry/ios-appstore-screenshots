import AppKit
import CoreGraphics
import ImageIO

class Renderer {
    let config: ScreenshotConfig
    let projectDir: String

    init(config: ScreenshotConfig, projectDir: String) {
        self.config = config
        self.projectDir = projectDir
    }

    func renderAll() throws {
        let screenshotsDir = (projectDir as NSString).appendingPathComponent(config.screenshotsDirectory)
        let outputBaseDir = (projectDir as NSString).appendingPathComponent(config.outputDirectory)

        for device in config.devices {
            let deviceOutputDir = "\(outputBaseDir)/apple/\(config.locale)/\(device.outputDirectory)"
            try FileManager.default.createDirectory(atPath: deviceOutputDir, withIntermediateDirectories: true)

            let count = min(config.screenshotCount, config.screenshots.count)
            for i in 0..<count {
                let screenshot = config.screenshots[i]

                let imagePath: String
                if let devicePaths = screenshot.screenshotPaths, let path = devicePaths[device.name] {
                    imagePath = (screenshotsDir as NSString).appendingPathComponent(path)
                } else {
                    imagePath = (screenshotsDir as NSString).appendingPathComponent(screenshot.screenshotPath)
                }

                guard let screenshotImage = loadImage(at: imagePath) else {
                    print("Warning: Could not load screenshot at \(imagePath), skipping")
                    continue
                }

                guard let image = renderScreenshot(screenshot: screenshot, device: device, screenshotImage: screenshotImage) else {
                    print("Error: Failed to render screenshot \(i + 1) for \(device.name)")
                    continue
                }

                let outputPath = "\(deviceOutputDir)/\(String(format: "%02d", i + 1)).png"
                try saveImage(image, to: outputPath)
                print("Generated: \(outputPath)")
            }
        }
    }

    // MARK: - Main Render Pipeline

    func renderScreenshot(
        screenshot: ScreenshotConfig.ScreenshotEntry,
        device: ScreenshotConfig.DeviceConfig,
        screenshotImage: CGImage
    ) -> CGImage? {
        let width = device.outputWidth
        let height = device.outputHeight

        // Create offscreen bitmap (NSBitmapImageRep for proper emoji support)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("Failed to create bitmap rep")
            return nil
        }

        guard let bitmapNSContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            print("Failed to create NSGraphicsContext")
            return nil
        }

        // Get the underlying CGContext and flip it to top-left origin
        let ctx = bitmapNSContext.cgContext
        let canvasWidth = CGFloat(width)
        let canvasHeight = CGFloat(height)

        ctx.translateBy(x: 0, y: canvasHeight)
        ctx.scaleBy(x: 1, y: -1)

        // Create a new NSGraphicsContext that knows the CGContext is flipped.
        // This is critical: NSAttributedString.draw() checks isFlipped to
        // determine text orientation. Without this, text renders upside down.
        let flippedNSContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flippedNSContext

        // 1. Gradient background
        drawGradient(ctx: ctx, width: canvasWidth, height: canvasHeight)

        // 2. Layout calculations
        let topPadding = canvasHeight * CGFloat(config.theme.topPaddingFraction)
        let headerFontSize = canvasWidth * CGFloat(config.theme.headerFontSizeFraction)
        let subtitleFontSize = canvasWidth * CGFloat(config.theme.subtitleFontSizeFraction)

        var currentY = topPadding

        // 3. Header pill
        currentY = drawHeaderPill(
            header: screenshot.header,
            y: currentY,
            canvasWidth: canvasWidth,
            fontSize: headerFontSize
        )

        // 4. Subtitle
        if let subtitle = screenshot.subtitle, !subtitle.isEmpty {
            currentY += canvasHeight * CGFloat(config.theme.pillSubtitleGapFraction)
            currentY = drawSubtitle(
                subtitle: subtitle,
                y: currentY,
                canvasWidth: canvasWidth,
                fontSize: subtitleFontSize
            )
        }

        // 5. Device frame with screenshot
        currentY += canvasHeight * CGFloat(config.theme.subtitleDeviceGapFraction)
        drawDevice(
            ctx: ctx,
            device: device,
            screenshotImage: screenshotImage,
            topY: currentY,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )

        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Gradient

    private func drawGradient(ctx: CGContext, width: CGFloat, height: CGFloat) {
        let topColor = NSColor.fromHex(config.theme.gradientTopColor).cgColor
        let bottomColor = NSColor.fromHex(config.theme.gradientBottomColor).cgColor

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [topColor, bottomColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: width / 2, y: 0),
            end: CGPoint(x: width / 2, y: height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // MARK: - Header Pill

    private func drawHeaderPill(header: String, y: CGFloat, canvasWidth: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let textColor = NSColor.fromHex(config.theme.pillTextColor)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attrString = NSAttributedString(string: header, attributes: attrs)
        let textSize = attrString.size()

        let hPadding = fontSize * 0.8
        let vPadding = fontSize * 0.4

        let pillWidth = textSize.width + hPadding * 2
        let pillHeight = textSize.height + vPadding * 2
        let pillX = (canvasWidth - pillWidth) / 2
        let pillCornerRadius = pillHeight * CGFloat(config.theme.pillCornerRadiusFraction)

        // Pill background
        let pillRect = NSRect(x: pillX, y: y, width: pillWidth, height: pillHeight)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillCornerRadius, yRadius: pillCornerRadius)
        NSColor.fromHex(config.theme.pillColor).setFill()
        pillPath.fill()

        // Text centered in pill
        let textX = pillX + (pillWidth - textSize.width) / 2
        let textY = y + (pillHeight - textSize.height) / 2
        attrString.draw(at: NSPoint(x: textX, y: textY))

        return y + pillHeight
    }

    // MARK: - Subtitle

    private func drawSubtitle(subtitle: String, y: CGFloat, canvasWidth: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = fontSize * 0.1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.fromHex(config.theme.subtitleColor),
            .paragraphStyle: style
        ]
        let attrString = NSAttributedString(string: subtitle, attributes: attrs)

        let maxWidth = canvasWidth * CGFloat(config.theme.subtitleMaxWidthFraction)

        let boundingRect = attrString.boundingRect(
            with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let drawRect = NSRect(
            x: (canvasWidth - maxWidth) / 2,
            y: y,
            width: maxWidth,
            height: ceil(boundingRect.height)
        )
        attrString.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        return y + ceil(boundingRect.height)
    }

    // MARK: - Device Frame

    private func drawDevice(
        ctx: CGContext,
        device: ScreenshotConfig.DeviceConfig,
        screenshotImage: CGImage,
        topY: CGFloat,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) {
        let deviceWidth = canvasWidth * CGFloat(device.deviceWidthFraction)
        let bezelWidth = deviceWidth * CGFloat(device.bezelWidthFraction)
        let outerCornerRadius = deviceWidth * CGFloat(device.frameCornerRadiusFraction)
        let innerCornerRadius = max(outerCornerRadius - bezelWidth, 0)

        // Screen area inside bezel
        let screenWidth = deviceWidth - 2 * bezelWidth
        let screenHeight = screenWidth * CGFloat(device.screenAspectRatio)
        let deviceHeight = screenHeight + 2 * bezelWidth

        // Center horizontally
        let deviceX = (canvasWidth - deviceWidth) / 2

        let deviceRect = CGRect(x: deviceX, y: topY, width: deviceWidth, height: deviceHeight)
        let screenRect = CGRect(
            x: deviceX + bezelWidth,
            y: topY + bezelWidth,
            width: screenWidth,
            height: screenHeight
        )

        // Shadow
        ctx.saveGState()
        let shadowColor = CGColor(gray: 0, alpha: CGFloat(config.theme.shadowOpacity))
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: CGFloat(config.theme.shadowBlur), color: shadowColor)

        // Outer bezel
        let outerPath = CGPath(
            roundedRect: deviceRect,
            cornerWidth: outerCornerRadius,
            cornerHeight: outerCornerRadius,
            transform: nil
        )
        ctx.setFillColor(NSColor.fromHex(config.theme.deviceFrameColor).cgColor)
        ctx.addPath(outerPath)
        ctx.fillPath()

        ctx.restoreGState()

        // Inner screen area - clip and draw screenshot
        ctx.saveGState()

        let innerPath = CGPath(
            roundedRect: screenRect,
            cornerWidth: innerCornerRadius,
            cornerHeight: innerCornerRadius,
            transform: nil
        )
        ctx.addPath(innerPath)
        ctx.clip()

        // Scale screenshot to fill screen width, aligned to top
        let screenshotAspect = CGFloat(screenshotImage.width) / CGFloat(screenshotImage.height)
        let screenAspect = screenWidth / screenHeight

        let drawRect: CGRect
        if screenshotAspect > screenAspect {
            // Screenshot is wider - fit height, center horizontally
            let drawHeight = screenHeight
            let drawWidth = drawHeight * screenshotAspect
            let drawX = screenRect.minX + (screenWidth - drawWidth) / 2
            drawRect = CGRect(x: drawX, y: screenRect.minY, width: drawWidth, height: drawHeight)
        } else {
            // Screenshot is taller or equal - fit width, align to top (bottom crops)
            let drawWidth = screenWidth
            let drawHeight = drawWidth / screenshotAspect
            drawRect = CGRect(x: screenRect.minX, y: screenRect.minY, width: drawWidth, height: drawHeight)
        }

        // Draw screenshot using CGContext.draw() with local flip.
        // CGContext.draw() renders images "right side up" relative to the default
        // (bottom-left) coordinate system, so in our globally-flipped context we
        // need to locally un-flip for the image to appear correctly.
        ctx.saveGState()
        ctx.translateBy(x: drawRect.minX, y: drawRect.minY + drawRect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(screenshotImage, in: CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height))
        ctx.restoreGState()

        ctx.restoreGState()
    }

    // MARK: - Image I/O

    private func loadImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func saveImage(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            throw RendererError.failedToCreateDestination(path)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw RendererError.failedToWriteImage(path)
        }
    }
}

enum RendererError: Error, LocalizedError {
    case failedToCreateDestination(String)
    case failedToWriteImage(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateDestination(let path):
            return "Failed to create image destination at \(path)"
        case .failedToWriteImage(let path):
            return "Failed to write image to \(path)"
        }
    }
}
