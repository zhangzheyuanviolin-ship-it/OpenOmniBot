@preconcurrency import Flutter
import SwiftUI

enum FlutterModuleRole {
    case main
    case settings
}

struct FlutterModuleContainerView: UIViewControllerRepresentable {
    let route: String?
    var role: FlutterModuleRole = .main

    func makeUIViewController(context: Context) -> FlutterViewController {
        OmnibotFlutterEngineCoordinator.shared.makeViewController(route: route, role: role)
    }

    func updateUIViewController(_ uiViewController: FlutterViewController, context: Context) {}
}
