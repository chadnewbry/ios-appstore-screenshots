import Foundation

struct ScreenshotConfig: Codable {
    var screenshotCount: Int
    var locale: String
    var outputDirectory: String
    var screenshotsDirectory: String
    var theme: Theme
    var screenshots: [ScreenshotEntry]
    var devices: [DeviceConfig]

    struct Theme: Codable {
        var gradientTopColor: String
        var gradientBottomColor: String
        var pillColor: String
        var pillTextColor: String
        var subtitleColor: String
        var deviceFrameColor: String
        var headerFontSizeFraction: Double
        var subtitleFontSizeFraction: Double
        var topPaddingFraction: Double
        var subtitleMaxWidthFraction: Double
        var shadowBlur: Double
        var shadowOpacity: Double
        var pillCornerRadiusFraction: Double
        var pillSubtitleGapFraction: Double
        var subtitleDeviceGapFraction: Double
    }

    struct ScreenshotEntry: Codable {
        var header: String
        var subtitle: String?
        var screenshotPath: String
        var screenshotPaths: [String: String]?
    }

    struct DeviceConfig: Codable {
        var name: String
        var outputWidth: Int
        var outputHeight: Int
        var outputDirectory: String
        var deviceWidthFraction: Double
        var screenAspectRatio: Double
        var frameCornerRadiusFraction: Double
        var bezelWidthFraction: Double
    }

    static func load(from path: String) throws -> ScreenshotConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(ScreenshotConfig.self, from: data)
    }

    static func defaultConfig() -> ScreenshotConfig {
        return ScreenshotConfig(
            screenshotCount: 4,
            locale: "en-US",
            outputDirectory: "App-Store-Screenshots",
            screenshotsDirectory: "screenshots",
            theme: Theme(
                gradientTopColor: "#FFF5F8",
                gradientBottomColor: "#FFE0EB",
                pillColor: "#FFB6C1",
                pillTextColor: "#000000",
                subtitleColor: "#000000",
                deviceFrameColor: "#1C1C1E",
                headerFontSizeFraction: 0.053,
                subtitleFontSizeFraction: 0.066,
                topPaddingFraction: 0.07,
                subtitleMaxWidthFraction: 0.85,
                shadowBlur: 25,
                shadowOpacity: 0.15,
                pillCornerRadiusFraction: 0.16,
                pillSubtitleGapFraction: 0.035,
                subtitleDeviceGapFraction: 0.08
            ),
            screenshots: [
                ScreenshotEntry(header: "✨ Feature One", subtitle: "A great feature of your app", screenshotPath: "01.png"),
                ScreenshotEntry(header: "🚀 Feature Two", subtitle: "Another great feature", screenshotPath: "02.png"),
                ScreenshotEntry(header: "💡 Feature Three", subtitle: "Yet another feature", screenshotPath: "03.png"),
                ScreenshotEntry(header: "🎯 Feature Four", subtitle: "The best feature", screenshotPath: "04.png")
            ],
            devices: [
                DeviceConfig(
                    name: "iPhone 6.5",
                    outputWidth: 1242,
                    outputHeight: 2688,
                    outputDirectory: "iPhone 6.5",
                    deviceWidthFraction: 0.75,
                    screenAspectRatio: 2.1643,
                    frameCornerRadiusFraction: 0.13,
                    bezelWidthFraction: 0.016
                ),
                DeviceConfig(
                    name: "iPad 13",
                    outputWidth: 2064,
                    outputHeight: 2752,
                    outputDirectory: "iPad 13",
                    deviceWidthFraction: 0.82,
                    screenAspectRatio: 1.3333,
                    frameCornerRadiusFraction: 0.045,
                    bezelWidthFraction: 0.008
                )
            ]
        )
    }
}
