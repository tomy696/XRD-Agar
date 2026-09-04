import UIKit
import SwiftUI
import Combine

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()
    let zoomEngine = ZoomEngine()
    let jsBridge = GameJSBridge()

    private weak var gameWindow: UIWindow?
    private var container: XRDPassthroughView?
    private var toggleBtn: ToggleButton?
    private var macroBtn: MacroButton?
    private var macroDragHandle: MacroDragHandle?
    private var menuHosting: UIHostingController<AnyView>?
    private var licenseHosting: UIHostingController<AnyView>?
    private var isMenuVisible = false
    private var feedTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func setup() {
        NetworkInterceptor.shared.install()

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let mainWindow = scene.windows.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.setup()
            }
            return
        }

        gameWindow = mainWindow
        botEngine.settings = settings
        settings.load()
        installContainer()
        observeLifecycle()
        setupObservers()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.jsBridge.setup(in: mainWindow)
            self.zoomEngine.jsBridge = self.jsBridge
            self.zoomEngine.setup(window: mainWindow)

            self.jsBridge.onConnected = { [weak self] in
                guard let self = self else { return }
                self.zoomEngine.activeMethod = .jsHook
                self.zoomEngine.statusText = "JS zoom active"
                if self.settings.isMacroEnabled {
                    let ms = Int(self.settings.feedInterval * 1000)
                    self.jsBridge.setFeedInterval(ms)
                }
            }
        }

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

    private func setupObservers() {
        settings.$isMacroEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.addMacroButton()
                    self?.startFeedTimer()
                } else {
                    self?.removeMacroButton()
                }
            }
            .store(in: &cancellables)

        settings.$macroPower
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.settings.isMacroEnabled else { return }
                self.startFeedTimer()
            }
            .store(in: &cancellables)

        settings.$macroButtonSize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.updateMacroSize(CGFloat(size))
            }
            .store(in: &cancellables)
    }

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivated),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func appActivated() {
        DispatchQueue.main.async { [weak self] in self?.ensureContainer() }
    }

    // MARK: - Feed Timer

    private func startFeedTimer() {
        feedTimer?.invalidate()
        let interval = settings.feedInterval
        if jsBridge.isConnected {
            jsBridge.setFeedInterval(Int(interval * 1000))
            return
        }
        feedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            if let bridge = self?.jsBridge, bridge.isConnected {
                bridge.sendFeed()
            } else {
                NetworkInterceptor.shared.sendFeed()
            }
        }
    }

    private func stopFeedTimer() {
        feedTimer?.invalidate()
        feedTimer = nil
        if jsBridge.isConnected {
            jsBridge.setFeedInterval(0)
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
        if settings.isMacroEnabled {
            addMacroButton()
            startFeedTimer()
        }
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

    private func addMacroButton() {
        ensureContainer()
        guard let c = container else { return }
        macroBtn?.removeFromSuperview()
        macroDragHandle?.removeFromSuperview()

        let size = CGFloat(settings.macroButtonSize)
        let btn = MacroButton(frame: CGRect(x: 50, y: c.bounds.height - size - 50, width: size, height: size))
        btn.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
        c.addSubview(btn)
        macroBtn = btn

        let handleSize: CGFloat = 24
        let handle = MacroDragHandle(frame: CGRect(
            x: btn.frame.maxX + 4,
            y: btn.frame.midY - handleSize / 2,
            width: handleSize,
            height: handleSize
        ))
        handle.onDrag = { [weak self] delta in
            guard let btn = self?.macroBtn, let h = self?.macroDragHandle else { return }
            btn.center = CGPoint(x: btn.center.x + delta.x, y: btn.center.y + delta.y)
            h.center = CGPoint(x: h.center.x + delta.x, y: h.center.y + delta.y)
        }
        c.addSubview(handle)
        macroDragHandle = handle
    }

    private func removeMacroButton() {
        stopFeedTimer()
        macroBtn?.removeFromSuperview()
        macroBtn = nil
        macroDragHandle?.removeFromSuperview()
        macroDragHandle = nil
    }

    private func updateMacroSize(_ size: CGFloat) {
        guard let btn = macroBtn else { return }
        let cx = btn.center.x
        let cy = btn.center.y
        btn.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        btn.center = CGPoint(x: cx, y: cy)
        btn.layer.cornerRadius = size / 2
        btn.setNeedsDisplay()
        macroDragHandle?.center = CGPoint(x: btn.frame.maxX + 4 + 12, y: cy)
    }

    // MARK: - Menu

    private func toggleMenu() {
        if isMenuVisible { hideMenu() } else { showMenu() }
        isMenuVisible.toggle()
    }

    private func showMenu() {
        ensureContainer()
        guard let c = container else { return }
        let menu = ModMenuView(settings: settings, botEngine: botEngine, zoomEngine: zoomEngine)
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
        }) { _ in hosting.view.removeFromSuperview() }
        menuHosting = nil
    }

    @objc private func dragMenu(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: v.superview)
        v.center = CGPoint(x: v.center.x + t.x, y: v.center.y + t.y)
        g.setTranslation(.zero, in: v.superview)
    }
}

