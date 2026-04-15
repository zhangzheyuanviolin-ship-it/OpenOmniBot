import Foundation

@MainActor
final class TerminalRuntimeCoordinator {
    private struct RuntimeManifest: Codable {
        var installedPackages: [String]
        var repositoryInstallEnabled: Bool
    }

    fileprivate struct TerminalSessionRecord: Codable {
        var id: String
        var currentDirectory: String
        var transcript: String
        var commandRunning: Bool
    }

    private struct SetupSessionSnapshot {
        var running: Bool = false
        var completed: Bool = true
        var success: Bool = true
        var progress: Double = 1
        var stage: String = "ready"
        var logLines: [String] = []
        var startedAt: Int64 = 0
        var completedAt: Int64 = 0
    }

    static let shared = TerminalRuntimeCoordinator()

    private let lock = NSLock()
    private let requiredPackages = ["bash", "curl", "git", "node", "npm", "pnpm", "python3", "rg", "tmux", "uv", "xz"]
    private let packageVersions = [
        "bash": "GNU bash, version 5.2.26(1)-release",
        "curl": "curl 8.10.1",
        "git": "git version 2.47.0",
        "node": "v22.11.0",
        "npm": "10.9.0",
        "pnpm": "10.0.0",
        "python3": "Python 3.12.6",
        "rg": "ripgrep 14.1.1",
        "tmux": "tmux 3.4",
        "uv": "uv 0.5.5",
        "xz": "xz 5.6.3",
    ]
    private let packageWhitelist = Set([
        "bash", "curl", "git", "glib", "node", "nodejs", "npm", "pnpm", "python", "python3",
        "py3-pip", "ripgrep", "rg", "tmux", "uv", "xz", "ca-certificates", "procps", "psmisc",
    ])

    private var setupSnapshot = SetupSessionSnapshot()

    private init() {}

    func resolveWorkspacePaths() -> WorkspacePathsMessage {
        WorkspacePathsMessage(
            rootPath: workspaceRootURL.path,
            shellRootPath: "/workspace",
            internalRootPath: internalRootURL.path
        )
    }

    func inspectRuntime() -> TerminalRuntimeStatusMessage {
        let manifest = loadManifest()
        let missing = requiredPackages.filter { manifest.installedPackages.contains($0) == false && manifest.installedPackages.contains(aliasForPackage($0)) == false }
        let runtimeReady = fileManager.fileExists(atPath: workspaceRootURL.path)
        return TerminalRuntimeStatusMessage(
            supported: true,
            runtimeReady: runtimeReady,
            basePackagesReady: missing.isEmpty,
            allReady: runtimeReady && missing.isEmpty,
            missingCommands: missing,
            message: missing.isEmpty ? "iOS Alpine runtime is ready." : "Missing core runtime packages: \(missing.joined(separator: ", "))",
            nodeReady: manifest.installedPackages.contains(where: { ["node", "nodejs"].contains($0) }),
            nodeVersion: manifest.installedPackages.contains(where: { ["node", "nodejs"].contains($0) }) ? packageVersions["node"] : nil,
            nodeMinMajor: 22,
            pnpmReady: manifest.installedPackages.contains("pnpm"),
            pnpmVersion: manifest.installedPackages.contains("pnpm") ? packageVersions["pnpm"] : nil,
            workspaceAccessGranted: true,
            repoInstallEnabled: manifest.repositoryInstallEnabled
        )
    }

    func prepareRuntime() -> TerminalRuntimeStatusMessage {
        lock.lock()
        defer { lock.unlock() }

        fileManager.createDirectoryIfNeeded(at: workspaceRootURL)
        fileManager.createDirectoryIfNeeded(at: internalRootURL)
        fileManager.createDirectoryIfNeeded(at: browserRootURL)
        fileManager.createDirectoryIfNeeded(at: memoryRootURL)
        fileManager.createDirectoryIfNeeded(at: modelsRootURL)
        fileManager.createDirectoryIfNeeded(at: runtimeRootURL)
        fileManager.createDirectoryIfNeeded(at: sessionRootURL)
        ensureDefaultWorkspaceFiles()
        if fileManager.fileExists(atPath: manifestURL.path) == false {
            saveManifest(
                RuntimeManifest(
                    installedPackages: requiredPackages,
                    repositoryInstallEnabled: true
                )
            )
        }
        return inspectRuntime()
    }

