import Foundation
import XCTest

// MARK: - HookManagerTests

final class HookManagerTests: XCTestCase {
    private var tempDir: URL!
    private var manager: HookManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusBarHookTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = HookManager(hooksDirectory: tempDir, timeout: 2)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - HookEvent Raw Values

    func testHookEventRawValues() {
        XCTAssertEqual(HookEvent.onStatusChange.rawValue, "on-status-change")
        XCTAssertEqual(HookEvent.onRefresh.rawValue, "on-refresh")
        XCTAssertEqual(HookEvent.onSourceAdd.rawValue, "on-source-add")
        XCTAssertEqual(HookEvent.onSourceRemove.rawValue, "on-source-remove")
    }

    func testHookEventAllCases() {
        XCTAssertEqual(HookEvent.allCases.count, 4)
    }

    // MARK: - Directory Management

    func testEnsureHooksDirectoryCreatesDir() {
        let subDir = tempDir.appendingPathComponent("nested/hooks")
        let mgr = HookManager(hooksDirectory: subDir, timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: subDir.path))
        mgr.ensureHooksDirectory()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: subDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - Hook Discovery

    func testDiscoverHooksEmptyDir() {
        let hooks = manager.discoverHooks()
        XCTAssertTrue(hooks.isEmpty)
    }

    func testDiscoverHooksFindsExecutables() {
        // Create an executable script
        let scriptURL = tempDir.appendingPathComponent("test-hook")
        FileManager.default.createFile(atPath: scriptURL.path, contents: "#!/bin/bash\nexit 0\n".data(using: .utf8))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        // Create a non-executable file
        let nonExecURL = tempDir.appendingPathComponent("not-a-hook.txt")
        FileManager.default.createFile(atPath: nonExecURL.path, contents: "hello".data(using: .utf8))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: nonExecURL.path
        )

        let hooks = manager.discoverHooks()
        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks.first?.lastPathComponent, "test-hook")
    }

    func testDiscoverHooksSkipsHiddenFiles() {
        let hidden = tempDir.appendingPathComponent(".hidden-hook")
        FileManager.default.createFile(atPath: hidden.path, contents: "#!/bin/bash\n".data(using: .utf8))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hidden.path
        )

        let hooks = manager.discoverHooks()
        XCTAssertTrue(hooks.isEmpty)
    }

    // MARK: - Script Execution

    func testExecuteSimpleScript() async {
        let script = tempDir.appendingPathComponent("exit-zero")
        FileManager.default.createFile(
            atPath: script.path,
            contents: "#!/bin/bash\nexit 0\n".data(using: .utf8)
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let exitCode = await manager.execute(script: script, event: .onRefresh)
        XCTAssertEqual(exitCode, 0)
    }

    func testExecuteScriptNonZeroExit() async {
        let script = tempDir.appendingPathComponent("exit-one")
        FileManager.default.createFile(
            atPath: script.path,
            contents: "#!/bin/bash\nexit 1\n".data(using: .utf8)
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let exitCode = await manager.execute(script: script, event: .onRefresh)
        XCTAssertEqual(exitCode, 1)
    }

    func testExecuteTimeoutKillsHungScript() async {
        let script = tempDir.appendingPathComponent("sleeper")
        FileManager.default.createFile(
            atPath: script.path,
            contents: "#!/bin/bash\nsleep 60\n".data(using: .utf8)
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let start = Date()
        let exitCode = await manager.execute(script: script, event: .onRefresh)
        let elapsed = Date().timeIntervalSince(start)

        // Should be killed within ~2s timeout, not 60s
        XCTAssertLessThan(elapsed, 10)
        // SIGTERM results in non-zero exit
        XCTAssertNotEqual(exitCode, 0)
    }

    func testExecutePassesEnvVars() async {
        let outputFile = tempDir.appendingPathComponent("env-output.txt")
        let script = tempDir.appendingPathComponent("env-reader")
        let scriptContent = """
            #!/bin/bash
            echo "$STATUSBAR_EVENT|$STATUSBAR_SOURCE_NAME" > "\(outputFile.path)"
            """
        FileManager.default.createFile(
            atPath: script.path,
            contents: scriptContent.data(using: .utf8)
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let exitCode = await manager.execute(
            script: script,
            event: .onStatusChange,
            environment: ["STATUSBAR_SOURCE_NAME": "GitHub"]
        )
        XCTAssertEqual(exitCode, 0)

        // Give a moment for file write
        try? await Task.sleep(nanoseconds: 100_000_000)

        let output = try? String(contentsOf: outputFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(output, "on-status-change|GitHub")
    }

    func testExecutePassesJSONToStdin() async {
        let outputFile = tempDir.appendingPathComponent("stdin-output.txt")
        let script = tempDir.appendingPathComponent("stdin-reader")
        let scriptContent = """
            #!/bin/bash
            cat > "\(outputFile.path)"
            """
        FileManager.default.createFile(
            atPath: script.path,
            contents: scriptContent.data(using: .utf8)
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let json = "{\"test\":true}".data(using: .utf8)
        let exitCode = await manager.execute(
            script: script, event: .onRefresh, jsonPayload: json
        )
        XCTAssertEqual(exitCode, 0)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let output = try? String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(output, "{\"test\":true}")
    }

    // MARK: - JSON Builders

    func testBuildStatusChangeJSON() {
        let data = HookManager.buildStatusChangeJSON(
            sourceName: "GitHub", sourceURL: "https://www.githubstatus.com",
            title: "Degraded", body: "Minor outage"
        )
        XCTAssertNotNil(data)
        let dict = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertEqual(dict?["event"] as? String, "on-status-change")
        XCTAssertEqual(dict?["source_name"] as? String, "GitHub")
        XCTAssertEqual(dict?["title"] as? String, "Degraded")
    }

    func testBuildRefreshJSON() {
        let data = HookManager.buildRefreshJSON(sourceCount: 3, worstLevel: "minor")
        XCTAssertNotNil(data)
        let dict = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertEqual(dict?["event"] as? String, "on-refresh")
        XCTAssertEqual(dict?["source_count"] as? Int, 3)
        XCTAssertEqual(dict?["worst_level"] as? String, "minor")
    }

    func testBuildSourceJSON() {
        let data = HookManager.buildSourceJSON(
            event: .onSourceAdd, name: "Stripe", url: "https://status.stripe.com"
        )
        XCTAssertNotNil(data)
        let dict = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertEqual(dict?["event"] as? String, "on-source-add")
        XCTAssertEqual(dict?["source_name"] as? String, "Stripe")
        XCTAssertEqual(dict?["source_url"] as? String, "https://status.stripe.com")
    }
}