// MARK: - Zoom Engine

class ZoomEngine: NSObject, ObservableObject {
    enum Method: String {
        case engineHook = "Engine"
        case objcHook = "ObjC"
        case jsHook = "JS Canvas"
        case displayZoom = "Display"
    }

    @Published var currentZoom: CGFloat = 1.0
    @Published var activeMethod: Method = .displayZoom
    @Published var statusText: String = "Searching..."
    @Published var debugInfo: String = ""

    private weak var gameWindow: UIWindow?
    private var gameView: UIView?
    private var originalFrame: CGRect = .zero

    var jsBridge: GameJSBridge?
    private var engineSetScale: ((Float) -> Void)?
    private var displayLink: CADisplayLink?

    deinit {
        displayLink?.invalidate()
    }

    func setup(window: UIWindow) {
        gameWindow = window
        gameView = findGameView(in: window)
        if gameView == nil {
            gameView = window.rootViewController?.view
        }
        if let gv = gameView {
            originalFrame = gv.frame
            debugInfo = String(describing: type(of: gv))
        }

        if tryCppHooks() {
            activeMethod = .engineHook
            statusText = "Engine hook active"
            return
        }
        if tryObjCHooks() {
            activeMethod = .objcHook
            statusText = "ObjC hook active"
            return
        }

        activeMethod = .displayZoom
        statusText = "Display zoom"

        let classes = scanEngineClasses()
        if !classes.isEmpty {
            debugInfo += " [" + classes.prefix(4).joined(separator: ",") + "]"
        }
    }

    func setZoom(_ factor: CGFloat) {
        currentZoom = factor
        if let scale = engineSetScale {
            scale(Float(factor))
        } else if let bridge = jsBridge, bridge.isConnected {
            bridge.setZoom(factor)
            if activeMethod != .jsHook {
                activeMethod = .jsHook
                statusText = "JS zoom active"
            }
        } else {
            applyDisplayZoom(factor)
        }
    }

    func reset() { setZoom(1.0) }

    // MARK: - C++ dlsym

