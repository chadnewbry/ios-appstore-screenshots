import Foundation

enum MaestroError: Error, LocalizedError {
    case flowTemplateCreated(URL)
    case maestroNotInstalled
    case captureFailed(Int32)
    case noScreenshotsDefined(URL)

    var errorDescription: String? {
        switch self {
        case .flowTemplateCreated(let url):
            return """
            Created a starter Maestro flow at \(url.path).
            Update the bundle ID, screen labels, and capture steps, then rerun the command.
            """
        case .maestroNotInstalled:
            return "Maestro CLI was not found. Install it with `brew install maestro`."
        case .captureFailed(let code):
            return "Maestro capture failed with exit code \(code)."
        case .noScreenshotsDefined(let url):
            return "No `takeScreenshot` steps were found in \(url.path)."
        }
    }
}

enum MaestroSupport {
    static let relativeFlowPath = "maestro/capture-screenshots.yaml"

    static func initFlowIfNeeded(projectDir: String) throws -> URL {
        let flowURL = URL(fileURLWithPath: projectDir, isDirectory: true)
            .appendingPathComponent(relativeFlowPath)

        guard !FileManager.default.fileExists(atPath: flowURL.path) else {
            return flowURL
        }

        try FileManager.default.createDirectory(
            at: flowURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try starterFlow.data(using: .utf8)?.write(to: flowURL)
        return flowURL
    }

    static func captureInputs(
        projectDir: String,
        configPath: String?,
        locale: String? = nil,
        appleLanguages: String? = nil
    ) throws {
        let flowURL = try initFlowIfNeeded(projectDir: projectDir)
        guard FileManager.default.fileExists(atPath: flowURL.path) else {
            throw MaestroError.flowTemplateCreated(flowURL)
        }

        let screenshotNames = try screenshotNames(from: flowURL)
        guard !screenshotNames.isEmpty else {
            throw MaestroError.noScreenshotsDefined(flowURL)
        }

        let didCreateFlow = starterFlowWasJustCreated(at: flowURL)
        if didCreateFlow {
            throw MaestroError.flowTemplateCreated(flowURL)
        }

        var extraEnv: [String: String] = [:]
        if let appleLanguages { extraEnv["APPLE_LANGUAGES"] = appleLanguages }
        if let locale {
            extraEnv["LOCALE_CODE"] = locale
            extraEnv["APPLE_LOCALE"] = locale.replacingOccurrences(of: "-", with: "_")
        }

        // Sign-in credentials for gated apps → forwarded to the Maestro flow as
        // ${LOGIN_EMAIL} / ${LOGIN_PASSWORD}. Env vars win over config so the
        // password can stay out of a committed config.
        let processEnv = ProcessInfo.processInfo.environment
        var loginEmail = processEnv["SCREENSHOT_LOGIN_EMAIL"]
        var loginPassword = processEnv["SCREENSHOT_LOGIN_PASSWORD"]
        if (loginEmail == nil || loginPassword == nil),
           let configPath, let config = try? ScreenshotConfig.load(from: configPath) {
            loginEmail = loginEmail ?? config.login?.email
            loginPassword = loginPassword ?? config.login?.password
        }
        if let loginEmail { extraEnv["LOGIN_EMAIL"] = loginEmail }
        if let loginPassword { extraEnv["LOGIN_PASSWORD"] = loginPassword }

        // Force the app UI into the target language by launching it ourselves
        // via simctl with -AppleLanguages BEFORE Maestro navigates. Maestro's
        // own launchApp arguments don't interpolate the language reliably, so
        // the tool owns the launch and the flow should just navigate/capture.
        if let appId = appId(fromFlow: flowURL) {
            let launchArgs = (try? ScreenshotConfig.load(from: configPath ?? ""))?.launchArguments ?? []
            try? launchAppViaSimctl(
                appId: appId,
                launchArguments: launchArgs,
                appleLanguages: appleLanguages,
                locale: locale
            )
        }

        try runMaestroTest(flowURL: flowURL, projectDir: projectDir, extraEnv: extraEnv)
        let destinationDir = try resolveInputsDirectory(projectDir: projectDir, configPath: configPath, locale: locale)
        try moveScreenshots(
            named: screenshotNames,
            fromProjectDir: projectDir,
            to: destinationDir
        )
    }

    private static func resolveInputsDirectory(projectDir: String, configPath: String?, locale: String? = nil) throws -> URL {
        let appStoreDir = URL(fileURLWithPath: projectDir, isDirectory: true)
            .appendingPathComponent("App-Store-Screenshots", isDirectory: true)

        var directory: URL
        if let configPath, let config = try? ScreenshotConfig.load(from: configPath) {
            if config.screenshotsDirectory.hasPrefix("/") {
                directory = URL(fileURLWithPath: config.screenshotsDirectory, isDirectory: true)
            } else {
                directory = appStoreDir.appendingPathComponent(config.screenshotsDirectory, isDirectory: true)
            }
        } else {
            directory = appStoreDir.appendingPathComponent("inputs", isDirectory: true)
        }

        // Route per-language captures into a locale subdirectory so `generate
        // --locale <code>` finds them at `<screenshotsDirectory>/<code>/`.
        if let locale {
            directory = directory.appendingPathComponent(locale, isDirectory: true)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func runMaestroTest(flowURL: URL, projectDir: String, extraEnv: [String: String] = [:]) throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir, isDirectory: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Maestro takes flow parameters via `-e KEY=VALUE`; the capture flow
        // interpolates ${APPLE_LANGUAGES}/${APPLE_LOCALE} into launchApp args
        // to force the app UI into the target language.
        var maestroArgs = ["maestro", "test", flowURL.path]
        for (key, value) in extraEnv.sorted(by: { $0.key < $1.key }) {
            maestroArgs += ["-e", "\(key)=\(value)"]
        }
        process.arguments = maestroArgs
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        let maestroBin = "\(home)/.maestro/bin"
        let path = environment["PATH"] ?? ""
        if !path.split(separator: ":").contains(Substring(maestroBin)) {
            environment["PATH"] = "\(path):\(maestroBin)"
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw MaestroError.maestroNotInstalled
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MaestroError.captureFailed(process.terminationStatus)
        }
    }

    /// Parse the `appId:` from a Maestro flow's YAML header.
    private static func appId(fromFlow flowURL: URL) -> String? {
        guard let contents = try? String(contentsOf: flowURL, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("appId:") {
                let value = trimmed.dropFirst("appId:".count).trimmingCharacters(in: .whitespaces)
                let cleaned = value.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                if !cleaned.isEmpty, !cleaned.hasPrefix("$") { return cleaned }
            }
        }
        return nil
    }

    /// Launch the app on the booted simulator via simctl, forcing the UI
    /// language when a locale is given. Terminates first for a clean cold start.
    private static func launchAppViaSimctl(
        appId: String,
        launchArguments: [String],
        appleLanguages: String?,
        locale: String?
    ) throws {
        let terminate = Process()
        terminate.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        terminate.arguments = ["simctl", "terminate", "booted", appId]
        try? terminate.run(); terminate.waitUntilExit()

        var args = ["simctl", "launch", "booted", appId] + launchArguments
        if let appleLanguages { args += ["-AppleLanguages", appleLanguages] }
        if let locale { args += ["-AppleLocale", locale.replacingOccurrences(of: "-", with: "_")] }

        let launch = Process()
        launch.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        launch.arguments = args
        try launch.run(); launch.waitUntilExit()
        // Give the app a moment to render before Maestro takes over.
        Thread.sleep(forTimeInterval: 2.5)
    }

    private static func moveScreenshots(named names: [String], fromProjectDir projectDir: String, to destinationDir: URL) throws {
        let fileManager = FileManager.default
        let projectURL = URL(fileURLWithPath: projectDir, isDirectory: true)

        for name in names {
            let sourceURL = projectURL.appendingPathComponent("\(name).png")
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = destinationDir.appendingPathComponent("\(name).png")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            print("Moved \(sourceURL.lastPathComponent) to \(destinationURL.path)")
        }
    }

    private static func screenshotNames(from flowURL: URL) throws -> [String] {
        let contents = try String(contentsOf: flowURL, encoding: .utf8)
        let pattern = #"-\s*takeScreenshot:\s*"?([^"\n]+)"?\s*$"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: contents) else {
                return nil
            }
            return String(contents[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func starterFlowWasJustCreated(at flowURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: flowURL.path),
              let created = attributes[.creationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(created) < 5
    }

    private static let starterFlow = """
    # Maestro Screenshot Capture Flow — Starter
    #
    # Update this file for your app, then rerun `ios-appstore-screenshots capture-inputs`
    # or `ios-appstore-screenshots regenerate`.
    #
    # Maestro docs: https://maestro.mobile.dev

    appId: com.example.myapp
    name: "Capture App Store Screenshots"
    ---

    - launchApp:
        appId: com.example.myapp
        clearState: true

    - waitForAnimationToEnd
    - takeScreenshot: "01-home"

    - tapOn: "Explore"
    - waitForAnimationToEnd
    - takeScreenshot: "02-explore"

    - tapOn: "Profile"
    - waitForAnimationToEnd
    - takeScreenshot: "03-profile"
    """
}
