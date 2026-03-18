import XCTest
@testable import ScreenshotGenerator

final class CLIParsingTests: XCTestCase {
    func testParseArgsDefaultsToGenerateInCurrentDirectory() throws {
        let options = try parseArgs(["ios-appstore-screenshots"])

        XCTAssertEqual(options.command, .generate)
        XCTAssertEqual(options.projectDir, ".")
        XCTAssertNil(options.configPath)
        XCTAssertNil(options.templateId)
        XCTAssertEqual(options.templateSource, TemplateSupport.templateSourceBaseURL)
        XCTAssertFalse(options.skipTemplatePrompt)
    }

    func testParseArgsReadsTemplateAndProjectOptions() throws {
        let options = try parseArgs([
            "ios-appstore-screenshots",
            "generate",
            "--project-dir", "/tmp/app",
            "--template-id", "bloomtracker",
            "--template-source", "https://example.com/templates",
            "--skip-template-prompt"
        ])

        XCTAssertEqual(options.command, .generate)
        XCTAssertEqual(options.projectDir, "/tmp/app")
        XCTAssertEqual(options.templateId, "bloomtracker")
        XCTAssertEqual(options.templateSource, "https://example.com/templates")
        XCTAssertTrue(options.skipTemplatePrompt)
    }

    func testParseArgsThrowsForUnknownArgument() {
        XCTAssertThrowsError(try parseArgs(["ios-appstore-screenshots", "--wat"])) { error in
            XCTAssertEqual(error.localizedDescription, "Unknown argument: --wat")
        }
    }
}
