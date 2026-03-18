import Foundation

struct TemplateIndexEntry: Codable {
    var templateId: String
    var name: String
    var description: String
    var author: String?
    var manifestPath: String
    var configPath: String
    var heroImagePath: String?
    var createdAt: String
}

struct TemplateManifest: Codable {
    struct Files: Codable {
        var config: String
        var sourceScreenshots: [String]
        var generatedImages: [String]
    }

    var schemaVersion: Int
    var templateId: String
    var name: String
    var description: String
    var author: String?
    var createdAt: String
    var files: Files
}

struct TemplateSubmissionBundle {
    var indexEntry: TemplateIndexEntry
    var manifest: TemplateManifest
    var files: [TemplateUploadFile]
}

struct TemplateUploadFile {
    var localURL: URL
    var remotePath: String
}

struct TemplateSourceFile {
    var localURL: URL
    var relativePath: String
}

enum TemplateError: Error, LocalizedError {
    case invalidTemplateSource(String)
    case templateNotFound(String)
    case missingConfig(URL)
    case missingSourceScreenshot(URL)
    case unsupportedSchemaVersion(Int, supported: Int)
    case gitHubAuthRequired(String)
    case invalidGitHubResponse(String)
    case submissionCancelled

    var errorDescription: String? {
        switch self {
        case .invalidTemplateSource(let message):
            return message
        case .templateNotFound(let templateId):
            return "Template \(templateId) was not found."
        case .missingConfig(let url):
            return "Expected config at \(url.path)."
        case .missingSourceScreenshot(let url):
            return "Expected source screenshot at \(url.path)."
        case .unsupportedSchemaVersion(let schemaVersion, let supported):
            return "Template schema version \(schemaVersion) is not supported. This CLI supports schema version \(supported)."
        case .gitHubAuthRequired(let message):
            return message
        case .invalidGitHubResponse(let message):
            return message
        case .submissionCancelled:
            return "Template submission cancelled."
        }
    }
}

enum TemplateSupport {
    static let supportedSchemaVersion = 1
    static let upstreamOwner = "chadnewbry"
    static let upstreamRepo = "ios-appstore-screenshots-website"
    static let upstreamBranch = "main"
    static let templatesRoot = "src/data/templates"
    static let templateSourceBaseURL = "https://raw.githubusercontent.com/\(upstreamOwner)/\(upstreamRepo)/\(upstreamBranch)/\(templatesRoot)"

    static func installTemplate(
        templateId: String,
        projectDir: String,
        templateSourceBaseURL: String
    ) throws -> URL {
        let baseURL = try normalizedBaseURL(templateSourceBaseURL)
        let indexURL = baseURL.appendingPathComponent("index.json")
        let indexData = try download(url: indexURL)

        let decoder = JSONDecoder()
        let indexEntries = try decoder.decode([TemplateIndexEntry].self, from: indexData)
        guard let entry = indexEntries.first(where: { $0.templateId == templateId }) else {
            throw TemplateError.templateNotFound(templateId)
        }

        let manifestURL = baseURL.appendingPathComponent(entry.manifestPath)
        let manifestData = try download(url: manifestURL)
        let manifest = try decoder.decode(TemplateManifest.self, from: manifestData)
        try validateSupportedSchemaVersion(manifest.schemaVersion)

        let appStoreDir = URL(fileURLWithPath: projectDir).appendingPathComponent("App-Store-Screenshots", isDirectory: true)
        let inputsDir = appStoreDir.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputsDir, withIntermediateDirectories: true)

        let configURL = appStoreDir.appendingPathComponent("screenshot-config.json")
        let remoteConfigURL = baseURL.appendingPathComponent(entry.configPath)
        try download(url: remoteConfigURL).write(to: configURL)
        let config = try ScreenshotConfig.load(from: configURL.path)
        let screenshotsBaseDir: URL
        if config.screenshotsDirectory.hasPrefix("/") {
            screenshotsBaseDir = URL(fileURLWithPath: config.screenshotsDirectory, isDirectory: true)
        } else {
            screenshotsBaseDir = appStoreDir.appendingPathComponent(config.screenshotsDirectory, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: screenshotsBaseDir, withIntermediateDirectories: true)

        for relativePath in manifest.files.sourceScreenshots {
            let remoteURL = baseURL.appendingPathComponent("templates/\(templateId)/\(relativePath)")
            let localURL = screenshotsBaseDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try download(url: remoteURL).write(to: localURL)
        }

        return configURL
    }

