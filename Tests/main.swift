import Foundation

// MARK: - Fixture Loader

func loadFixture(_ name: String) -> Data {
    let fixturesDir: String
    if let envDir = ProcessInfo.processInfo.environment["FIXTURES_DIR"] {
        fixturesDir = envDir
    } else {
        fixturesDir = "./Tests/Fixtures"
    }
    let path = "\(fixturesDir)/\(name)"
    guard let data = FileManager.default.contents(atPath: path) else {
        fatalError("Failed to load fixture: \(path)")
    }
    return data
}

// No XCTMain needed on macOS — xctest auto-discovers tests
