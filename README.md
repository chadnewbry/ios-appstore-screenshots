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

After a successful run, the generator can prompt you to open an automatic GitHub pull request that adds your setup as a reusable template on the public website.

## Templates

Templates live in the website repo and can be installed by template ID.

```bash
.build/release/ScreenshotGenerator \
  --project-dir /path/to/your/project \
  --template-id soft-gradient-demo
```

This downloads the template config and any packaged source screenshots into `App-Store-Screenshots/` before generation.

### Template Contribution Flow

When generation succeeds in an interactive terminal, the tool prompts:

- whether you want to share your template
- and, if you say yes, it uses your authenticated `gh` session to fork, branch, commit, and open a pull request automatically

The submitted template package includes:

- `config.json`
- optional source screenshots
- generated output images
- `template.json` manifest metadata

Use `--skip-template-prompt` if you want to suppress the contribution prompt.

## Configuration

`screenshot-config.json` controls everything:

```json
{
  "screenshotCount": 4,
  "locale": "en-US",
  "outputDirectory": "App-Store-Screenshots",
  "screenshotsDirectory": "inputs",
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

## Automated Screenshot Capture with Maestro

Instead of manually taking screenshots from the simulator, you can use [Maestro](https://maestro.mobile.dev) to automate the entire capture process.

### Setup

1. Install Maestro:

```bash
brew install maestro
```

2. Ensure the Maestro CLI is on your PATH:

```bash
export PATH="$PATH":"$HOME/.maestro/bin"
```

3. Boot an iOS Simulator and install your app.

### Using the Claude Skill (Recommended)

This repo includes a Claude skill at `.claude/skills/take-app-screenshots.md` that can be referenced from any iOS app project. When invoked, it will:

1. Read your app's source code to discover the navigation structure (TabView, UITabBarController, etc.)
2. Generate a custom Maestro flow YAML tailored to your app's screens
3. Run the Maestro flow against a booted simulator to capture screenshots
4. Copy the captured screenshots into your `App-Store-Screenshots/inputs/` directory
5. Optionally run the ScreenshotGenerator to produce final marketing screenshots

This works for both SwiftUI and UIKit apps. The skill dynamically adapts to whatever navigation pattern your app uses.

### Using the Template Manually

A reference Maestro flow template is available at `maestro/template-flow.yaml`. You can copy and customize it for your app:

```bash
cp maestro/template-flow.yaml /path/to/your/app/maestro/capture-screenshots.yaml
# Edit the file: set your bundle ID, tab labels, and screen names
maestro test /path/to/your/app/maestro/capture-screenshots.yaml
```

After Maestro runs, screenshots are saved under `~/.maestro/tests/`. Copy them to your project's `App-Store-Screenshots/inputs/` directory, then run the generator.

## Requirements

- macOS 13+
- Swift 5.9+
- [Maestro](https://maestro.mobile.dev) (optional, for automated screenshot capture)

## License

MIT
