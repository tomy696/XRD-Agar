import UIKit
import SwiftUI
import Combine

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()

    private weak var gameWindow: UIWindow?
    private var container: XRDPassthroughView?
    private var toggleBtn: ToggleButton?
    private var macroBtn: MacroButton?
    private var menuHosting: UIHostingController<AnyView>?
    private var licenseHosting: UIHostingController<AnyView>?
    private var isMenuVisible = false
    private var macroTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func setup() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let mainWindow = scene.windows.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.setup()
            }
            return
        }

        gameWindow = mainWindow
        installContainer()
        observeLifecycle()
        setupObservers()

        if LicenseManager.shared.isValid {
            showOverlayUI()
        } else {
            showLicenseView()
        }
    }

    private func installContainer() {
        guard let window = gameWindow else { return }
        container?.removeFromSuperview()
        let c = XRDPassthroughView(frame: window.bounds)
        c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(c)
        container = c
    }

    private func ensureContainer() {
        guard let window = gameWindow else { return }
        if container == nil || container?.superview == nil {
            installContainer()
            if LicenseManager.shared.isValid {
                addToggleButton()
                if settings.isMacroEnabled { addMacroButton() }
            }
        }
        if let c = container { window.bringSubviewToFront(c) }
    }

    // MARK: - Observers

    private func setupObservers() {
        settings.$isMacroEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.addMacroButton() }
                else { self?.removeMacroButton() }
            }
            .store(in: &cancellables)

        settings.$macroButtonSize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.updateMacroSize(CGFloat(size))
            }
            .store(in: &cancellables)

        settings.$zoomLevel
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.applyZoom(CGFloat(level))
            }
            .store(in: &cancellables)
    }

    // MARK: - Zoom

    private func applyZoom(_ scale: CGFloat) {
        guard let window = gameWindow,
              let rootView = window.rootViewController?.view else { return }
        for subview in rootView.subviews where subview !== container {
            subview.transform = CGAffineTransform(scaleX: scale, y: scale)
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
            self?.ensureContainer()
        }
    }

    // MARK: - License

    private func showLicenseView() {
        ensureContainer()
        guard let c = container else { return }
        let view = LicenseView(licenseManager: LicenseManager.shared) { [weak self] in
            self?.hideLicenseView()
            self?.showOverlayUI()
        }
        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        hosting.view.frame = c.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        c.addSubview(hosting.view)
        licenseHosting = hosting
    }

    private func hideLicenseView() {
        licenseHosting?.view.removeFromSuperview()
        licenseHosting = nil
    }

    // MARK: - Overlay UI

    private func showOverlayUI() {
        addToggleButton()
    }

    private func addToggleButton() {
        ensureContainer()
        guard let c = container else { return }
        toggleBtn?.removeFromSuperview()

        let screenW = c.bounds.width
        let btn = ToggleButton(frame: CGRect(x: screenW - 52, y: 40, width: 40, height: 40))
        btn.autoresizingMask = [.flexibleLeftMargin]
        btn.onTap = { [weak self] in self?.toggleMenu() }
        c.addSubview(btn)
        toggleBtn = btn
    }

    // MARK: - Macro Button

    private func addMacroButton() {
        ensureContainer()
        guard let c = container else { return }
        macroBtn?.removeFromSuperview()

        let size = CGFloat(settings.macroButtonSize)
        let btn = MacroButton(frame: CGRect(x: 50, y: c.bounds.height - size - 50, width: size, height: size))
        btn.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
        btn.onStart = { [weak self] in self?.startMacro() }
        btn.onStop = { [weak self] in self?.stopMacro() }
        c.addSubview(btn)
        macroBtn = btn
    }

    private func removeMacroButton() {
        stopMacro()
        macroBtn?.removeFromSuperview()
        macroBtn = nil
    }

    private func updateMacroSize(_ size: CGFloat) {
        guard let btn = macroBtn else { return }
        let cx = btn.center.x
        let cy = btn.center.y
        btn.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        btn.center = CGPoint(x: cx, y: cy)
        btn.layer.cornerRadius = size / 2
        btn.setNeedsDisplay()
    }

    // MARK: - Macro

    private func startMacro() {
        settings.isMacroActive = true
        macroTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
    }

    private func stopMacro() {
        settings.isMacroActive = false
        macroTimer?.invalidate()
        macroTimer = nil
    }

    // MARK: - Menu

    private func toggleMenu() {
        if isMenuVisible { hideMenu() } else { showMenu() }
        isMenuVisible.toggle()
    }

    private func showMenu() {
        ensureContainer()
        guard let c = container else { return }

        let menu = ModMenuView(settings: settings, botEngine: botEngine)
        let hosting = UIHostingController(rootView: AnyView(menu))
        hosting.view.backgroundColor = .clear

        let menuW: CGFloat = 220
        let menuH: CGFloat = 310
        let x = c.bounds.width - menuW - 8
        let y: CGFloat = 85
        let finalFrame = CGRect(x: x, y: y, width: menuW, height: menuH)
        hosting.view.frame = finalFrame.offsetBy(dx: 0, dy: -12)
        hosting.view.alpha = 0

        c.addSubview(hosting.view)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragMenu(_:)))
        hosting.view.addGestureRecognizer(pan)

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            hosting.view.alpha = 1
            hosting.view.frame = finalFrame
        }

        menuHosting = hosting
    }

    private func hideMenu() {
        guard let hosting = menuHosting else { return }
        UIView.animate(withDuration: 0.15, animations: {
            hosting.view.alpha = 0
            hosting.view.frame = hosting.view.frame.offsetBy(dx: 0, dy: -10)
        }) { _ in
            hosting.view.removeFromSuperview()
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

// MARK: - Passthrough View

class XRDPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for sub in subviews where !sub.isHidden && sub.alpha > 0.01 && sub.isUserInteractionEnabled {
            let p = convert(point, to: sub)
            if sub.point(inside: p, with: event) {
                return true
            }
        }
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self { return nil }
        return result
    }
}

// MARK: - Toggle Button (draggable + tappable)

class ToggleButton: UIView {
    var onTap: (() -> Void)?
    private var startCenter: CGPoint = .zero
    private var moved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
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

// MARK: - Macro Button (spider web style, draggable)

class MacroButton: UIView {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.cornerRadius = frame.width / 2
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = min(bounds.width, bounds.height) / 2

        ctx.setFillColor(UIColor(white: 0.18, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        ctx.setStrokeColor(UIColor(white: 0.55, alpha: 0.45).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let spokes = 8
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.3).cgColor)
        ctx.setLineWidth(1)
        for i in 0..<spokes {
            let a = CGFloat(i) * .pi * 2 / CGFloat(spokes) - .pi / 2
            ctx.move(to: c)
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * (r - 5), y: c.y + sin(a) * (r - 5)))
        }
        ctx.strokePath()

        for ring in 1...3 {
            let ringR = (r - 5) * CGFloat(ring) / 4
            let path = UIBezierPath()
            for i in 0..<spokes {
                let a = CGFloat(i) * .pi * 2 / CGFloat(spokes) - .pi / 2
                let p = CGPoint(x: c.x + cos(a) * ringR, y: c.y + sin(a) * ringR)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.close()
            path.lineWidth = 0.8
            UIColor(white: 1, alpha: 0.2).setStroke()
            path.stroke()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onStart?()
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.alpha = 0.85
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
            self.transform = .identity
            self.alpha = 1
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onStop?()
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}
