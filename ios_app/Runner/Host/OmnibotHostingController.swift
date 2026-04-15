import SwiftUI
import UIKit

@objc(OmnibotHostingController)
final class OmnibotHostingController: UIHostingController<OmnibotRootView> {
    init() {
        super.init(rootView: OmnibotRootView())
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: OmnibotRootView())
    }
}
