import UIKit
import SwiftUI
import Combine

class XRDOverlay: NSObject {
    static let shared = XRDOverlay()

    let settings = GameSettings()
    let botEngine = BotEngine()
    let zoomEngine = ZoomEngine()

    private weak var gameWindow: UIWindow?
    private var container: XRDPassthroughView?
    private var toggleBtn: ToggleButton?
    private var macroBtn: MacroButton?
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
            self?.zoomEngine.setup(window: mainWindow)
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
        feedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            NetworkInterceptor.shared.sendFeed()
        }
    }

    private func stopFeedTimer() {
        feedTimer?.invalidate()
        feedTimer = nil
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
        let size = CGFloat(settings.macroButtonSize)
        let btn = MacroButton(frame: CGRect(x: 50, y: c.bounds.height - size - 50, width: size, height: size))
        btn.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
        c.addSubview(btn)
        macroBtn = btn
    }

    private func removeMacroButton() {
        stopFeedTimer()
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

class ZoomEngine: ObservableObject {
    enum Method: String {
        case engineHook = "Engine"
        case objcHook = "ObjC"
        case displayZoom = "Display"
    }

    @Published var currentZoom: CGFloat = 1.0
    @Published var activeMethod: Method = .displayZoom
    @Published var statusText: String = "Initializing..."
    @Published var debugInfo: String = ""

    private weak var gameWindow: UIWindow?
    private var gameView: UIView?
    private var originalFrame: CGRect = .zero
    private var originalScaleFactor: CGFloat = 0

    private var getInstanceFn: (() -> UnsafeMutableRawPointer)?
    private var getSceneFn: ((UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?)?
    private var setScaleFn: ((UnsafeMutableRawPointer, Float) -> Void)?

    private weak var objcDirector: AnyObject?
    private var objcSceneSel: Selector?
    private var objcSetScaleIMP: IMP?

    func setup(window: UIWindow) {
        gameWindow = window
        gameView = findGameView(in: window)
        if let gv = gameView {
            originalFrame = gv.frame
            originalScaleFactor = gv.contentScaleFactor
            debugInfo = String(describing: type(of: gv))
        } else {
            debugInfo = "no game view"
        }

        if tryCocos2dCpp() {
            activeMethod = .engineHook
            statusText = "Engine hook active"
            return
        }

        if tryObjCDirector() {
            activeMethod = .objcHook
            statusText = "ObjC hook active"
            return
        }

        activeMethod = .displayZoom
        statusText = gameView != nil ? "Display zoom ready" : "Zoom on root view"

        if gameView == nil {
            gameView = window.rootViewController?.view
            if let gv = gameView {
                originalFrame = gv.frame
                originalScaleFactor = gv.contentScaleFactor
                debugInfo = "rootVC: \(String(describing: type(of: gv)))"
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        currentZoom = factor
        switch activeMethod {
        case .engineHook:
            applyEngineZoom(factor)
        case .objcHook:
            applyObjCZoom(factor)
        case .displayZoom:
            applyDisplayZoom(factor)
        }
    }

    func reset() {
        setZoom(1.0)
    }

    // MARK: - Strategy 1: C++ dlsym

    private func tryCocos2dCpp() -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }

        let namespaces = ["7cocos2d", "2ax", "2cc"]
        for ns in namespaces {
            let giName = "_ZN\(ns)8Director11getInstanceEv"
            guard let giSym = dlsym(handle, giName) else { continue }

            typealias GIFn = @convention(c) () -> UnsafeMutableRawPointer
            let gi = unsafeBitCast(giSym, to: GIFn.self)

            let gsNames = [
                "_ZNK\(ns)8Director15getRunningSceneEv",
                "_ZN\(ns)8Director15getRunningSceneEv"
            ]
            var gsResolved: UnsafeMutableRawPointer?
            for n in gsNames {
                gsResolved = dlsym(handle, n)
                if gsResolved != nil { break }
            }
            guard let gsSym = gsResolved else { continue }

            let ssNames = [
                "_ZN\(ns)4Node8setScaleEf",
                "_ZN\(ns)4Node8setScaleEff"
            ]
            var ssResolved: UnsafeMutableRawPointer?
            for n in ssNames {
                ssResolved = dlsym(handle, n)
                if ssResolved != nil { break }
            }
            guard let ssSym = ssResolved else { continue }

            typealias GSFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
            let gs = unsafeBitCast(gsSym, to: GSFn.self)
            typealias SSFn = @convention(c) (UnsafeMutableRawPointer, Float) -> Void
            let ss = unsafeBitCast(ssSym, to: SSFn.self)

            let director = gi()
            guard gs(director) != nil else { continue }

            getInstanceFn = { gi() }
            getSceneFn = gs
            setScaleFn = ss
            debugInfo = "C++ ns=\(ns)"
            return true
        }
        return false
    }

    private func applyEngineZoom(_ factor: CGFloat) {
        guard let gi = getInstanceFn, let gs = getSceneFn, let ss = setScaleFn else { return }
        let director = gi()
        guard let scene = gs(director) else { return }
        ss(scene, Float(1.0 / factor))
    }

    // MARK: - Strategy 2: ObjC runtime

    private func tryObjCDirector() -> Bool {
        let classNames = ["CCDirector", "Director", "CCEAGLView"]
        let selectorNames = ["sharedDirector", "getInstance", "shared"]

        for className in classNames {
            guard let cls = NSClassFromString(className) else { continue }
            for selName in selectorNames {
                let sel = NSSelectorFromString(selName)
                guard cls.responds(to: sel) else { continue }
                guard let result = (cls as AnyObject).perform(sel) else { continue }
                let director = result.takeUnretainedValue()

                let sceneSel = NSSelectorFromString("runningScene")
                guard director.responds(to: sceneSel) else { continue }
                guard let sceneResult = director.perform(sceneSel) else { continue }
                let scene = sceneResult.takeUnretainedValue()

                let scaleSel = NSSelectorFromString("setScale:")
                guard scene.responds(to: scaleSel) else { continue }

                guard let imp = class_getMethodImplementation(type(of: scene) as? AnyClass, scaleSel) else { continue }

                objcDirector = director
                objcSceneSel = sceneSel
                objcSetScaleIMP = imp
                debugInfo = "ObjC \(className).\(selName)"
                return true
            }
        }
        return false
    }

    private func applyObjCZoom(_ factor: CGFloat) {
        guard let director = objcDirector,
              let sceneSel = objcSceneSel,
              let imp = objcSetScaleIMP else { return }

        guard let sceneResult = director.perform(sceneSel) else { return }
        let scene = sceneResult.takeUnretainedValue()

        typealias SetScaleFn = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let fn = unsafeBitCast(imp, to: SetScaleFn.self)
        fn(scene, NSSelectorFromString("setScale:"), 1.0 / factor)
    }

    // MARK: - Strategy 3: Display zoom

    private func applyDisplayZoom(_ factor: CGFloat) {
        guard let view = gameView else { return }
        if abs(factor - 1.0) < 0.01 {
            view.transform = .identity
            return
        }
        view.transform = CGAffineTransform(scaleX: factor, y: factor)
    }

    // MARK: - Game view detection

    private func findGameView(in window: UIWindow) -> UIView? {
        guard let root = window.rootViewController?.view else { return nil }
        let gameClassHints = [
            "CCEAGL", "CCMetal", "CCRender",
            "MTKView", "GLKView",
            "EAGLView", "MetalView", "OpenGL",
            "Cocos", "cocos"
        ]
        if let found = findViewByClass(root, hints: gameClassHints) {
            return found
        }
        if let biggest = findBiggestOpaqueChild(root) {
            return biggest
        }
        return nil
    }

    private func findViewByClass(_ view: UIView, hints: [String]) -> UIView? {
        let name = String(describing: type(of: view))
        for hint in hints {
            if name.localizedCaseInsensitiveContains(hint) { return view }
        }
        for sub in view.subviews {
            if let found = findViewByClass(sub, hints: hints) { return found }
        }
        return nil
    }

    private func findBiggestOpaqueChild(_ root: UIView) -> UIView? {
        let screenArea = UIScreen.main.bounds.width * UIScreen.main.bounds.height
        var best: UIView?
        var bestArea: CGFloat = 0
        func scan(_ view: UIView) {
            let area = view.bounds.width * view.bounds.height
            if area > screenArea * 0.5 && area > bestArea && view !== root && view.isOpaque {
                best = view
                bestArea = area
            }
            for sub in view.subviews { scan(sub) }
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

// MARK: - Macro Button (draggable indicator)

class MacroButton: UIView {
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

        ctx.setFillColor(UIColor(white: 0.18, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let green = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.7)
        ctx.setStrokeColor(green.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1, dy: 1))

        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .black),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9)
        ]
        let text = "M"
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
            withAttributes: attrs
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 0.7 }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let loc = t.location(in: superview)
        let prev = t.previousLocation(in: superview)
        center = CGPoint(x: center.x + loc.x - prev.x, y: center.y + loc.y - prev.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        UIView.animate(withDuration: 0.1) { self.alpha = 1 }
    }
}
