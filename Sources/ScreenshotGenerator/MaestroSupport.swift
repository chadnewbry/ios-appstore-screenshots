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

    static func captureInputs(projectDir: String, configPath: String?) throws {
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

        try runMaestroTest(flowURL: flowURL, projectDir: projectDir)
        let destinationDir = try resolveInputsDirectory(projectDir: projectDir, configPath: configPath)
        try moveScreenshots(
            named: screenshotNames,
            fromProjectDir: projectDir,
            to: destinationDir
        )
    }

    private static func resolveInputsDirectory(projectDir: String, configPath: String?) throws -> URL {
        let appStoreDir = URL(fileURLWithPath: projectDir, isDirectory: true)
            .appendingPathComponent("App-Store-Screenshots", isDirectory: true)

        if let configPath {
            let config = try ScreenshotConfig.load(from: configPath)
            let directory: URL
            if config.screenshotsDirectory.hasPrefix("/") {
                directory = URL(fileURLWithPath: config.screenshotsDirectory, isDirectory: true)
            } else {
                directory = appStoreDir.appendingPathComponent(config.screenshotsDirectory, isDirectory: true)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        let defaultDirectory = appStoreDir.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
        return defaultDirectory
    }

    private static func runMaestroTest(flowURL: URL, projectDir: String) throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir, isDirectory: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["maestro", "test", flowURL.path]
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
