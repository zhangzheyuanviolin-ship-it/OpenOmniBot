@preconcurrency import Flutter
import Foundation
import FlutterPluginRegistrant

@MainActor
final class OmnibotFlutterEngineCoordinator {
    static let shared = OmnibotFlutterEngineCoordinator()

    let engine = FlutterEngine(name: "omnibot.main.engine")

    private var started = false

    private init() {}

    func startIfNeeded() {
        guard started == false else { return }
        engine.run()
        GeneratedPluginRegistrant.register(with: engine)
        AgentBrowserPlatformViewFactory.register(with: engine)
        SpeechRecognitionCoordinator.shared.register(on: engine)
        OmnibotBridgeRegistry.shared.register(on: engine)
        started = true
    }

    func makeViewController(route: String? = nil) -> FlutterViewController {
        startIfNeeded()
        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        controller.view.backgroundColor = .systemBackground
        if let route, route.isEmpty == false {
            engine.navigationChannel.invokeMethod("pushRoute", arguments: route)
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
