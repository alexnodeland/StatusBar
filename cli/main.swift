// main.swift — the statusbar CLI
// Reads the app's status cache (~/.cache/statusbar/status.json), can fetch
// live from providers when the app isn't running, and drives the app via
// its statusbar:// URL scheme.

import Foundation

// MARK: - Output helpers

let stdoutIsTTY = isatty(fileno(stdout)) == 1
let colorEnabled = stdoutIsTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

func paint(_ text: String, _ code: String) -> String {
    colorEnabled ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
}

func glyph(for indicator: String) -> String {
    switch indicator {
    case "none": return paint("●", "32")
    case "minor": return paint("▲", "33")
    case "major": return paint("▲", "38;5;208")
    case "critical": return paint("✖", "31")
    default: return paint("○", "90")
    }
}

func plainGlyph(for indicator: String) -> String {
    switch indicator {
    case "none": return "●"
    case "minor", "major": return "▲"
    case "critical": return "✖"
    default: return "○"
    }
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data(("statusbar: " + message + "\n").utf8))
    exit(code)
}

// MARK: - Cache access

func loadCache(required: Bool = true) -> StatusCacheSnapshot? {
    if let snapshot = StatusCache().read() { return snapshot }
    if required {
        fail(
            "no status cache at \(StatusCache.defaultURL.path).\n"
                + "Launch StatusBar.app once, or use --fresh to fetch live.", code: 2)
    }
    return nil
}

func findSource(_ name: String, in snapshot: StatusCacheSnapshot) -> StatusCacheSource? {
    snapshot.sources.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        ?? snapshot.sources.first { $0.name.lowercased().contains(name.lowercased()) }
}

// MARK: - URL scheme passthrough

func openURLScheme(_ url: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", url]
    try? process.run()
    process.waitUntilExit()
}

// MARK: - Repo config (.statusbar)

/// Walks up from the working directory looking for a `.statusbar` file:
/// one source name per line, `#` comments. Scopes status/prompt output to
/// that project's upstream dependencies.
func repoConfig() -> (names: [String], path: String)? {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while true {
        let file = dir.appendingPathComponent(".statusbar")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            let names = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            if !names.isEmpty { return (names, file.path) }
        }
        if dir.path == "/" { return nil }
        dir.deleteLastPathComponent()
    }
}

struct ScopedSnapshot {
    let sources: [StatusCacheSource]
    let missing: [String]
    let configPath: String
    var worst: String {
        let ranked = sources.map { severityRank($0.indicator) }.max() ?? -1
        return ranked <= 0 ? (ranked == 0 ? "none" : "unknown") : ["none", "minor", "major", "critical"][ranked]
    }
    var issueCount: Int {
        sources.filter { $0.indicator != "none" && $0.indicator != "unknown" }.count
    }
}

func applyRepoScope(_ snapshot: StatusCacheSnapshot) -> ScopedSnapshot? {
    guard let config = repoConfig() else { return nil }
    var matched: [StatusCacheSource] = []
    var missing: [String] = []
    for name in config.names {
        if let source = findSource(name, in: snapshot),
            !matched.contains(where: { $0.name == source.name })
        {
            matched.append(source)
        } else {
            missing.append(name)
        }
    }
    return ScopedSnapshot(sources: matched, missing: missing, configPath: config.path)
}

func severityRank(_ indicator: String) -> Int {
    ["none": 0, "minor": 1, "major": 2, "critical": 3][indicator] ?? -1
}

// MARK: - Commands

func printStatusLine(name: String, indicator: String, description: String, snoozed: Bool) {
    let pad = name.padding(toLength: max(name.count, 18), withPad: " ", startingAt: 0)
    let snooze = snoozed ? paint(" (snoozed)", "90") : ""
    print("\(glyph(for: indicator)) \(pad) \(paint(description, "90"))\(snooze)")
}

func cmdStatus(name: String?, json: Bool, fresh: Bool, allFlag: Bool) async {
    guard let snapshot = loadCache() else { return }

    if let name {
        guard let source = findSource(name, in: snapshot) else {
            fail("no source matching \u{201C}\(name)\u{201D}", code: 2)
        }
        var indicator = source.indicator
        var description = source.description
        if fresh {
            (indicator, description) = await CLIFetcher().liveStatus(baseURL: source.url)
        }
        if json {
            let payload: [String: Any] = [
                "name": source.name, "url": source.url,
                "indicator": indicator, "description": description,
            ]
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
        } else {
            printStatusLine(
                name: source.name, indicator: indicator,
                description: description, snoozed: source.snoozed)
        }
        exit(indicator == "none" ? 0 : (severityRank(indicator) > 0 ? 1 : 2))
    }

    // Repo scope: a .statusbar file narrows output to that project's deps
    if !allFlag, let scoped = applyRepoScope(snapshot) {
        if json {
            let payload: [String: Any] = [
                "worst": scoped.worst,
                "issueCount": scoped.issueCount,
                "scope": scoped.configPath,
                "sources": scoped.sources.map {
                    ["name": $0.name, "indicator": $0.indicator, "description": $0.description]
                },
                "missing": scoped.missing,
            ]
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
        } else {
            for source in scoped.sources {
                printStatusLine(
                    name: source.name, indicator: source.indicator,
                    description: source.description, snoozed: source.snoozed)
            }
            for name in scoped.missing {
                print("\(glyph(for: "unknown")) \(name.padding(toLength: max(name.count, 18), withPad: " ", startingAt: 0)) \(paint("not monitored — statusbar add <url> \(name)", "90"))")
            }
            print(paint("— scoped by \(scoped.configPath)", "90"))
        }
        exit(scoped.worst == "none" ? 0 : (severityRank(scoped.worst) > 0 ? 1 : 2))
    }

    // All sources
    var worst = snapshot.worst
    if fresh {
        let fetcher = CLIFetcher()
        var rank = 0
        for source in snapshot.sources {
            let (indicator, description) = await fetcher.liveStatus(baseURL: source.url)
            rank = max(rank, severityRank(indicator))
            if !json {
                printStatusLine(
                    name: source.name, indicator: indicator,
                    description: description, snoozed: source.snoozed)
            }
        }
        worst = ["none", "minor", "major", "critical"][max(rank, 0)]
        exit(worst == "none" ? 0 : 1)
    }

    if json {
        let data = try? JSONEncoder().encode(snapshot)
        print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
    } else {
        for source in snapshot.sources {
            printStatusLine(
                name: source.name, indicator: source.indicator,
                description: source.description, snoozed: source.snoozed)
        }
        let summary =
            snapshot.issueCount == 0
            ? "all systems operational"
            : "\(snapshot.issueCount) source\(snapshot.issueCount == 1 ? "" : "s") with issues"
        print(paint("— \(summary) · updated \(snapshot.updatedAt)", "90"))
    }
    exit(worst == "none" ? 0 : (severityRank(worst) > 0 ? 1 : 2))
}

