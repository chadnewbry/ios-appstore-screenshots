import Foundation
import AppKit

// Bootstrap AppKit for headless emoji/font rendering
let _ = NSApplication.shared

func printUsage() {
    print("""
    Usage: ios-appstore-screenshots --project-dir <path> [--config <path>] [--template-id <id>]
           ios-appstore-screenshots --init --project-dir <path>

    Options:
      --project-dir   Path to the project directory containing screenshots
      --config        Path to config file (default: <project-dir>/screenshot-config.json)
      --template-id   Download a template config and source screenshots before generating
      --template-source Base URL for template data (default: official website repo)
      --init          Generate a default config file in the project directory
      --skip-template-prompt Skip the post-generation GitHub template submission prompt
      --help, -h      Show this help message
    """)
}

func parseArgs() -> (
    projectDir: String,
    configPath: String?,
    shouldInit: Bool,
    templateId: String?,
    templateSource: String,
    skipTemplatePrompt: Bool
) {
    let args = CommandLine.arguments
    var projectDir: String?
    var configPath: String?
    var shouldInit = false
    var templateId: String?
    var templateSource = TemplateSupport.templateSourceBaseURL
    var skipTemplatePrompt = false

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--project-dir":
            i += 1
            if i < args.count { projectDir = args[i] }
        case "--config":
            i += 1
            if i < args.count { configPath = args[i] }
        case "--template-id":
            i += 1
            if i < args.count { templateId = args[i] }
        case "--template-source":
            i += 1
            if i < args.count { templateSource = args[i] }
        case "--init":
            shouldInit = true
        case "--skip-template-prompt":
            skipTemplatePrompt = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            print("Unknown argument: \(args[i])")
            printUsage()
            exit(1)
        }
        i += 1
    }

    guard let dir = projectDir else {
        print("Error: --project-dir is required")
        printUsage()
        exit(1)
    }

    return (dir, configPath, shouldInit, templateId, templateSource, skipTemplatePrompt)
}

// MARK: - Main

let (projectDir, configPathOverride, shouldInit, templateId, templateSource, skipTemplatePrompt) = parseArgs()

let resolvedProjectDir: String
if projectDir.hasPrefix("/") {
    resolvedProjectDir = projectDir
} else {
    resolvedProjectDir = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(projectDir)
}

let appStoreDir = (resolvedProjectDir as NSString).appendingPathComponent("App-Store-Screenshots")

if shouldInit {
    let configPath = (appStoreDir as NSString).appendingPathComponent("screenshot-config.json")
    if FileManager.default.fileExists(atPath: configPath) {
        print("Config already exists at \(configPath)")
        print("Delete it first if you want to regenerate.")
        exit(1)
    }

    try? FileManager.default.createDirectory(atPath: appStoreDir, withIntermediateDirectories: true)

    let defaultConfig = ScreenshotConfig.defaultConfig()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(defaultConfig)
        try data.write(to: URL(fileURLWithPath: configPath))
    } catch {
        print("Error writing config: \(error)")
        exit(1)
    }

    let screenshotsDir = (appStoreDir as NSString).appendingPathComponent("inputs")
    try? FileManager.default.createDirectory(atPath: screenshotsDir, withIntermediateDirectories: true)

    print("Created: \(configPath)")
    print("Created: \(screenshotsDir)/")
    print("")
    print("Next steps:")
    print("  1. Add your raw app screenshots to App-Store-Screenshots/inputs/")
    print("  2. Edit App-Store-Screenshots/screenshot-config.json with your headlines and colors")
    print("  3. Run: ios-appstore-screenshots --project-dir \(projectDir)")
    exit(0)
}

// Look for config in App-Store-Screenshots/ first, fall back to project root
let defaultConfigPath: String
let appStoreDirConfig = (appStoreDir as NSString).appendingPathComponent("screenshot-config.json")
let rootConfig = (resolvedProjectDir as NSString).appendingPathComponent("screenshot-config.json")
if FileManager.default.fileExists(atPath: appStoreDirConfig) {
    defaultConfigPath = appStoreDirConfig
} else {
    defaultConfigPath = rootConfig
}
let configPath = configPathOverride ?? defaultConfigPath

if let templateId {
    do {
        let installedConfigURL = try TemplateSupport.installTemplate(
            templateId: templateId,
            projectDir: resolvedProjectDir,
            templateSourceBaseURL: templateSource
        )
        print("Installed template \(templateId) to \(installedConfigURL.path)")
    } catch {
        print("Error installing template: \(error.localizedDescription)")
        exit(1)
    }
}

guard FileManager.default.fileExists(atPath: configPath) else {
    print("Error: Config not found at \(configPath)")
    print("Run with --init to create a default config:")
    print("  ios-appstore-screenshots --init --project-dir \(projectDir)")
    exit(1)
}

do {
    let config = try ScreenshotConfig.load(from: configPath)
    print("Loaded config: \(config.screenshots.count) screenshots, \(config.devices.count) devices")
    print("Generating up to \(config.screenshotCount) screenshots per device...\n")

    let configDir = (configPath as NSString).deletingLastPathComponent
    let renderer = Renderer(config: config, projectDir: resolvedProjectDir, configDir: configDir)
    try renderer.renderAll()

    print("\nDone! Screenshots saved to \(resolvedProjectDir)/\(config.outputDirectory)/")

    if skipTemplatePrompt {
        TemplateSupport.printContributionMessage()
    } else if TemplateSupport.promptForSubmission() {
        do {
            let bundle = try TemplateSupport.buildSubmissionBundle(projectDir: resolvedProjectDir, configPath: configPath)
            let pullRequestURL = try TemplateSupport.submitTemplate(bundle: bundle)
            print("Opened template PR: \(pullRequestURL.absoluteString)")
        } catch {
            print("Template submission skipped: \(error.localizedDescription)")
        }
    } else {
        TemplateSupport.printContributionMessage()
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
