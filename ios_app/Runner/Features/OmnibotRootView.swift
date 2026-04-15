import SwiftUI
import UIKit

struct OmnibotRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var chromeCoordinator = OmnibotChromeCoordinator.shared
    @State private var runtimeStatus: TerminalRuntimeStatusMessage?
    @State private var localModelStatus: LocalModelStatusMessage?
    @State private var installedPackages: [String] = []
    @State private var selectedCompactTab: CompactTab = .chats

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            HostOverviewPanel(
                runtimeStatus: runtimeStatus,
                localModelStatus: localModelStatus,
                installedPackages: installedPackages,
                onPrepareRuntime: { refreshRuntime(prepare: true) },
                onRefreshModels: refreshModels
            )
        } detail: {
            detailTabs
        }
        .task {
            refreshRuntime()
            refreshModels()
        }
    }

    private var compactLayout: some View {
        ZStack {
            compactTabContent(.chats)
            compactTabContent(.host)
            compactTabContent(.runtime)
            compactTabContent(.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if chromeCoordinator.isBottomTabBarHidden == false {
                CompactTabBar(selection: $selectedCompactTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeCoordinator.isBottomTabBarHidden)
        .task {
            refreshRuntime()
            refreshModels()
        }
    }

    private var detailTabs: some View {
        TabView {
            FlutterModuleContainerView(route: "/home/conversations", role: .main)
                .tabItem {
                    Label("Chats", systemImage: "message")
                }

            RuntimeOverviewView(
                runtimeStatus: runtimeStatus,
                installedPackages: installedPackages
            )
            .tabItem {
                Label("Runtime", systemImage: "terminal")
            }

            FlutterModuleContainerView(route: "/home/settings_root", role: .settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
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

    @ViewBuilder
    private func compactTabContent(_ tab: CompactTab) -> some View {
        Group {
            switch tab {
            case .chats:
                FlutterModuleContainerView(route: "/home/conversations", role: .main)
            case .host:
                NavigationStack {
                    HostOverviewPanel(
                        runtimeStatus: runtimeStatus,
                        localModelStatus: localModelStatus,
                        installedPackages: installedPackages,
                        onPrepareRuntime: { refreshRuntime(prepare: true) },
                        onRefreshModels: refreshModels
                    )
                }
            case .runtime:
                RuntimeOverviewView(
                    runtimeStatus: runtimeStatus,
                    installedPackages: installedPackages
                )
            case .settings:
                FlutterModuleContainerView(route: "/home/settings_root", role: .settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(selectedCompactTab == tab ? 1 : 0)
        .allowsHitTesting(selectedCompactTab == tab)
        .accessibilityHidden(selectedCompactTab != tab)
        .zIndex(selectedCompactTab == tab ? 1 : 0)
    }
}

private enum CompactTab: Int, CaseIterable {
    case chats
    case host
    case runtime
    case settings

    var title: String {
        switch self {
        case .chats:
            "Chats"
        case .host:
            "Host"
        case .runtime:
            "Runtime"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chats:
            "message"
        case .host:
            "iphone.gen3"
        case .runtime:
            "terminal"
        case .settings:
            "gearshape"
        }
    }

    @MainActor
    var tabBarItem: UITabBarItem {
        UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            tag: rawValue
        )
    }
}

private struct CompactTabBar: UIViewRepresentable {
    @Binding var selection: CompactTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar(frame: .zero)
        tabBar.delegate = context.coordinator
        tabBar.items = CompactTab.allCases.map(\.tabBarItem)
        tabBar.isTranslucent = true
        tabBar.unselectedItemTintColor = .secondaryLabel

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }

        updateSelection(on: tabBar)
        return tabBar
    }

    func updateUIView(_ uiView: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        if uiView.items?.count != CompactTab.allCases.count {
            uiView.items = CompactTab.allCases.map(\.tabBarItem)
        }
        updateSelection(on: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITabBar, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        return CGSize(width: targetWidth, height: fittingSize.height)
    }

    private func updateSelection(on tabBar: UITabBar) {
        tabBar.selectedItem = tabBar.items?.first(where: { $0.tag == selection.rawValue })
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<CompactTab>

        init(selection: Binding<CompactTab>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let tab = CompactTab(rawValue: item.tag) else {
                return
            }
            selection.wrappedValue = tab
        }
    }
}

private struct HostOverviewPanel: View {
    let runtimeStatus: TerminalRuntimeStatusMessage?
    let localModelStatus: LocalModelStatusMessage?
    let installedPackages: [String]
    let onPrepareRuntime: () -> Void
    let onRefreshModels: () -> Void

    var body: some View {
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
                Button("Prepare Runtime", action: onPrepareRuntime)
            }

            Section("Local Models") {
                Label(localModelStatus?.apiState ?? "stopped", systemImage: "cpu")
                Label(localModelStatus?.loadedModelId ?? "No active model", systemImage: "brain")
                Button("Refresh Models", action: onRefreshModels)
            }
        }
        .navigationTitle("Omnibot iOS")
    }

    private func capabilityRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
            Text(enabled ? "Enabled" : "Unsupported")
                .foregroundStyle(enabled ? .green : .secondary)
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
