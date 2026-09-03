import Foundation

class XRDLoader: NSObject {
    @objc static func activate() {
        XRDOverlay.shared.setup()
    }
}