func cmdPrompt(allFlag: Bool) {
    guard let snapshot = loadCache(required: false) else {
        print("○")
        exit(0)
    }
    var worst = snapshot.worst
    var issues = snapshot.issueCount
    if !allFlag, let scoped = applyRepoScope(snapshot), !scoped.sources.isEmpty {
        worst = scoped.worst
        issues = scoped.issueCount
    }
    if issues > 0 {
        print("\(plainGlyph(for: worst))\(issues)")
    } else {
        print(plainGlyph(for: worst))
    }
    exit(0)
}

func cmdWait(name: String, timeout: TimeInterval, interval: TimeInterval) async {
    guard let snapshot = loadCache() else { return }
    guard let source = findSource(name, in: snapshot) else {
        fail("no source matching \u{201C}\(name)\u{201D}", code: 2)
    }
    let fetcher = CLIFetcher()
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        let (indicator, description) = await fetcher.liveStatus(baseURL: source.url)
        if indicator == "none" {
            print("\(glyph(for: "none")) \(source.name) is operational")
            exit(0)
        }
        print("\(glyph(for: indicator)) \(source.name): \(description) — retrying in \(Int(interval))s")
        if Date() >= deadline {
            fail("timed out after \(Int(timeout))s waiting for \(source.name)", code: 1)
        }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

let helpText = """
    statusbar — every status page you care about, from the terminal

    USAGE
      statusbar <command> [options]

    COMMANDS
      status [name]     Current status for all sources or one (exit 0 ok, 1 issues)
      list              Alias for status
      wait <name>       Block until a source is operational again (live polling)
      prompt            Compact glyph for shell prompts (e.g. "●" or "▲1")
      refresh           Ask the running app to refresh now
      open [name]       Open the popover, optionally at a source
      add <url> [name]  Add a source through the app
      remove <name>     Remove a source through the app
      cache-path        Print the status cache location

    OPTIONS
      --json            Machine-readable output (status)
      --all             Ignore a .statusbar repo scope
      --fresh           Fetch live from providers instead of the cache (status)
      --timeout <sec>   wait: give up after N seconds (default 1800)
      --interval <sec>  wait: poll every N seconds (default 30)

    The cache at ~/.cache/statusbar/status.json is refreshed by the app on
    every poll; `status` reads it instantly with no network.

    Drop a `.statusbar` file in a repo (one source name per line, # for
    comments) and `status`/`prompt` scope to that project's dependencies.
    """

// MARK: - Entry

@main
struct StatusBarCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print(helpText)
            exit(64)
        }
        args.removeFirst()

        let json = args.contains("--json")
        let fresh = args.contains("--fresh")
        let allFlag = args.contains("--all")
        func optionValue(_ flag: String) -> String? {
            guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        let positional = args.filter { !$0.hasPrefix("--") && $0 != optionValue("--timeout") && $0 != optionValue("--interval") }

        switch command {
        case "status", "list":
            await cmdStatus(name: positional.first, json: json, fresh: fresh, allFlag: allFlag)
        case "prompt":
            cmdPrompt(allFlag: allFlag)
        case "wait":
            guard let name = positional.first else { fail("usage: statusbar wait <name>") }
            let timeout = TimeInterval(optionValue("--timeout") ?? "") ?? 1800
            let interval = TimeInterval(optionValue("--interval") ?? "") ?? 30
            await cmdWait(name: name, timeout: max(timeout, 1), interval: max(interval, 5))
        case "refresh":
            openURLScheme("statusbar://refresh")
            print("refresh requested")
        case "open":
            if let name = positional.first,
                let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            {
                openURLScheme("statusbar://open?source=\(encoded)")
            } else {
                openURLScheme("statusbar://open")
            }
        case "add":
            guard let url = positional.first,
                let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else { fail("usage: statusbar add <url> [name]") }
            var scheme = "statusbar://add?url=\(encodedURL)"
            if positional.count > 1,
                let encodedName = positional[1].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            {
                scheme += "&name=\(encodedName)"
            }
            openURLScheme(scheme)
            print("add requested")
        case "remove":
            guard let name = positional.first,
                let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else { fail("usage: statusbar remove <name>") }
            openURLScheme("statusbar://remove?name=\(encoded)")
            print("remove requested")
        case "cache-path":
            print(StatusCache.defaultURL.path)
        case "help", "--help", "-h":
            print(helpText)
        default:
            fail("unknown command \u{201C}\(command)\u{201D} — see `statusbar help`")
        }
    }
}
