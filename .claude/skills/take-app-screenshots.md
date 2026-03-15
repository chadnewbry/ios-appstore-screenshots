# Skill: Take App Screenshots with Maestro

This skill automates capturing iOS app screenshots using Maestro. It works for any iOS app by dynamically discovering the app's UI structure from source code and generating a Maestro flow to capture screenshots from each key screen.

## Prerequisites

- A booted iOS Simulator with the app installed
- Maestro CLI installed (`brew install maestro` or https://maestro.mobile.dev)
- The ios-appstore-screenshots tool (ScreenshotGenerator) built if you want final marketing screenshots

## Step 1: Discover the App's UI Structure

Read the app's source code to identify:

### Find the bundle identifier

Search for the bundle ID in these locations (check in order):
1. `*.xcodeproj/project.pbxproj` — look for `PRODUCT_BUNDLE_IDENTIFIER`
2. `*.plist` files — look for `CFBundleIdentifier`
3. `Project.swift` (Tuist) or `Package.swift` — look for bundle ID configuration
4. Ask the user if it cannot be determined

### Identify the main navigation pattern

Search the source code for the app's navigation structure. Look for these patterns:

**SwiftUI apps:**
- `TabView` with `tabItem` or `.tab(` modifiers — each tab is a key screen
- `NavigationStack` / `NavigationView` — identify the root views
- `TabView` with `selection` binding — note the tab identifiers
- `.tag(` values on tab content for tab identification

**UIKit apps:**
- `UITabBarController` — each `viewControllers` entry is a key screen
- `UINavigationController` — identify root view controllers
- Storyboard files (`.storyboard`) — look for tab bar controllers and their connected scenes

**For each screen found, record:**
- A human-readable name (e.g., "Home", "Settings", "Profile")
- The tab label text or accessibility identifier used in the UI
- Whether it requires any setup (e.g., logged-in state, sample data)

### Identify any onboarding or modals

Check if the app has:
- An onboarding flow that appears on first launch (look for `UserDefaults` keys like `hasSeenOnboarding`, `isFirstLaunch`, etc.)
- Login screens that might block navigation
- Permission dialogs (notifications, location, etc.)

## Step 2: Generate the Maestro Flow YAML

Based on what you discovered, generate a Maestro flow YAML file. Save it to the app project directory as `maestro/capture-screenshots.yaml`.

Use this structure as a template:

```yaml
appId: <BUNDLE_ID>
name: "Capture App Store Screenshots"
---

# Launch the app fresh
- launchApp:
    appId: <BUNDLE_ID>
    clearState: true

# Handle any onboarding if present
# (Add steps here based on what you found — tap through onboarding screens,
#  dismiss permission dialogs, etc.)

# Wait for main UI to settle
- waitForAnimationToEnd

# Screenshot 1: First tab / Home screen
- takeScreenshot: "01-home"

# Screenshot 2: Navigate to second tab
- tapOn: "<SECOND_TAB_LABEL>"
- waitForAnimationToEnd
- takeScreenshot: "02-<screen-name>"

# Screenshot 3: Navigate to third tab
- tapOn: "<THIRD_TAB_LABEL>"
- waitForAnimationToEnd
- takeScreenshot: "03-<screen-name>"

# Continue for each key screen...
```

### Maestro command reference for screenshot flows

- `launchApp:` — launch or relaunch the app. Use `clearState: true` for a fresh start.
- `tapOn:` — tap an element. Accepts a string (matches text label), or an object with `id:` (accessibility identifier) or `text:`.
- `waitForAnimationToEnd` — wait for all animations to finish before proceeding.
- `takeScreenshot: "<name>"` — capture a screenshot. Saved to `~/.maestro/tests/<timestamp>/` directory.
- `scrollUntilVisible:` — scroll until an element is visible. Useful for content below the fold.
- `swipe:` — swipe in a direction. Values: `LEFT`, `RIGHT`, `UP`, `DOWN`.
- `assertVisible:` — assert an element is on screen. Use to verify navigation succeeded.
- `inputText:` — type text into a focused field.
- `hideKeyboard` — dismiss the software keyboard.
- `back` — press the back button.
- `waitForAnimationToEnd` — useful after every navigation action.

### Tips for the generated flow

- Always add `waitForAnimationToEnd` after navigation actions and before `takeScreenshot`.
- If the app has an onboarding flow, add steps to complete or dismiss it before capturing screenshots.
- For permission dialogs, use `tapOn: "Allow"` or `tapOn: "Don't Allow"` as needed.
- If a screen needs sample data to look good, note this as a comment — the user may need to set up data manually.
- Name screenshots with a numeric prefix and descriptive name: `01-home`, `02-explore`, `03-profile`.

## Step 3: Run the Maestro Flow

Before running, ensure:
1. An iOS Simulator is booted (check with `xcrun simctl list devices | grep Booted`)
2. The app is installed on the simulator

Run the flow:

```bash
export PATH="$PATH":"$HOME/.maestro/bin"
maestro test maestro/capture-screenshots.yaml
```

If the test fails:
- Read the error output carefully
- Common issues: element not found (check label text), timing (add `waitForAnimationToEnd` or `extendedWaitUntil`), wrong bundle ID
- Fix the YAML and re-run

## Step 4: Move Screenshots to the Inputs Directory

Maestro's `takeScreenshot` saves PNG files to the **current working directory** (the app project root). After a successful run, move them into the `App-Store-Screenshots/inputs/` folder so they're ready for the ScreenshotGenerator.

1. Find the screenshots Maestro just created in the project root (they'll be named like `01-home.png`, `02-library.png`, etc.).
2. Determine the correct input directory:
   - If `App-Store-Screenshots/screenshot-config.json` exists, check its `screenshotsDirectory` field for a custom input path. The inputs folder is `App-Store-Screenshots/<screenshotsDirectory>/` (default: `App-Store-Screenshots/inputs/`).
   - If no config exists yet, use `App-Store-Screenshots/inputs/` as the default.
3. Create the directory if it doesn't exist and move the screenshots there.

```bash
# Move Maestro screenshots from project root to inputs folder
INPUT_DIR="App-Store-Screenshots/inputs"
mkdir -p "$INPUT_DIR"
mv *.png "$INPUT_DIR/" 2>/dev/null
ls -la "$INPUT_DIR/"
```

4. If `screenshot-config.json` already has `screenshotPath` entries, rename the files to match. Otherwise, update the config to reference the new filenames (e.g., `01-home.png`, `02-library.png`).

## Step 5 (Optional): Generate Marketing Screenshots

If the user wants to produce final App Store marketing screenshots with device frames and text overlays:

1. Ensure `screenshot-config.json` is set up with the correct `screenshotPath` values matching the captured screenshot filenames.
2. Run the ScreenshotGenerator:

```bash
# Build if needed
cd /path/to/ios-appstore-screenshots
swift build -c release

# Generate marketing screenshots
.build/release/ScreenshotGenerator --project-dir /path/to/app/project
```

The final screenshots land in `App-Store-Screenshots/apple/en-US/iPhone 6.5/` and `iPad 13/`.

## Summary of What This Skill Does

1. Reads the app source code to discover screens and navigation
2. Generates a custom Maestro YAML flow for that specific app
3. Runs Maestro to capture screenshots from a booted simulator
4. Copies captured screenshots into the project's input directory
5. Optionally generates final marketing screenshots with the ScreenshotGenerator tool