    private func tryCppHooks() -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }

        let namespaces = ["7cocos2d", "2cc", "2ax", "5cocos", "6cocos2"]
        for ns in namespaces {
            let dirGetters = [
                "_ZN\(ns)8Director11getInstanceEv",
                "_ZN\(ns)8Director14sharedDirectorEv"
            ]
            var dSym: UnsafeMutableRawPointer?
            for n in dirGetters { dSym = dlsym(handle, n); if dSym != nil { break } }
            guard let dirSym = dSym else { continue }

            let sceneGetters = [
                "_ZNK\(ns)8Director15getRunningSceneEv",
                "_ZN\(ns)8Director15getRunningSceneEv",
                "_ZNK\(ns)8Director8getSceneEv"
            ]
            var sSym: UnsafeMutableRawPointer?
            for n in sceneGetters { sSym = dlsym(handle, n); if sSym != nil { break } }
            guard let sceneSym = sSym else { continue }

            let scaleSetters = [
                "_ZN\(ns)4Node8setScaleEf",
                "_ZN\(ns)5Scene8setScaleEf",
                "_ZN\(ns)4Node8setScaleEff"
            ]
            var scSym: UnsafeMutableRawPointer?
            for n in scaleSetters { scSym = dlsym(handle, n); if scSym != nil { break } }
            guard let scaleSym = scSym else { continue }

            typealias GetDir = @convention(c) () -> UnsafeMutableRawPointer
            typealias GetScene = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
            typealias SetScale = @convention(c) (UnsafeMutableRawPointer, Float) -> Void

            let getDir = unsafeBitCast(dirSym, to: GetDir.self)
            let getScene = unsafeBitCast(sceneSym, to: GetScene.self)
            let setScale = unsafeBitCast(scaleSym, to: SetScale.self)

            let dir = getDir()
            guard getScene(dir) != nil else { continue }

            engineSetScale = { scale in
                let d = getDir()
                if let scene = getScene(d) { setScale(scene, scale) }
            }
            debugInfo = "C++ \(ns)"
            return true
        }
        return false
    }

    // MARK: - ObjC runtime

    private func tryObjCHooks() -> Bool {
        let classNames = ["CCDirector", "Director", "CCDirectorCaller",
                          "cocos2d.Director", "AppController"]
        let singletons = ["sharedDirector", "getInstance", "shared"]

        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in singletons {
                let sel = NSSelectorFromString(selName)
                guard cls.responds(to: sel),
                      let result = (cls as AnyObject).perform(sel) else { continue }
                let director = result.takeUnretainedValue()

                let sceneSel = NSSelectorFromString("runningScene")
                guard director.responds(to: sceneSel),
                      let sceneResult = director.perform(sceneSel) else { continue }
                let scene = sceneResult.takeUnretainedValue()

                let scaleSel = NSSelectorFromString("setScale:")
                guard scene.responds(to: scaleSel),
                      let imp = class_getMethodImplementation(type(of: scene) as? AnyClass, scaleSel) else { continue }

                let dirRef = director
                let scSelCopy = sceneSel

                engineSetScale = { scale in
                    guard let sr = dirRef.perform(scSelCopy) else { return }
                    let sc = sr.takeUnretainedValue()
                    typealias Fn = @convention(c) (AnyObject, Selector, CGFloat) -> Void
                    let fn = unsafeBitCast(imp, to: Fn.self)
                    fn(sc, NSSelectorFromString("setScale:"), CGFloat(scale))
                }
                debugInfo = "ObjC \(className)"
                return true
            }
        }
        return false
    }

    // MARK: - Display zoom (fallback)

    private func applyDisplayZoom(_ factor: CGFloat) {
        guard let view = gameView else { return }

        displayLink?.invalidate()
        displayLink = nil

        if abs(factor - 1.0) < 0.01 {
            view.transform = .identity
            return
        }

        view.transform = CGAffineTransform(scaleX: factor, y: factor)

        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkFired() {
        guard let view = gameView else { return }
        if abs(currentZoom - 1.0) < 0.01 {
            view.transform = .identity
            displayLink?.invalidate()
            displayLink = nil
        } else {
            view.transform = CGAffineTransform(scaleX: currentZoom, y: currentZoom)
        }
    }

    // MARK: - Class scan (debug)

    private func scanEngineClasses() -> [String] {
        let candidates = [
            "CCDirector", "CCEAGLView", "CCMetalView", "CCGLView",
            "Director", "EAGLView", "MetalView", "GLView",
            "CCDirectorCaller", "AppController", "RootViewController"
        ]
        return candidates.filter { NSClassFromString($0) != nil }
    }

    // MARK: - Game view detection

    private func findGameView(in window: UIWindow) -> UIView? {
        guard let root = window.rootViewController?.view else { return nil }
        let hints = ["CCEAGL", "CCMetal", "CCRender", "MTKView", "GLKView",
                     "EAGLView", "MetalView", "OpenGL", "Cocos", "cocos"]
        if let found = findByClass(root, hints: hints) { return found }
        return findBiggestOpaque(root)
    }

    private func findByClass(_ view: UIView, hints: [String]) -> UIView? {
        let name = String(describing: type(of: view))
        if hints.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return view }
        for sub in view.subviews {
            if let found = findByClass(sub, hints: hints) { return found }
        }
        return nil
    }

    private func findBiggestOpaque(_ root: UIView) -> UIView? {
        let screenArea = UIScreen.main.bounds.width * UIScreen.main.bounds.height
        var best: UIView?
        var bestArea: CGFloat = 0
        func scan(_ v: UIView) {
            let a = v.bounds.width * v.bounds.height
            if a > screenArea * 0.5 && a > bestArea && v !== root && v.isOpaque {
                best = v; bestArea = a
            }
            v.subviews.forEach { scan($0) }
        }
        scan(root)
        return best
    }
}

// MARK: - Passthrough View

class XRDPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for sub in subviews where !sub.isHidden && sub.alpha > 0.01 && sub.isUserInteractionEnabled {
            let p = convert(point, to: sub)
            if sub.point(inside: p, with: event) { return true }
        }
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self { return nil }
        return result
    }
}

// MARK: - Toggle Button

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
        startCenter = center; moved = false
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

// MARK: - Macro Button (FEED indicator, not draggable)

class MacroButton: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.cornerRadius = frame.width / 2
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 0.6).cgColor)
        ctx.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let green = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.8)
        ctx.setStrokeColor(green.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .black),
            .foregroundColor: UIColor.white
        ]
        let text = "FEED"
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - Macro Drag Handle (moves the FEED button)

class MacroDragHandle: UIView {
    var onDrag: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.15)
        layer.cornerRadius = frame.width / 2
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor

        let icon = UILabel(frame: bounds)
        icon.text = "✥"
        icon.font = .systemFont(ofSize: 13)
        icon.textColor = UIColor.white.withAlphaComponent(0.6)
        icon.textAlignment = .center
        icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        let delta = CGPoint(x: loc.x - prev.x, y: loc.y - prev.y)
        onDrag?(delta)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 0.5 }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }
}
