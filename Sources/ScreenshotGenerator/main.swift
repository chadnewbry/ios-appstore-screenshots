import Foundation
import AppKit

// Bootstrap AppKit for headless emoji/font rendering
let _ = NSApplication.shared

enum CLICommand: String {
    case generate
    case regenerate
    case captureInputs = "capture-inputs"
    case initialize = "init"
    case initMaestro = "init-maestro"
    case help
}

struct CLIOptions {
    var command: CLICommand
    var projectDir: String
    var configPath: String?
    var templateId: String?
    var templateSource: String
    var skipTemplatePrompt: Bool
    var locale: String? = nil
    var allLocales: Bool = false
}

enum CLIParseError: Error, LocalizedError {
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

func printUsage() {
    print("""
    Usage: ios-appstore-screenshots <command> [options]
           ios-appstore-screenshots [options]

    Commands:
      generate         Generate final App Store screenshots. If inputs are missing and a Maestro flow exists, run capture first.
      regenerate       Force Maestro capture, then regenerate final screenshots.
      capture-inputs   Run Maestro and move captured PNGs into App-Store-Screenshots/inputs/.
      init             Create a default screenshot config and inputs directory.
      init-maestro     Create a starter maestro/capture-screenshots.yaml flow if one does not exist.
      help             Show this help message.

    Options:
      --project-dir   Path to the project directory containing screenshots (default: current directory)
      --config        Path to config file (default: App-Store-Screenshots/screenshot-config.json)
      --template-id   Download a template config and source screenshots before generating
      --template-source Base URL for template data (default: official website repo)
      --skip-template-prompt Skip the post-generation GitHub template submission prompt
      --locale <code> Operate on a single language variant from config.locales (e.g. de-DE).
                      With capture-inputs: relaunch the app in that language via Maestro.
                      With generate: frame inputs/<code>/ using that locale's captions → output/<code>/.
      --all-locales   Same as --locale but for every entry in config.locales (loops all languages).
      --help, -h      Show this help message

    Localized screenshots (per-language):
      1. Add a `locales` array to the config: each { code, appleLanguages, screenshots:[{header,subtitle}] }.
      2. Make the Maestro flow force language: launchApp arguments -AppleLanguages: "${APPLE_LANGUAGES}".
      3. Capture:  ios-appstore-screenshots capture-inputs --all-locales
      4. Generate: ios-appstore-screenshots generate --all-locales
      Requires the app itself to be localized (String Catalog) so the UI renders in each language.
    """)
}

func parseArgs(_ args: [String]) throws -> CLIOptions {
    var command: CLICommand = .generate
    var projectDir: String?
    var configPath: String?
    var templateId: String?
    var templateSource = TemplateSupport.templateSourceBaseURL
    var skipTemplatePrompt = false
    var locale: String? = nil
    var allLocales = false

    var i = 1
    while i < args.count {
        if !args[i].hasPrefix("--"), let parsedCommand = CLICommand(rawValue: args[i]) {
            command = parsedCommand
            i += 1
            continue
        }

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
            command = .initialize
        case "--skip-template-prompt":
            skipTemplatePrompt = true
        case "--locale":
            i += 1
            if i < args.count { locale = args[i] }
        case "--all-locales":
            allLocales = true
        case "--help", "-h":
            command = .help
        default:
            throw CLIParseError.unknownArgument(args[i])
        }
        i += 1
    }

    return CLIOptions(
        command: command,
        projectDir: projectDir ?? ".",
        configPath: configPath,
        templateId: templateId,
        templateSource: templateSource,
        skipTemplatePrompt: skipTemplatePrompt,
        locale: locale,
        allLocales: allLocales
    )
}

func parseArgs() -> CLIOptions {
    do {
        return try parseArgs(CommandLine.arguments)
    } catch {
        print(error.localizedDescription)
        printUsage()
        exit(1)
    }
}

// MARK: - Main

let options = parseArgs()

if options.command == .help {
    printUsage()
    exit(0)
}

let resolvedProjectDir: String
if options.projectDir.hasPrefix("/") {
    resolvedProjectDir = options.projectDir
} else {
    resolvedProjectDir = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(options.projectDir)
}

let appStoreDir = (resolvedProjectDir as NSString).appendingPathComponent("App-Store-Screenshots")

if options.command == .initialize {
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
    print("  3. Run: ios-appstore-screenshots generate")
    exit(0)
}

