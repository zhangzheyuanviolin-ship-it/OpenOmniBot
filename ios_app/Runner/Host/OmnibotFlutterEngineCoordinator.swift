@preconcurrency import Flutter
import Foundation
import FlutterPluginRegistrant

@MainActor
final class OmnibotFlutterEngineCoordinator {
    static let shared = OmnibotFlutterEngineCoordinator()

    private let mainEngine = FlutterEngine(name: "omnibot.main.engine")
    private let settingsEngine = FlutterEngine(name: "omnibot.settings.engine")

    private var startedRoles: Set<String> = []

    private init() {}

    private func engine(for role: FlutterModuleRole) -> FlutterEngine {
        switch role {
        case .main:
            return mainEngine
        case .settings:
            return settingsEngine
        }
    }

    @discardableResult
    func startIfNeeded(role: FlutterModuleRole = .main, initialRoute: String? = nil) -> Bool {
        let roleKey = "\(role)"
        guard startedRoles.contains(roleKey) == false else { return false }
        let engine = engine(for: role)
        if let initialRoute, initialRoute.isEmpty == false {
            engine.run(withEntrypoint: nil, initialRoute: initialRoute)
        } else {
            engine.run()
        }
        GeneratedPluginRegistrant.register(with: engine)
        AgentBrowserPlatformViewFactory.register(with: engine)
        SpeechRecognitionCoordinator.shared.register(on: engine)
        OmnibotBridgeRegistry.shared.register(on: engine)
        startedRoles.insert(roleKey)
        return true
    }

    func makeViewController(route: String? = nil, role: FlutterModuleRole = .main) -> FlutterViewController {
        let startedNow = startIfNeeded(role: role, initialRoute: route)
        let engine = engine(for: role)
        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        controller.view.backgroundColor = .systemBackground
        if startedNow == false, let route, route.isEmpty == false {
            let routerChannel = FlutterMethodChannel(
                name: "ui_router_channel",
                binaryMessenger: engine.binaryMessenger
            )
            routerChannel.invokeMethod("clearAndNavigateTo", arguments: ["route": route])
        }
        return controller
    }
}

@objc(OmnibotFlutterBootstrap)
final class OmnibotFlutterBootstrap: NSObject {
    @objc static func warmUp() {
        Task { @MainActor in
            OmnibotFlutterEngineCoordinator.shared.startIfNeeded()
        }
    }
}