    static func buildSubmissionBundle(projectDir: String, configPath: String) throws -> TemplateSubmissionBundle {
        let projectURL = URL(fileURLWithPath: projectDir, isDirectory: true)
        let configURL = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw TemplateError.missingConfig(configURL)
        }

        let config = try ScreenshotConfig.load(from: configURL.path)
        let projectName = humanizedProjectName(projectURL.lastPathComponent)
        let templateId = makeTemplateID(from: projectURL.lastPathComponent)
        let createdAt = iso8601Timestamp()
        let templateDir = "templates/\(templateId)"

        let sourceFiles = try collectSourceScreenshotPaths(config: config, configPath: configPath)
        let generatedRelativePaths = try collectGeneratedImagePaths(projectDir: projectDir, outputDirectory: config.outputDirectory)
        let preferredHeroImagePath = preferredHeroImagePath(from: generatedRelativePaths)

        let manifest = TemplateManifest(
            schemaVersion: supportedSchemaVersion,
            templateId: templateId,
            name: projectName,
            description: "",
            author: "Chad Newbry",
            createdAt: createdAt,
            files: .init(
                config: "config.json",
                sourceScreenshots: sourceFiles.map(\.relativePath),
                generatedImages: generatedRelativePaths.map { "generated/\($0)" }
            )
        )

        let indexEntry = TemplateIndexEntry(
            templateId: templateId,
            name: projectName,
            description: "",
            author: "Chad Newbry",
            manifestPath: "\(templateDir)/template.json",
            configPath: "\(templateDir)/config.json",
            heroImagePath: preferredHeroImagePath.map { "\(templateDir)/generated/\($0)" },
            createdAt: createdAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let supportDir = projectURL.appendingPathComponent(".app-store-screenshot-template-submit", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let manifestURL = supportDir.appendingPathComponent("template.json")
        try encoder.encode(manifest).write(to: manifestURL)

        var files: [TemplateUploadFile] = [
            .init(localURL: manifestURL, remotePath: "\(templatesRoot)/\(templateDir)/template.json"),
            .init(localURL: configURL, remotePath: "\(templatesRoot)/\(templateDir)/config.json")
        ]

        for sourceFile in sourceFiles {
            files.append(.init(
                localURL: sourceFile.localURL,
                remotePath: "\(templatesRoot)/\(templateDir)/source-screenshots/\(sourceFile.relativePath)"
            ))
        }

        for generatedPath in generatedRelativePaths {
            let localURL = projectURL.appendingPathComponent(config.outputDirectory).appendingPathComponent(generatedPath)
            files.append(.init(localURL: localURL, remotePath: "\(templatesRoot)/\(templateDir)/generated/\(generatedPath)"))
        }

        return TemplateSubmissionBundle(indexEntry: indexEntry, manifest: manifest, files: files)
    }

    static func submitTemplate(bundle: TemplateSubmissionBundle) throws -> URL {
        let github = try GitHubTemplateClient.resolveIdentity()
        return try github.submit(bundle: bundle)
    }

    static func promptForSubmission() -> Bool {
        guard isInteractive() else { return false }
        print("")
        print("Thanks for using iOS App Store Screenshots.")
        print("It helps a lot when people share their templates so others can reuse them.")
        print("Would you like to open an automatic GitHub PR with this template? [y/N]")
        guard let response = readLine(strippingNewline: true) else {
            return false
        }
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "y" || normalized == "yes"
    }

    static func printContributionMessage() {
        print("")
        print("Thanks for using iOS App Store Screenshots.")
        print("If you'd like, you can add this as a template for the website so other people can reuse it.")
        print("Run the generator again in a terminal session and say yes to the GitHub PR prompt after generation.")
    }

    private static func validateSupportedSchemaVersion(_ schemaVersion: Int) throws {
        guard schemaVersion == supportedSchemaVersion else {
            throw TemplateError.unsupportedSchemaVersion(schemaVersion, supported: supportedSchemaVersion)
        }
    }

    private static func collectSourceScreenshotPaths(config: ScreenshotConfig, configPath: String) throws -> [TemplateSourceFile] {
        let configURL = URL(fileURLWithPath: configPath)
        let configDir = configURL.deletingLastPathComponent()
        let screenshotsDir: URL
        if config.screenshotsDirectory.hasPrefix("/") {
            screenshotsDir = URL(fileURLWithPath: config.screenshotsDirectory, isDirectory: true)
        } else {
            screenshotsDir = configDir.appendingPathComponent(config.screenshotsDirectory, isDirectory: true)
        }

        var ordered: [TemplateSourceFile] = []
        var seen = Set<String>()
        for screenshot in config.screenshots.prefix(config.screenshotCount) {
            let paths = screenshot.screenshotPaths?.values.sorted() ?? [screenshot.screenshotPath]
            for path in paths {
                let url = screenshotsDir.appendingPathComponent(path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw TemplateError.missingSourceScreenshot(url)
                }
                if seen.insert(url.path).inserted {
                    ordered.append(.init(localURL: url, relativePath: path))
                }
            }
        }
        return ordered
    }

    private static func collectGeneratedImagePaths(projectDir: String, outputDirectory: String) throws -> [String] {
        let outputURL = URL(fileURLWithPath: projectDir, isDirectory: true)
            .appendingPathComponent(outputDirectory, isDirectory: true)
            .standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: outputURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "png" else { continue }
            let normalizedFileURL = fileURL.standardizedFileURL
            let relativePath = normalizedFileURL.path.replacingOccurrences(of: outputURL.path + "/", with: "")
            paths.append(relativePath)
        }
        return paths.sorted()
    }

