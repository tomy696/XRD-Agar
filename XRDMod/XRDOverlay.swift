import UIKit
import SwiftUI
import Combine
import ObjectiveC

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()

    private var overlayWindow: XRDWindow?
    private var toggleBtn: ToggleButton?
    private var macroBtn: MacroButton?
    private var menuHosting: UIHostingController<AnyView>?
    private var licenseHosting: UIHostingController<AnyView>?
    private var isMenuVisible = false
    private var macroTimer: Timer?

    weak var capturedGameSocket: URLSessionWebSocketTask?
    private static var didSwizzle = false

    func setup() {
        guard UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.setup()
            }
            return
        }

        createWindow()
        observeLifecycle()
        hookNetwork()

        if LicenseManager.shared.isValid {
            showOverlayUI()
        } else {
            showLicenseView()
        }
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivated),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivated),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    @objc private func appActivated() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.overlayWindow == nil || self.overlayWindow?.isHidden == true {
                self.createWindow()
            }
            if self.toggleBtn == nil && LicenseManager.shared.isValid {
                self.showOverlayUI()
            }
            self.overlayWindow?.isHidden = false
        }
    }

    // MARK: - Network Hook (best-effort macro support)

    private func hookNetwork() {
        guard !XRDOverlay.didSwizzle else { return }
        XRDOverlay.didSwizzle = true

        let orig = #selector(URLSessionTask.resume)
        let swiz = #selector(URLSessionTask.xrd_resume)
        guard let origMethod = class_getInstanceMethod(URLSessionTask.self, orig),
              let swizMethod = class_getInstanceMethod(URLSessionTask.self, swiz)
        else { return }
        method_exchangeImplementations(origMethod, swizMethod)
    }

    // MARK: - Window

    private func createWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }

        let w = XRDWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let vc = XRDRootVC()
        vc.view.backgroundColor = .clear
        w.rootViewController = vc
        w.isHidden = false
        overlayWindow = w
    }

    // MARK: - License

    private func showLicenseView() {
        guard let rootVC = overlayWindow?.rootViewController else { return }
        let view = LicenseView(licenseManager: LicenseManager.shared) { [weak self] in
            self?.hideLicenseView()
            self?.showOverlayUI()
        }
        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        hosting.view.frame = rootVC.view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rootVC.addChild(hosting)
        rootVC.view.addSubview(hosting.view)
        hosting.didMove(toParent: rootVC)
        licenseHosting = hosting
    }

    private func hideLicenseView() {
        licenseHosting?.willMove(toParent: nil)
        licenseHosting?.view.removeFromSuperview()
        licenseHosting?.removeFromParent()
        licenseHosting = nil
    }

    // MARK: - Overlay UI

    private func showOverlayUI() {
        addToggleButton()
        addMacroButton()
    }

    private func addToggleButton() {
        guard let rv = overlayWindow?.rootViewController?.view else { return }
        toggleBtn?.removeFromSuperview()

        let btn = ToggleButton(frame: CGRect(x: rv.bounds.width - 52, y: 50, width: 40, height: 40))
        btn.onTap = { [weak self] in self?.toggleMenu() }
        rv.addSubview(btn)
        toggleBtn = btn
    }

    private func addMacroButton() {
        guard let rv = overlayWindow?.rootViewController?.view else { return }
        macroBtn?.removeFromSuperview()

        let btn = MacroButton(frame: CGRect(x: 60, y: rv.bounds.height - 90, width: 50, height: 50))
        btn.onStart = { [weak self] in self?.startMacro() }
        btn.onStop = { [weak self] in self?.stopMacro() }
        rv.addSubview(btn)
        macroBtn = btn
    }

    // MARK: - Macro

    private func startMacro() {
        settings.isMacroActive = true
        macroTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.sendEjectPacket()
        }
    }

    private func stopMacro() {
        settings.isMacroActive = false
        macroTimer?.invalidate()
        macroTimer = nil
    }

    private func sendEjectPacket() {
        guard let ws = capturedGameSocket, ws.state == .running else { return }
        ws.send(.data(Data([21]))) { _ in }
    }

    // MARK: - Menu

    private func toggleMenu() {
        if isMenuVisible { hideMenu() } else { showMenu() }
        isMenuVisible.toggle()
    }

    private func showMenu() {
        guard let rootVC = overlayWindow?.rootViewController else { return }
        let rv = rootVC.view!

        let menu = ModMenuView(settings: settings, botEngine: botEngine)
        let hosting = UIHostingController(rootView: AnyView(menu))
        hosting.view.backgroundColor = .clear

        let menuW: CGFloat = 220
        let menuH: CGFloat = 300
        let x = rv.bounds.width - menuW - 12
        let y = (rv.bounds.height - menuH) / 2
        hosting.view.frame = CGRect(x: x, y: y, width: menuW, height: menuH)

        rootVC.addChild(hosting)
        rv.addSubview(hosting.view)
        hosting.didMove(toParent: rootVC)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragMenu(_:)))
        hosting.view.addGestureRecognizer(pan)

        hosting.view.alpha = 0
        hosting.view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            hosting.view.alpha = 1
            hosting.view.transform = .identity
        }

        menuHosting = hosting
    }

    private func hideMenu() {
        guard let hosting = menuHosting else { return }
        UIView.animate(withDuration: 0.15, animations: {
            hosting.view.alpha = 0
            hosting.view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }) { _ in
            hosting.willMove(toParent: nil)
            hosting.view.removeFromSuperview()
            hosting.removeFromParent()
        }
        menuHosting = nil
    }

    @objc private func dragMenu(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: v.superview)
        v.center = CGPoint(x: v.center.x + t.x, y: v.center.y + t.y)
        g.setTranslation(.zero, in: v.superview)
    }
}

