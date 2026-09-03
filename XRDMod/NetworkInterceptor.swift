import Foundation
import ObjectiveC

class NetworkInterceptor: NSObject {
    static let shared = NetworkInterceptor()

    private(set) var capturedServerURL: String?
    private(set) var capturedToken: String?
    var botSessions = NSHashTable<URLSession>.weakObjects()
    private var installed = false

    private let defaults = UserDefaults.standard
    private let apiKey = "XRD_discoveredAPI"
    private let headersKey = "XRD_discoveredHeaders"
    private let bodyFormatKey = "XRD_discoveredBodyFormat"

    var discoveredAPIEndpoint: String? {
        get { defaults.string(forKey: apiKey) }
        set { defaults.set(newValue, forKey: apiKey) }
    }

    var discoveredHeaders: [String: String]? {
        get { defaults.dictionary(forKey: headersKey) as? [String: String] }
        set { defaults.set(newValue, forKey: headersKey) }
    }

    var hasDiscoveredAPI: Bool { discoveredAPIEndpoint != nil }

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

    func handleAPIRequest(_ request: URLRequest, responseData data: Data) {
        guard let url = request.url?.absoluteString else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var serverURL: String?
        if let endpoints = json["endpoints"] as? [[String: Any]],
           let first = endpoints.first,
           let u = first["url"] as? String {
            serverURL = u
        } else if let u = json["url"] as? String {
            serverURL = u
        } else if let u = json["server"] as? String {
            serverURL = u
        }

        guard let server = serverURL else { return }

        DispatchQueue.main.async {
            self.discoveredAPIEndpoint = url
            self.discoveredHeaders = request.allHTTPHeaderFields

            let wsURL = server.hasPrefix("wss://") ? server : "wss://\(server)"
            self.capturedServerURL = wsURL
            self.capturedToken = (json["token"] as? String) ?? ""
            NotificationCenter.default.post(name: .xrdServerCaptured, object: nil)
        }
    }

    func handleWebSocketURL(_ url: URL) {
        let str = url.absoluteString
        guard str.contains("agar.io") else { return }
        DispatchQueue.main.async {
            self.capturedServerURL = str
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
        let urlStr = request.url?.absoluteString ?? ""
        let isAgar = urlStr.contains("agar.io") &&
            (urlStr.contains("server") || urlStr.contains("findServer") || urlStr.contains("find"))

        guard isAgar else {
            return self.xrd_dataTask(with: request, completionHandler: completionHandler)
        }

        let capturedReq = request
        let wrapped: (Data?, URLResponse?, Error?) -> Void = { data, resp, err in
            if let data = data {
                NetworkInterceptor.shared.handleAPIRequest(capturedReq, responseData: data)
            }
            completionHandler(data, resp, err)
        }
        return self.xrd_dataTask(with: request, completionHandler: wrapped)
    }

    @objc(xrd_webSocketTaskWithURL:)
    func xrd_wsTask(with url: URL) -> URLSessionWebSocketTask {
        if !NetworkInterceptor.shared.botSessions.contains(self) {
            NetworkInterceptor.shared.handleWebSocketURL(url)
        }
        return self.xrd_wsTask(with: url)
    }

    @objc(xrd_webSocketTaskWithRequest:)
    func xrd_wsTaskReq(with request: URLRequest) -> URLSessionWebSocketTask {
        if !NetworkInterceptor.shared.botSessions.contains(self),
           let url = request.url {
            NetworkInterceptor.shared.handleWebSocketURL(url)
        }
        return self.xrd_wsTaskReq(with: request)
    }
}