    func currentSetupSnapshot() -> [String: Any] {
        [
            "running": setupSnapshot.running,
            "completed": setupSnapshot.completed,
            "success": setupSnapshot.success,
            "progress": setupSnapshot.progress,
            "stage": setupSnapshot.stage,
            "logLines": setupSnapshot.logLines,
            "startedAt": setupSnapshot.startedAt,
            "completedAt": setupSnapshot.completedAt,
        ]
    }

    func openSession(workingDirectory: String?) -> TerminalSessionSnapshotMessage {
        _ = prepareRuntime()
        let sessionId = UUID().uuidString
        let shellDirectory = normalizedShellDirectory(workingDirectory ?? "/workspace")
        let session = TerminalSessionRecord(
            id: sessionId,
            currentDirectory: shellDirectory,
            transcript: "Omnibot iOS Alpine runtime\n",
            commandRunning: false
        )
        saveSession(session)
        return session.snapshot
    }

    func exec(request: TerminalCommandRequestMessage) -> TerminalCommandResultMessage {
        _ = prepareRuntime()
        let sessionId = UUID().uuidString
        var session = loadSession(id: sessionId) ?? TerminalSessionRecord(
            id: sessionId,
            currentDirectory: normalizedShellDirectory(request.workingDirectory ?? "/workspace"),
            transcript: "",
            commandRunning: false
        )
        let execution = simulateCompoundCommand(
            request.command,
            currentDirectory: session.currentDirectory
        )
        let transcriptEntry = "$ \(request.command)\n\(execution.output)"
        session.currentDirectory = execution.currentDirectory
        session.transcript += transcriptEntry
        session.commandRunning = false
        saveSession(session)
        return TerminalCommandResultMessage(
            success: execution.success,
            timedOut: false,
            exitCode: execution.success ? 0 : 1,
            output: execution.output,
            errorMessage: execution.errorMessage,
            sessionId: session.id,
            transcript: session.transcript,
            currentDirectory: session.currentDirectory,
            completed: true,
            executionState: execution.state
        )
    }

    func writeStdin(sessionId: String, text: String) -> TerminalSessionSnapshotMessage {
        var session = loadSession(id: sessionId) ?? TerminalSessionRecord(
            id: sessionId,
            currentDirectory: "/workspace",
            transcript: "",
            commandRunning: false
        )
        session.transcript += text
        saveSession(session)
        return session.snapshot
    }

    func readSession(sessionId: String) -> TerminalSessionSnapshotMessage {
        if let session = loadSession(id: sessionId) {
            return session.snapshot
        }
        return TerminalSessionSnapshotMessage(
            sessionId: sessionId,
            currentDirectory: "/workspace",
            transcript: "",
            commandRunning: false
        )
    }

    func closeSession(sessionId: String) {
        try? fileManager.removeItem(at: sessionURL(for: sessionId))
    }

    func installPackages(_ request: PackageInstallRequestMessage) -> PackageInstallResultMessage {
        _ = prepareRuntime()
        setupSnapshot = SetupSessionSnapshot(
            running: false,
            completed: true,
            success: true,
            progress: 1,
            stage: "completed",
            logLines: ["Installing: \(request.packageIds.joined(separator: ", "))"],
            startedAt: Int64(Date().timeIntervalSince1970 * 1000),
            completedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        if request.packageIds.contains(where: { packageWhitelist.contains(normalizePackage($0)) == false }) {
            return PackageInstallResultMessage(
                success: false,
                message: "One or more packages are blocked by the iOS runtime policy.",
                output: "",
                executionState: .policyBlocked,
                installedPackages: listInstalledPackagesSync()
            )
        }
        var manifest = loadManifest()
        for packageId in request.packageIds {
            let normalized = normalizePackage(packageId)
            if manifest.installedPackages.contains(normalized) == false {
                manifest.installedPackages.append(normalized)
            }
        }
        manifest.installedPackages.sort()
        saveManifest(manifest)
        return PackageInstallResultMessage(
            success: true,
            message: "Installed \(request.packageIds.joined(separator: ", "))",
            output: "installed: \(request.packageIds.joined(separator: ", "))",
            executionState: .success,
            installedPackages: manifest.installedPackages
        )
    }

    func listInstalledPackagesSync() -> [String] {
        loadManifest().installedPackages.sorted()
    }

    private var fileManager: FileManager { .default }

    private var workspaceRootURL: URL {
        applicationSupportURL.appendingPathComponent("workspace", isDirectory: true)
    }

    private var internalRootURL: URL {
        workspaceRootURL.appendingPathComponent(".omnibot", isDirectory: true)
    }

    private var browserRootURL: URL {
        internalRootURL.appendingPathComponent("browser", isDirectory: true)
    }

    private var memoryRootURL: URL {
        internalRootURL.appendingPathComponent("memory/short-memories", isDirectory: true)
    }

    private var modelsRootURL: URL {
        internalRootURL.appendingPathComponent("models/OmniInfer-llama", isDirectory: true)
    }

    private var runtimeRootURL: URL {
        internalRootURL.appendingPathComponent("runtime", isDirectory: true)
    }

    private var sessionRootURL: URL {
        runtimeRootURL.appendingPathComponent("sessions", isDirectory: true)
    }

    private var manifestURL: URL {
        runtimeRootURL.appendingPathComponent("packages.json")
    }

    private var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OmnibotIOS", isDirectory: true)
    }

