import SwiftUI
import UIKit

@objc(OmnibotHostingBridge)
final class OmnibotHostingBridge: NSObject {
    @MainActor
    @objc static func makeRootViewController() -> UIViewController {
        let controller = UIHostingController(rootView: OmnibotRootView())
        controller.view.backgroundColor = .systemBackground
        return controller
    }
}