if options.command == .initMaestro {
    do {
        let flowURL = try MaestroSupport.initFlowIfNeeded(projectDir: resolvedProjectDir)
        print("Maestro flow ready at \(flowURL.path)")
        exit(0)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
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
var configPath = options.configPath ?? defaultConfigPath

if let templateId = options.templateId {
    do {
        let installedConfigURL = try TemplateSupport.installTemplate(
            templateId: templateId,
            projectDir: resolvedProjectDir,
            templateSourceBaseURL: options.templateSource
        )
        configPath = installedConfigURL.path
        print("Installed template \(templateId) to \(installedConfigURL.path)")
    } catch {
        print("Error installing template: \(error.localizedDescription)")
        exit(1)
    }
}

func hasInputImages(projectDir: String, configPath: String?) -> Bool {
    let appStoreURL = URL(fileURLWithPath: projectDir, isDirectory: true)
        .appendingPathComponent("App-Store-Screenshots", isDirectory: true)
    let inputsDirectory: URL
    if let configPath,
       let config = try? ScreenshotConfig.load(from: configPath) {
        if config.screenshotsDirectory.hasPrefix("/") {
            inputsDirectory = URL(fileURLWithPath: config.screenshotsDirectory, isDirectory: true)
        } else {
            inputsDirectory = appStoreURL.appendingPathComponent(config.screenshotsDirectory, isDirectory: true)
        }
    } else {
        inputsDirectory = appStoreURL.appendingPathComponent("inputs", isDirectory: true)
    }

    guard let files = try? FileManager.default.contentsOfDirectory(atPath: inputsDirectory.path) else {
        return false
    }
    return files.contains { $0.lowercased().hasSuffix(".png") }
}

func runCaptureInputs(projectDir: String, configPath: String?, locale: String? = nil, appleLanguages: String? = nil) {
    do {
        try MaestroSupport.captureInputs(projectDir: projectDir, configPath: configPath, locale: locale, appleLanguages: appleLanguages)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Capture raw screenshots for one or more languages. With --all-locales /
// --locale, relaunch the app per language (via Maestro launch args) so each
// captured screen renders localized, routed into inputs/<code>/.
func runLocalizedCapture(projectDir: String, configPath: String, locale: String?, allLocales: Bool) {
    guard let config = try? ScreenshotConfig.load(from: configPath), let variants = config.locales, !variants.isEmpty else {
        print("Error: --locale/--all-locales capture needs a `locales` array in \(configPath).")
        exit(1)
    }
    let selected = variants.filter { locale == nil || $0.code == locale }
    guard !selected.isEmpty else {
        print("Error: no locale variant\(locale.map { " matching \($0)" } ?? "") in config.locales.")
        exit(1)
    }
    for v in selected {
        print("\n[capture:\(v.code)] launching app with AppleLanguages=\(v.appleLanguages ?? "(unset)") ...")
        runCaptureInputs(projectDir: projectDir, configPath: configPath, locale: v.code, appleLanguages: v.appleLanguages)
    }
    print("\nCaptured raw screenshots for \(selected.count) locale(s). Now run: generate \(allLocales ? "--all-locales" : "--locale \(locale ?? "")")")
}

if options.command == .captureInputs {
    let cfg = FileManager.default.fileExists(atPath: configPath) ? configPath : nil
    if (options.allLocales || options.locale != nil), let cfg {
        runLocalizedCapture(projectDir: resolvedProjectDir, configPath: cfg, locale: options.locale, allLocales: options.allLocales)
    } else {
        runCaptureInputs(projectDir: resolvedProjectDir, configPath: cfg)
    }
    exit(0)
}

if options.command == .regenerate {
    runCaptureInputs(projectDir: resolvedProjectDir, configPath: FileManager.default.fileExists(atPath: configPath) ? configPath : nil)
}

if options.command == .generate && !hasInputImages(projectDir: resolvedProjectDir, configPath: FileManager.default.fileExists(atPath: configPath) ? configPath : nil) {
    runCaptureInputs(projectDir: resolvedProjectDir, configPath: FileManager.default.fileExists(atPath: configPath) ? configPath : nil)
}

guard FileManager.default.fileExists(atPath: configPath) else {
    print("Error: Config not found at \(configPath)")
    print("Run with --init to create a default config:")
    print("  ios-appstore-screenshots init")
    exit(1)
}

do {
    let config = try ScreenshotConfig.load(from: configPath)
    let configDir = (configPath as NSString).deletingLastPathComponent

    if options.allLocales || options.locale != nil {
        let variants = (config.locales ?? []).filter { options.locale == nil || $0.code == options.locale }
        guard !variants.isEmpty else {
            let suffix = options.locale.map { " matching --locale \($0)" } ?? ""
            print("Error: no locale variants in config.locales\(suffix). Add a `locales` array to the config.")
            exit(1)
        }
        print("Generating localized screenshots for \(variants.count) locale(s): \(variants.map { $0.code }.joined(separator: ", "))\n")
        for variant in variants {
            let lconfig = config.localized(for: variant)
            print("[\(variant.code)] \(lconfig.screenshots.count) screenshots from \(lconfig.screenshotsDirectory)/ ...")
            let renderer = Renderer(config: lconfig, projectDir: resolvedProjectDir, configDir: configDir)
            try renderer.renderAll()
            print("[\(variant.code)] → \(resolvedProjectDir)/\(lconfig.outputDirectory)/")
        }
        print("\nDone! Localized screenshots generated for \(variants.count) locale(s).")
    } else {
        print("Loaded config: \(config.screenshots.count) screenshots, \(config.devices.count) devices")
        print("Generating up to \(config.screenshotCount) screenshots per device...\n")
        let renderer = Renderer(config: config, projectDir: resolvedProjectDir, configDir: configDir)
        try renderer.renderAll()
        print("\nDone! Screenshots saved to \(resolvedProjectDir)/\(config.outputDirectory)/")
    }

    if options.skipTemplatePrompt {
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
