import UIKit

/// Holds the app in landscape while Couch mode shows, and gives the app back
/// its usual orientations (Info.plist's) when it closes: when the library is
/// chosen instead, or while a game session replaces it.
@MainActor enum CouchOrientation {
    /// What the app allows when Couch mode is not showing: the orientations
    /// Info.plist lists for this device, as UIKit would use without a delegate.
    static let usual: UIInterfaceOrientationMask = {
        let info = Bundle.main.infoDictionary ?? [:]
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let names = (pad ? info["UISupportedInterfaceOrientations~ipad"] as? [String] : nil)
            ?? info["UISupportedInterfaceOrientations"] as? [String] ?? []
        let masks: [String: UIInterfaceOrientationMask] = [
            "UIInterfaceOrientationPortrait": .portrait,
            "UIInterfaceOrientationPortraitUpsideDown": .portraitUpsideDown,
            "UIInterfaceOrientationLandscapeLeft": .landscapeLeft,
            "UIInterfaceOrientationLandscapeRight": .landscapeRight,
        ]
        let mask = names.compactMap { masks[$0] }.reduce(into: UIInterfaceOrientationMask()) { $0.formUnion($1) }
        return mask.isEmpty ? .allButUpsideDown : mask
    }()

    private(set) static var allowed: UIInterfaceOrientationMask = usual

    /// Landscape on (Couch mode appears) or back to the usual orientations.
    static func hold(landscape: Bool) {
        let next = landscape ? usual.intersection(.landscape) : usual
        guard !next.isEmpty, next != allowed else { return }
        allowed = next
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // Turns the screen now if the phone is held upright; otherwise iOS
            // waits for the next rotation.
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: next)) { error in
                LogStore.shared.log("[couch] orientation request: \(error.localizedDescription)")
            }
        }
    }
}

/// Madeira's app delegate, for the orientations Couch mode holds
/// (MadeiraApp's UIApplicationDelegateAdaptor).
final class MadeiraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { CouchOrientation.allowed }
    }
}
