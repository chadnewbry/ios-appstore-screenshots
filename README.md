# App Store Screenshot Generator

A Swift CLI tool that programmatically generates App Store Connect-ready marketing screenshots. Takes your raw app screenshots and wraps them with gradient backgrounds, header pills with emoji, subtitle text, and device frames.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Output

Each screenshot is rendered at the exact pixel dimensions required by App Store Connect:

- **iPhone 6.5"** - 1242 x 2688
- **iPad 13"** - 2064 x 2752

Screenshots include:
- Configurable gradient background
- Rounded header pill with emoji support
- Bold subtitle text
- Device frame with your app screenshot inside

## Install

```bash
git clone https://github.com/chadnewbry/ios-appstore-screenshots.git
cd ios-appstore-screenshots
swift build -c release
```

The binary is at `.build/release/ScreenshotGenerator`.

## Quick Start

**1. Initialize a config in your project:**

```bash
.build/release/ScreenshotGenerator --init --project-dir /path/to/your/project
```

This creates:
- `App-Store-Screenshots/screenshot-config.json` - configuration file
- `App-Store-Screenshots/inputs/` - place your raw screenshots here

**2. Add your raw app screenshots** to the `inputs/` directory.

**3. Edit the config** to set your headlines, colors, and screenshot filenames.

**4. Generate:**

```bash
.build/release/ScreenshotGenerator --project-dir /path/to/your/project
```

Output lands in `App-Store-Screenshots/apple/en-US/iPhone 6.5/` and `iPad 13/`.

## Configuration

`screenshot-config.json` controls everything:

```json
{
  "screenshotCount": 4,
  "locale": "en-US",
  "outputDirectory": "App-Store-Screenshots",
  "screenshotsDirectory": "screenshots",
  "theme": {
    "gradientTopColor": "#FFF5F8",
    "gradientBottomColor": "#FFE0EB",
    "pillColor": "#FFB6C1",
    "pillTextColor": "#000000",
    "subtitleColor": "#000000",
    "deviceFrameColor": "#1C1C1E",
    "headerFontSizeFraction": 0.038,
    "subtitleFontSizeFraction": 0.035
  },
  "screenshots": [
    {
      "header": "✨ Feature One",
      "subtitle": "A great feature of your app",
      "screenshotPath": "01.png"
    }
  ],
  "devices": [
    {
      "name": "iPhone 6.5",
      "outputWidth": 1242,
      "outputHeight": 2688,
      "outputDirectory": "iPhone 6.5",
      "deviceWidthFraction": 0.75,
      "screenAspectRatio": 2.1643,
      "frameCornerRadiusFraction": 0.13,
      "bezelWidthFraction": 0.016
    }
  ]
}
```

### Theme Options

| Key | Description |
|-----|-------------|
| `gradientTopColor` / `gradientBottomColor` | Background gradient (hex) |
| `pillColor` / `pillTextColor` | Header pill appearance |
| `subtitleColor` | Subtitle text color |
| `deviceFrameColor` | Device bezel color |
| `headerFontSizeFraction` | Header font size as fraction of canvas width |
| `subtitleFontSizeFraction` | Subtitle font size as fraction of canvas width |
| `shadowBlur` / `shadowOpacity` | Drop shadow on device frame |

### Per-Device Screenshot Paths

If your iPhone and iPad screenshots are different files, use `screenshotPaths` instead of `screenshotPath`:

```json
{
  "header": "✨ Feature",
  "subtitle": "Description",
  "screenshotPaths": {
    "iPhone 6.5": "feature-iphone.png",
    "iPad 13": "feature-ipad.png"
  }
}
```

## Requirements

- macOS 13+
- Swift 5.9+
- No external dependencies

## License

MIT
