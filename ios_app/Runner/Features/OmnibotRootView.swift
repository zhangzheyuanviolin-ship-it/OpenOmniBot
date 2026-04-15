import SwiftUI

struct OmnibotRootView: View {
    @State private var runtimeStatus: TerminalRuntimeStatusMessage?
    @State private var localModelStatus: LocalModelStatusMessage?
    @State private var installedPackages: [String] = []

    var body: some View {
        NavigationSplitView {
            List {
                Section("Workspace") {
                    let workspace = TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
                    Label(workspace.rootPath, systemImage: "folder")
                    Label(workspace.internalRootPath, systemImage: "internaldrive")
                    Label(workspace.shellRootPath, systemImage: "terminal")
                }

                Section("Capabilities") {
                    capabilityRow("Terminal", enabled: true)
                    capabilityRow("APK Install", enabled: true)
                    capabilityRow("Local Models", enabled: true)
                    capabilityRow("Browser Automation", enabled: true)
                    capabilityRow("External App Automation", enabled: false)
                }

                Section("Runtime") {
                    Label(runtimeStatus?.message ?? "Preparing runtime…", systemImage: "shippingbox")
                    Label("Installed packages: \(installedPackages.count)", systemImage: "cube.box")
                    Button("Prepare Runtime") {
                        refreshRuntime(prepare: true)
                    }
                }

                Section("Local Models") {
                    Label(localModelStatus?.apiState ?? "stopped", systemImage: "cpu")
                    Label(localModelStatus?.loadedModelId ?? "No active model", systemImage: "brain")
                    Button("Refresh Models") {
                        refreshModels()
                    }
                }
            }
            .navigationTitle("Omnibot iOS")
            .task {
                refreshRuntime()
                refreshModels()
            }
        } detail: {
            TabView {
                FlutterModuleContainerView(route: "/home/chat")
                    .tabItem {
                        Label("Shared UI", systemImage: "sparkles.rectangle.stack")
                    }

                RuntimeOverviewView(
                    runtimeStatus: runtimeStatus,
                    installedPackages: installedPackages
                )
                .tabItem {
                    Label("Runtime", systemImage: "terminal")
                }

                LocalModelOverviewView(status: localModelStatus)
                    .tabItem {
                        Label("Models", systemImage: "brain.head.profile")
                    }
            }
        }
    }

    private func capabilityRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
            Text(enabled ? "Enabled" : "Unsupported")
                .foregroundStyle(enabled ? .green : .secondary)
        }
    }

    private func refreshRuntime(prepare: Bool = false) {
        Task {
            if prepare {
                runtimeStatus = TerminalRuntimeCoordinator.shared.prepareRuntime()
            } else {
                runtimeStatus = TerminalRuntimeCoordinator.shared.inspectRuntime()
            }
            installedPackages = TerminalRuntimeCoordinator.shared.listInstalledPackagesSync()
        }
    }

    private func refreshModels() {
        Task {
            localModelStatus = await LocalModelCoordinator.shared.statusMessage()
        }
    }
}

private struct RuntimeOverviewView: View {
    let runtimeStatus: TerminalRuntimeStatusMessage?
    let installedPackages: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terminal Runtime")
                    .font(.largeTitle.bold())

                if let runtimeStatus {
                    runtimeTile("Runtime Ready", value: runtimeStatus.runtimeReady ? "Yes" : "No")
                    runtimeTile("Base Packages", value: runtimeStatus.basePackagesReady ? "Ready" : "Missing")
                    runtimeTile("Node", value: runtimeStatus.nodeVersion ?? "Unavailable")
                    runtimeTile("PNPM", value: runtimeStatus.pnpmVersion ?? "Unavailable")
                    runtimeTile("Message", value: runtimeStatus.message)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Installed Packages")
                        .font(.headline)
                    Text(installedPackages.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    private func runtimeTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct LocalModelOverviewView: View {
    let status: LocalModelStatusMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Local Models")
                    .font(.largeTitle.bold())

                runtimeTile("API State", value: status?.apiState ?? "stopped")
                runtimeTile("Backend", value: status?.backend ?? "llama.cpp")
                runtimeTile("Loaded Model", value: status?.loadedModelId ?? "None")
                runtimeTile("Endpoint", value: status?.baseUrl ?? "http://127.0.0.1:9099")
            }
            .padding(24)
        }
    }

    private func runtimeTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
