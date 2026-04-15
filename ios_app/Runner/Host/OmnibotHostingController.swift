import SwiftUI
import UIKit

@objc(OmnibotHostingBridge)
final class OmnibotHostingBridge: NSObject {
    @MainActor
    @objc static func makeRootViewController() -> UIViewController {
        OmnibotHostingController()
    }
}

@objc(OmnibotHostingController)
final class OmnibotHostingController: UIHostingController<OmnibotRootView> {
    @MainActor
    init() {
        super.init(rootView: OmnibotRootView())
    }

    @MainActor
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: OmnibotRootView())
    }
}