    private static func preferredHeroImagePath(from generatedPaths: [String]) -> String? {
        generatedPaths.first(where: { $0.contains("/iPhone ") && $0.hasSuffix("/01.png") })
        ?? generatedPaths.first(where: { $0.contains("/iPhone ") })
        ?? generatedPaths.first(where: { $0.contains("/iPad ") && $0.hasSuffix("/01.png") })
        ?? generatedPaths.first
    }

    private static func makeTemplateID(from seed: String) -> String {
        slugify(seed)
    }

    private static func slugify(_ value: String) -> String {
        let lowercase = value.lowercased()
        var scalars = String.UnicodeScalarView()
        var lastWasDash = false
        for scalar in lowercase.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                scalars.append("-")
                lastWasDash = true
            }
        }
        let raw = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return raw.isEmpty ? "template" : raw
    }

    private static func humanizedProjectName(_ value: String) -> String {
        let separators = CharacterSet(charactersIn: "-_")
        let components = value
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .map { component in
                component.prefix(1).uppercased() + component.dropFirst()
            }
        if components.isEmpty {
            return value
        }
        return components.joined(separator: " ")
    }

    private static func timestampID() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

    private static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func normalizedBaseURL(_ string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
            throw TemplateError.invalidTemplateSource("Invalid template source URL: \(string)")
        }
        return url
    }

    private static func download(url: URL) throws -> Data {
        var result: Result<Data, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(data ?? Data())
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case .none:
            throw TemplateError.invalidTemplateSource("No response from \(url.absoluteString)")
        }
    }

    private static func isInteractive() -> Bool {
        isatty(fileno(stdin)) == 1
    }
}

private struct GitHubTemplateIdentity {
    var token: String
    var login: String
}

private final class GitHubTemplateClient {
    private let token: String
    private let login: String
    private let session = URLSession.shared

    init(token: String, login: String) {
        self.token = token
        self.login = login
    }