// MARK: - Passthrough Window

class XRDWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self || result === rootViewController?.view {
            return nil
        }
        return result
    }
}

// MARK: - Root VC

class XRDRootVC: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}

// MARK: - Toggle Button (draggable + tappable)

class ToggleButton: UIView {
    var onTap: (() -> Void)?
    private var startCenter: CGPoint = .zero
    private var moved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = frame.width / 2
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(red: 0.459, green: 0.318, blue: 0.957, alpha: 1).cgColor
        clipsToBounds = true

        let lbl = UILabel(frame: bounds)
        lbl.text = "XRD"
        lbl.font = .systemFont(ofSize: 10, weight: .black)
        lbl.textColor = .white
        lbl.textAlignment = .center
        lbl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(lbl)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        startCenter = center
        moved = false
        UIView.animate(withDuration: 0.1) { self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        center = CGPoint(x: center.x + loc.x - prev.x, y: center.y + loc.y - prev.y)
        if hypot(center.x - startCenter.x, center.y - startCenter.y) > 6 { moved = true }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.transform = .identity }
        if !moved { onTap?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.transform = .identity }
    }
}

// MARK: - Macro Button (hold = feed, draggable)

class MacroButton: UIView {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 0.65)
        layer.cornerRadius = frame.width / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.8).cgColor
        clipsToBounds = true

        let lbl = UILabel(frame: bounds)
        lbl.text = "W"
        lbl.font = .systemFont(ofSize: 18, weight: .black)
        lbl.textColor = .white
        lbl.textAlignment = .center
        lbl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(lbl)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onStart?()
        UIView.animate(withDuration: 0.1) {
            self.backgroundColor = UIColor.red.withAlphaComponent(0.85)
            self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        center = CGPoint(x: center.x + loc.x - prev.x, y: center.y + loc.y - prev.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onStop?()
        UIView.animate(withDuration: 0.1) {
            self.backgroundColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 0.65)
            self.transform = .identity
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onStop?()
        UIView.animate(withDuration: 0.1) {
            self.backgroundColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 0.65)
            self.transform = .identity
        }
    }
}

// MARK: - URLSessionTask Swizzle

extension URLSessionTask {
    @objc func xrd_resume() {
        if let ws = self as? URLSessionWebSocketTask,
           let url = ws.originalRequest?.url?.absoluteString,
           (url.contains("agar") || url.contains("miniclip")) {
            XRDOverlay.shared.capturedGameSocket = ws
        }
        xrd_resume()
    }
}
