@preconcurrency import Flutter
import SwiftUI

struct FlutterModuleContainerView: UIViewControllerRepresentable {
    let route: String?

    func makeUIViewController(context: Context) -> FlutterViewController {
        OmnibotFlutterEngineCoordinator.shared.makeViewController(route: route)
    }

    func updateUIViewController(_ uiViewController: FlutterViewController, context: Context) {}
}
