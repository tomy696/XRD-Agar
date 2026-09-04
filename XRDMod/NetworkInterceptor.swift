import Foundation
import ObjectiveC

class NetworkInterceptor: NSObject {
    static let shared = NetworkInterceptor()

    private(set) var capturedServerURL: String?
    private(set) var capturedToken: String?
    var botSessions = NSHashTable<URLSession>.weakObjects()
    private var installed = false

    @objc dynamic var interceptedCount: Int = 0
    weak var gameWebSocket: URLSessionWebSocketTask?

    private let defaults = UserDefaults.standard
    private let serverKey = "XRD_capturedServer"
    private let headersKey = "XRD_capturedHeaders"
    private let apiKey = "XRD_discoveredAPI"

    var discoveredAPIEndpoint: String? {
        get { defaults.string(forKey: apiKey) }
        set { defaults.set(newValue, forKey: apiKey) }
    }

    var discoveredHeaders: [String: String]? {
        get { defaults.dictionary(forKey: headersKey) as? [String: String] }
        set { defaults.set(newValue, forKey: headersKey) }
    }

    var savedServerURL: String? {
        get { defaults.string(forKey: serverKey) }
        set { defaults.set(newValue, forKey: serverKey) }
    }

    private(set) var manualServerURL: String?

    var hasServer: Bool {
        capturedServerURL != nil || savedServerURL != nil || manualServerURL != nil
    }

    var bestServerURL: String? {
        capturedServerURL ?? manualServerURL ?? savedServerURL
    }

    var hasGameWS: Bool {
        gameWebSocket != nil && gameWebSocket?.state == .running
    }

    func setManualServer(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let wsURL = trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") ? trimmed : "wss://\(trimmed)"
        DispatchQueue.main.async {
            self.manualServerURL = wsURL
            self.savedServerURL = wsURL
            self.interceptedCount += 1
            NotificationCenter.default.post(name: .xrdServerCaptured, object: nil)
        }
    }

    func sendFeed() {
        guard let ws = gameWebSocket, ws.state == .running else { return }
        ws.send(.data(Data([21]))) { _ in }
    }

    func sendSplit() {
        guard let ws = gameWebSocket, ws.state == .running else { return }
        ws.send(.data(Data([17]))) { _ in }
    }

    func install() {
        guard !installed else { return }
        installed = true

        let dataTaskSel = NSSelectorFromString("dataTaskWithRequest:completionHandler:")
        let swizzledDataSel = NSSelectorFromString("xrd_dataTaskWithRequest:completionHandler:")
        if let orig = class_getInstanceMethod(URLSession.self, dataTaskSel),
           let swiz = class_getInstanceMethod(URLSession.self, swizzledDataSel) {
            method_exchangeImplementations(orig, swiz)
        }

        let wsByURLSel = NSSelectorFromString("webSocketTaskWithURL:")
        let swizzledWsSel = NSSelectorFromString("xrd_webSocketTaskWithURL:")
        if let orig = class_getInstanceMethod(URLSession.self, wsByURLSel),
           let swiz = class_getInstanceMethod(URLSession.self, swizzledWsSel) {
            method_exchangeImplementations(orig, swiz)
        }

        let wsByReqSel = NSSelectorFromString("webSocketTaskWithRequest:")
        let swizzledWsReqSel = NSSelectorFromString("xrd_webSocketTaskWithRequest:")
        if let orig = class_getInstanceMethod(URLSession.self, wsByReqSel),
           let swiz = class_getInstanceMethod(URLSession.self, swizzledWsReqSel) {
            method_exchangeImplementations(orig, swiz)
        }
    }

    func handleResponse(_ request: URLRequest, data: Data) {
        DispatchQueue.main.async { self.interceptedCount += 1 }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var serverURL: String?
        if let endpoints = json["endpoints"] as? [[String: Any]],
           let first = endpoints.first,
           let u = first["url"] as? String {
            serverURL = u
        } else if let u = json["url"] as? String, u.contains("agar") || u.contains("wss") || u.contains(":") {
            serverURL = u
        } else if let u = json["server"] as? String {
            serverURL = u
        }

        if let raw = serverURL {
            let wsURL = raw.hasPrefix("wss://") ? raw : "wss://\(raw)"
            let token = (json["token"] as? String) ?? ""
            DispatchQueue.main.async {
                self.capturedServerURL = wsURL
                self.capturedToken = token
                self.savedServerURL = wsURL
                self.discoveredAPIEndpoint = request.url?.absoluteString
                self.discoveredHeaders = request.allHTTPHeaderFields
                NotificationCenter.default.post(name: .xrdServerCaptured, object: nil)
            }
        }
    }

    func handleWebSocketURL(_ url: URL, task: URLSessionWebSocketTask?) {
        let str = url.absoluteString
        guard str.contains("agar") || str.contains("tech.") else { return }
        DispatchQueue.main.async {
            self.capturedServerURL = str
            self.savedServerURL = str
            if let task = task {
                self.gameWebSocket = task
            }
            NotificationCenter.default.post(name: .xrdServerCaptured, object: nil)
        }
    }
}

extension Notification.Name {
    static let xrdServerCaptured = Notification.Name("XRDServerCaptured")
}

extension URLSession {
    @objc(xrd_dataTaskWithRequest:completionHandler:)
    func xrd_dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        guard !NetworkInterceptor.shared.botSessions.contains(self) else {
            return self.xrd_dataTask(with: request, completionHandler: completionHandler)
        }

        let isPost = request.httpMethod?.uppercased() == "POST"
        let urlStr = request.url?.absoluteString ?? ""
        let mightBeAgar = isPost || urlStr.contains("agar") || urlStr.contains("miniclip")

        guard mightBeAgar else {
            return self.xrd_dataTask(with: request, completionHandler: completionHandler)
        }

        let capturedReq = request
        let wrapped: (Data?, URLResponse?, Error?) -> Void = { data, resp, err in
            if let data = data {
                NetworkInterceptor.shared.handleResponse(capturedReq, data: data)
            }
            completionHandler(data, resp, err)
        }
        return self.xrd_dataTask(with: request, completionHandler: wrapped)
    }

    @objc(xrd_webSocketTaskWithURL:)
    func xrd_wsTask(with url: URL) -> URLSessionWebSocketTask {
        let task = self.xrd_wsTask(with: url)
        if !NetworkInterceptor.shared.botSessions.contains(self) {
            NetworkInterceptor.shared.handleWebSocketURL(url, task: task)
        }
        return task
    }

    @objc(xrd_webSocketTaskWithRequest:)
    func xrd_wsTaskReq(with request: URLRequest) -> URLSessionWebSocketTask {
        let task = self.xrd_wsTaskReq(with: request)
        if !NetworkInterceptor.shared.botSessions.contains(self),
           let url = request.url {
            NetworkInterceptor.shared.handleWebSocketURL(url, task: task)
        }
        return task
    }
}