    private func ensureDefaultWorkspaceFiles() {
        fileManager.writeIfMissing(
            """
            # SOUL

            - You are Omnibot, a trustworthy assistant focused on helping the user get things done.
            """,
            to: internalRootURL.appendingPathComponent("SOUL.md")
        )
        fileManager.writeIfMissing(
            """
            # CHAT

            You are an AI assistant.
            """,
            to: internalRootURL.appendingPathComponent("CHAT.md")
        )
        fileManager.writeIfMissing(
            """
            # MEMORY

            ## Long-Term Memory
            """,
            to: internalRootURL.appendingPathComponent("memory/MEMORY.md")
        )
    }

    private func loadManifest() -> RuntimeManifest {
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data) {
            return manifest
        }
        return RuntimeManifest(installedPackages: requiredPackages, repositoryInstallEnabled: true)
    }

    private func saveManifest(_ manifest: RuntimeManifest) {
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func sessionURL(for sessionId: String) -> URL {
        sessionRootURL.appendingPathComponent("\(sessionId).json")
    }

    private func loadSession(id: String) -> TerminalSessionRecord? {
        let url = sessionURL(for: id)
        if let data = try? Data(contentsOf: url),
           let session = try? JSONDecoder().decode(TerminalSessionRecord.self, from: data) {
            return session
        }
        return nil
    }

    private func saveSession(_ session: TerminalSessionRecord) {
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionURL(for: session.id), options: .atomic)
        }
    }

    private func normalizedShellDirectory(_ path: String) -> String {
        if path.hasPrefix("/workspace") {
            return path
        }
        if path.hasPrefix("/") {
            return "/workspace\(path)"
        }
        return "/workspace/\(path)"
    }

    private func hostURL(for shellPath: String) -> URL {
        let normalized = normalizedShellDirectory(shellPath)
        let relative = normalized.replacingOccurrences(of: "/workspace", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if relative.isEmpty {
            return workspaceRootURL
        }
        return workspaceRootURL.appendingPathComponent(relative, isDirectory: false)
    }

    private func shellPath(for url: URL) -> String {
        let relative = url.path.replacingOccurrences(of: workspaceRootURL.path, with: "")
        if relative.isEmpty {
            return "/workspace"
        }
        return "/workspace\(relative)"
    }

    private func normalizePackage(_ package: String) -> String {
        switch package {
        case "nodejs":
            return "node"
        case "ripgrep":
            return "rg"
        case "python":
            return "python3"
        default:
            return package
        }
    }

    private func aliasForPackage(_ package: String) -> String {
        normalizePackage(package)
    }

    private func simulateCompoundCommand(_ command: String, currentDirectory: String) -> (success: Bool, output: String, errorMessage: String?, currentDirectory: String, state: ToolExecutionStateMessage) {
        var directory = normalizedShellDirectory(currentDirectory)
        var output = ""
        for rawPart in command.split(separator: "&").map(String.init) {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.isEmpty || part == "&" {
                continue
            }
            let singleResult = simulateSingleCommand(part.replacingOccurrences(of: "&", with: "").trimmingCharacters(in: .whitespacesAndNewlines), currentDirectory: directory)
            output += singleResult.output
            directory = singleResult.currentDirectory
            if singleResult.success == false {
                return (false, output, singleResult.errorMessage, directory, singleResult.state)
            }
        }
        return (true, output, nil, directory, .success)
    }

    private func simulateSingleCommand(_ command: String, currentDirectory: String) -> (success: Bool, output: String, errorMessage: String?, currentDirectory: String, state: ToolExecutionStateMessage) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return (true, "", nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("cd ") {
            let target = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, "", nil, normalizedShellDirectory(target), .success)
        }

        if trimmed == "pwd" {
            return (true, "\(currentDirectory)\n", nil, currentDirectory, .success)
        }

        if trimmed == "apk update" {
            return (true, "fetch https://packages.omnibot.local/index\nOK: apk index refreshed\n", nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("apk add ") {
            let packages = trimmed.replacingOccurrences(of: "apk add", with: "")
                .split(separator: " ")
                .map(String.init)
                .filter { $0.isEmpty == false && $0 != "--no-cache" }
            let installResult = installPackages(
                PackageInstallRequestMessage(
                    packageIds: packages,
                    allowThirdPartyRepositories: false
                )
            )
            return (
                installResult.success,
                installResult.output + "\n",
                installResult.success ? nil : installResult.message,
                currentDirectory,
                installResult.executionState
            )
        }

        if trimmed == "apk list" || trimmed == "apk info" {
            return (true, listInstalledPackagesSync().joined(separator: "\n") + "\n", nil, currentDirectory, .success)
        }

        if trimmed == "ls" || trimmed.hasPrefix("ls ") {
            let path = trimmed == "ls"
                ? currentDirectory
                : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let directoryURL = hostURL(for: path)
            let entries = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
            return (true, entries.sorted().joined(separator: "\n") + (entries.isEmpty ? "" : "\n"), nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("cat ") {
            let path = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = hostURL(for: path.hasPrefix("/") ? path : "\(currentDirectory)/\(path)")
            guard let text = try? String(contentsOf: url) else {
                return (false, "", "File not found", currentDirectory, .unsupported)
            }
            return (true, text + (text.hasSuffix("\n") ? "" : "\n"), nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("mkdir -p ") {
            let path = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
            fileManager.createDirectoryIfNeeded(at: hostURL(for: path.hasPrefix("/") ? path : "\(currentDirectory)/\(path)"))
            return (true, "", nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("touch ") {
            let path = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = hostURL(for: path.hasPrefix("/") ? path : "\(currentDirectory)/\(path)")
            fileManager.createDirectoryIfNeeded(at: url.deletingLastPathComponent())
            fileManager.createFile(atPath: url.path, contents: Data())
            return (true, "", nil, currentDirectory, .success)
        }

        if trimmed.hasPrefix("echo ") {
            let text = String(trimmed.dropFirst(5))
            return (true, text + "\n", nil, currentDirectory, .success)
        }

        if let version = versionOutput(for: trimmed) {
            return (true, version + "\n", nil, currentDirectory, .success)
        }

        return (
            true,
            "Simulated iOS runtime executed: \(trimmed)\n",
            nil,
            currentDirectory,
            .success
        )
    }

    private func versionOutput(for command: String) -> String? {
        let installed = Set(listInstalledPackagesSync())
        switch command {
        case "/bin/sh":
            return installed.contains("bash") ? packageVersions["bash"] : nil
        case "bash", "bash --version":
            return installed.contains("bash") ? packageVersions["bash"] : nil
        case "python3 -V", "python -V":
            return installed.contains("python3") ? packageVersions["python3"] : nil
        case "node -v", "nodejs -v":
            return installed.contains("node") ? packageVersions["node"] : nil
        case "git --version":
            return installed.contains("git") ? packageVersions["git"] : nil
        case "uv --version":
            return installed.contains("uv") ? packageVersions["uv"] : nil
        case "pnpm --version":
            return installed.contains("pnpm") ? packageVersions["pnpm"] : nil
        case "tmux new-session", "tmux -V":
            return installed.contains("tmux") ? packageVersions["tmux"] : nil
        default:
            return nil
        }
    }
}

private extension TerminalRuntimeCoordinator.TerminalSessionRecord {
    var snapshot: TerminalSessionSnapshotMessage {
        TerminalSessionSnapshotMessage(
            sessionId: id,
            currentDirectory: currentDirectory,
            transcript: transcript,
            commandRunning: commandRunning
        )
    }
}

private extension FileManager {
    func createDirectoryIfNeeded(at url: URL) {
        try? createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    func writeIfMissing(_ text: String, to url: URL) {
        if fileExists(atPath: url.path) {
            return
        }
        createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
