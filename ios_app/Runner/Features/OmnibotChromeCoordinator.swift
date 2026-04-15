import SwiftUI

@MainActor
final class OmnibotChromeCoordinator: ObservableObject {
    static let shared = OmnibotChromeCoordinator()

    @Published private(set) var isBottomTabBarHidden = false

    private init() {}

    func setBottomTabBarHidden(_ hidden: Bool) {
        guard isBottomTabBarHidden != hidden else { return }
        isBottomTabBarHidden = hidden
    }
}