    static func resolveIdentity() throws -> GitHubTemplateClient {
        func runGH(_ args: [String]) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + args
            process.environment = ProcessInfo.processInfo.environment.merging([
                "GH_PROMPT_DISABLED": "1",
                "GIT_TERMINAL_PROMPT": "0"
            ]) { _, new in new }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw TemplateError.gitHubAuthRequired("GitHub CLI is required. Install `gh` and run `gh auth login`.")
            }

            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw TemplateError.gitHubAuthRequired(errorText.isEmpty ? "Run `gh auth login` first." : errorText)
            }

            return stdout.fileHandleForReading.readDataToEndOfFile()
        }

        let tokenData = try runGH(["auth", "token"])
        let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            throw TemplateError.gitHubAuthRequired("`gh auth token` returned an empty token. Run `gh auth login` first.")
        }

        let login = try currentUserLogin(token: token)
        return GitHubTemplateClient(token: token, login: login)
    }

    func submit(bundle: TemplateSubmissionBundle) throws -> URL {
        let upstreamFullName = "\(TemplateSupport.upstreamOwner)/\(TemplateSupport.upstreamRepo)"
        let forkFullName = "\(login)/\(TemplateSupport.upstreamRepo)"
        let useUpstreamDirectly = login.caseInsensitiveCompare(TemplateSupport.upstreamOwner) == .orderedSame
        let targetOwner = useUpstreamDirectly ? TemplateSupport.upstreamOwner : login
        let branch = "templates/\(bundle.indexEntry.templateId)"
        let commitMessage = "templates: add \(bundle.indexEntry.templateId)"
        let prTitle = commitMessage
        let prBody = """
        ## Summary

        - add template `\(bundle.indexEntry.templateId)`

        ## Notes

        - submitted via `ios-appstore-screenshots`
        """

        let forkRepo = useUpstreamDirectly ? nil : try repo(owner: login, repo: TemplateSupport.upstreamRepo)
        if !useUpstreamDirectly, let forkRepo, !forkRepo.isFork(of: upstreamFullName) {
            throw TemplateError.invalidGitHubResponse("Existing repo \(forkFullName) is not a fork of \(upstreamFullName).")
        }

        let baseSHA = try refSHA(owner: TemplateSupport.upstreamOwner, repo: TemplateSupport.upstreamRepo, ref: "heads/\(TemplateSupport.upstreamBranch)")
        let indexResponse = try fileContents(
            owner: TemplateSupport.upstreamOwner,
            repo: TemplateSupport.upstreamRepo,
            path: "\(TemplateSupport.templatesRoot)/index.json",
            ref: baseSHA
        )
        let updatedIndexData = try updatedIndex(indexData: indexResponse.content, adding: bundle.indexEntry)

        if !useUpstreamDirectly, forkRepo == nil {
            try createFork(owner: TemplateSupport.upstreamOwner, repo: TemplateSupport.upstreamRepo)
            try waitForRepo(owner: login, repo: TemplateSupport.upstreamRepo)
        }

        try createBranch(owner: targetOwner, repo: TemplateSupport.upstreamRepo, branch: branch, sha: baseSHA)
        try updateFile(
            owner: targetOwner,
            repo: TemplateSupport.upstreamRepo,
            path: "\(TemplateSupport.templatesRoot)/index.json",
            sha: indexResponse.sha,
            branch: branch,
            message: commitMessage,
            data: updatedIndexData
        )

        for file in bundle.files {
            guard FileManager.default.fileExists(atPath: file.localURL.path) else {
                throw TemplateError.invalidGitHubResponse("Template upload file is missing: \(file.localURL.path)")
            }
            let data = try Data(contentsOf: file.localURL)
            try createOrUpdateFile(
                owner: targetOwner,
                repo: TemplateSupport.upstreamRepo,
                path: file.remotePath,
                branch: branch,
                message: commitMessage,
                data: data
            )
        }

        let pr = try createPullRequest(
            owner: TemplateSupport.upstreamOwner,
            repo: TemplateSupport.upstreamRepo,
            title: prTitle,
            body: prBody,
            head: useUpstreamDirectly ? branch : "\(login):\(branch)",
            base: TemplateSupport.upstreamBranch
        )
        guard let url = URL(string: pr.htmlURL) else {
            throw TemplateError.invalidGitHubResponse("GitHub returned an invalid pull request URL.")
        }
        return url
    }

    private func updatedIndex(indexData: Data, adding entry: TemplateIndexEntry) throws -> Data {
        let decoder = JSONDecoder()
        var entries = try decoder.decode([TemplateIndexEntry].self, from: indexData)
        if entries.contains(where: { $0.templateId == entry.templateId }) {
            throw TemplateError.invalidGitHubResponse("Template ID \(entry.templateId) already exists.")
        }
        entries.append(entry)
        entries.sort { $0.templateId < $1.templateId }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(entries)
    }

    private static func currentUserLogin(token: String) throws -> String {
        let client = GitHubTemplateClient(token: token, login: "")
        let payload = try client.request(method: "GET", path: "/user", payload: nil)
        guard payload.statusCode == 200 else {
            throw TemplateError.invalidGitHubResponse("Failed to fetch GitHub user.")
        }
        let json = try JSONSerialization.jsonObject(with: payload.data) as? [String: Any]
        guard let login = json?["login"] as? String, !login.isEmpty else {
            throw TemplateError.invalidGitHubResponse("GitHub user login was empty.")
        }
        return login
    }

    private func repo(owner: String, repo: String) throws -> GitHubRepo? {
        let payload = try request(method: "GET", path: "/repos/\(owner)/\(repo)", payload: nil)
        if payload.statusCode == 404 {
            return nil
        }
        guard payload.statusCode == 200 else {
            throw TemplateError.invalidGitHubResponse("Failed to inspect fork \(owner)/\(repo).")
        }
        return try JSONDecoder().decode(GitHubRepo.self, from: payload.data)
    }

    private func createFork(owner: String, repo: String) throws {
        let payload = try request(method: "POST", path: "/repos/\(owner)/\(repo)/forks", payload: [:])
        guard payload.statusCode == 202 || payload.statusCode == 201 else {
            throw TemplateError.invalidGitHubResponse("Failed to create fork.")
        }
    }

    private func waitForRepo(owner: String, repo repoName: String) throws {
        for _ in 0..<20 {
            if let _ = try repo(owner: owner, repo: repoName) {
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        throw TemplateError.invalidGitHubResponse("Timed out waiting for fork \(owner)/\(repoName).")
    }

    private func refSHA(owner: String, repo: String, ref: String) throws -> String {
        let payload = try request(method: "GET", path: "/repos/\(owner)/\(repo)/git/ref/\(ref)", payload: nil)
        guard payload.statusCode == 200 else {
            throw TemplateError.invalidGitHubResponse("Failed to fetch git ref \(ref).")
        }
        let ref = try JSONDecoder().decode(GitHubRef.self, from: payload.data)
        return ref.object.sha
    }

    private func createBranch(owner: String, repo: String, branch: String, sha: String) throws {
        let payload = try request(method: "POST", path: "/repos/\(owner)/\(repo)/git/refs", payload: [
            "ref": "refs/heads/\(branch)",
            "sha": sha
        ])
        guard payload.statusCode == 201 else {
            throw TemplateError.invalidGitHubResponse("Failed to create branch \(branch).")
        }
    }

    private func fileContents(owner: String, repo: String, path: String, ref: String) throws -> GitHubFileContent {
        let escapedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref
        let payload = try request(method: "GET", path: "/repos/\(owner)/\(repo)/contents/\(path)?ref=\(escapedRef)", payload: nil)
        guard payload.statusCode == 200 else {
            throw TemplateError.invalidGitHubResponse("Failed to fetch \(path).")
        }
        let content = try JSONDecoder().decode(GitHubContentPayload.self, from: payload.data)
        guard content.encoding == "base64" else {
            throw TemplateError.invalidGitHubResponse("Unsupported GitHub encoding \(content.encoding).")
        }
        let normalized = content.content.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: normalized) else {
            throw TemplateError.invalidGitHubResponse("Failed to decode GitHub content for \(path).")
        }
        return GitHubFileContent(content: data, sha: content.sha)
    }

    private func updateFile(owner: String, repo: String, path: String, sha: String, branch: String, message: String, data: Data) throws {
        let payload = try request(method: "PUT", path: "/repos/\(owner)/\(repo)/contents/\(path)", payload: [
            "message": message,
            "content": data.base64EncodedString(),
            "sha": sha,
            "branch": branch
        ])
        guard payload.statusCode == 200 || payload.statusCode == 201 else {
            throw TemplateError.invalidGitHubResponse("Failed to update \(path).")
        }
    }

    private func createOrUpdateFile(owner: String, repo: String, path: String, branch: String, message: String, data: Data) throws {
        let existing = try fileContentsIfPresent(owner: owner, repo: repo, path: path, ref: branch)
        var requestPayload: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "branch": branch
        ]
        if let existing {
            requestPayload["sha"] = existing.sha
        }

        let payload = try request(method: "PUT", path: "/repos/\(owner)/\(repo)/contents/\(path)", payload: requestPayload)
        guard payload.statusCode == 200 || payload.statusCode == 201 else {
            throw TemplateError.invalidGitHubResponse("Failed to upload \(path).")
        }
    }

    private func fileContentsIfPresent(owner: String, repo: String, path: String, ref: String) throws -> GitHubFileContent? {
        let escapedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref
        let payload = try request(method: "GET", path: "/repos/\(owner)/\(repo)/contents/\(path)?ref=\(escapedRef)", payload: nil)
        if payload.statusCode == 404 {
            return nil
        }
        guard payload.statusCode == 200 else {
            throw TemplateError.invalidGitHubResponse("Failed to inspect \(path).")
        }
        let content = try JSONDecoder().decode(GitHubContentPayload.self, from: payload.data)
        let normalized = content.content.replacingOccurrences(of: "\n", with: "")
        let data = Data(base64Encoded: normalized) ?? Data()
        return GitHubFileContent(content: data, sha: content.sha)
    }

    private func createPullRequest(owner: String, repo: String, title: String, body: String, head: String, base: String) throws -> GitHubPullRequest {
        let payload = try request(method: "POST", path: "/repos/\(owner)/\(repo)/pulls", payload: [
            "title": title,
            "body": body,
            "head": head,
            "base": base
        ])
        guard payload.statusCode == 201 else {
            throw TemplateError.invalidGitHubResponse("Failed to create pull request.")
        }
        return try JSONDecoder().decode(GitHubPullRequest.self, from: payload.data)
    }

    private func request(method: String, path: String, payload: Any?) throws -> (data: Data, statusCode: Int) {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw TemplateError.invalidGitHubResponse("Invalid GitHub URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        var result: Result<(Data, Int), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
                semaphore.signal()
                return
            }
            let response = response as? HTTPURLResponse
            result = .success((data ?? Data(), response?.statusCode ?? 0))
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw TemplateError.invalidGitHubResponse("GitHub request failed without a response.")
        }
    }
}

private struct GitHubRepo: Codable {
    struct Parent: Codable {
        var fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    var fullName: String
    var fork: Bool
    var parent: Parent?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case fork
        case parent
    }

    func isFork(of upstreamFullName: String) -> Bool {
        fork && parent?.fullName.caseInsensitiveCompare(upstreamFullName) == .orderedSame
    }
}

private struct GitHubRef: Codable {
    struct Object: Codable {
        var sha: String
    }

    var object: Object
}

private struct GitHubContentPayload: Codable {
    var sha: String
    var encoding: String
    var content: String
}

private struct GitHubFileContent {
    var content: Data
    var sha: String
}

private struct GitHubPullRequest: Codable {
    var htmlURL: String

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
    }
}
