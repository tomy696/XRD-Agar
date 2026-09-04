import Foundation

class ServerResolver {

    struct ServerInfo {
        let url: String
        let token: String
    }

    private static let gameRegions = [
        "us-east-1", "us-east-2", "us-west-1",
        "ap-northeast-1", "ap-southeast-1",
        "eu-central-1", "eu-west-2", "eu-west-3",
        "sa-east-1", "me-south-1"
    ]

    private static let domainTemplate = "%@.mobile-live-v26.agario.miniclippt.com"

    static func resolveHostname(forIP ip: String, port: Int, completion: @escaping (String) -> Void) {
        let cleanIP = ip.hasPrefix("::ffff:") ? String(ip.dropFirst(7)) : ip
        let ipParts = cleanIP.split(separator: ".")
        let group = DispatchGroup()
        var matchedHostname: String?
        var subnetHostname: String?
        let lock = NSLock()

        for region in gameRegions {
            group.enter()
            let hostname = String(format: domainTemplate, region)
            let host = hostname as CFString
            let hostRef = CFHostCreateWithName(kCFAllocatorDefault, host).takeRetainedValue()
            var resolved = DarwinBoolean(false)
            CFHostStartInfoResolution(hostRef, .addresses, nil)
            if let addrs = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data] {
                for addrData in addrs {
                    var storage = sockaddr_storage()
                    addrData.withUnsafeBytes { ptr in
                        _ = memcpy(&storage, ptr.baseAddress!, min(addrData.count, MemoryLayout<sockaddr_storage>.size))
                    }
                    var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    if storage.ss_family == sa_family_t(AF_INET) {
                        var sin = withUnsafePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee } }
                        inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                    } else if storage.ss_family == sa_family_t(AF_INET6) {
                        var sin6 = withUnsafePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee } }
                        inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                    }
                    let resolvedStr = String(cString: buf)
                    let cleanResolved = resolvedStr.hasPrefix("::ffff:") ? String(resolvedStr.dropFirst(7)) : resolvedStr
                    if cleanResolved == cleanIP {
                        lock.lock()
                        matchedHostname = hostname
                        lock.unlock()
                    } else if ipParts.count >= 2 {
                        let resParts = cleanResolved.split(separator: ".")
                        if resParts.count >= 2 && resParts[0] == ipParts[0] && resParts[1] == ipParts[1] {
                            lock.lock()
                            if subnetHostname == nil { subnetHostname = hostname }
                            lock.unlock()
                        }
                    }
                }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let resolvedHostname: String
            if let hostname = matchedHostname {
                resolvedHostname = hostname
            } else if let hostname = subnetHostname {
                resolvedHostname = hostname
            } else {
                resolvedHostname = String(format: domainTemplate, gameRegions[0])
            }

            if let bsdClass = NSClassFromString("XRDBSDHook") {
                let sel = NSSelectorFromString("setDNSOverride:ip:")
                if bsdClass.responds(to: sel) {
                    _ = bsdClass.perform(sel, with: resolvedHostname, with: cleanIP)
                }
            }

            completion("wss://\(resolvedHostname):\(port)")
        }
    }

    static func resolveServer(
        partyCode: String = "",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        let interceptor = NetworkInterceptor.shared

        if let wsURL = interceptor.bestServerURL {
            let token = interceptor.capturedToken ?? partyCode

            if let ip = interceptor.capturedServerIP, let port = interceptor.capturedServerPort {
                resolveHostname(forIP: ip, port: port) { resolvedURL in
                    completion(.success(ServerInfo(url: resolvedURL, token: token)))
                }
                return
            }

            completion(.success(ServerInfo(url: wsURL, token: token)))
            return
        }

        if let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer"),
           !bsdServer.isEmpty {
            completion(.success(ServerInfo(url: bsdServer, token: partyCode)))
            return
        }

        guard let endpointStr = interceptor.discoveredAPIEndpoint,
              let endpoint = URL(string: endpointStr) else {
            completion(.failure(ServerError.noServer))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")

        if let headers = interceptor.discoveredHeaders {
            for (key, value) in headers {
                if key.lowercased() != "content-length" {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }

        var body: [String: Any] = ["mode": partyCode.isEmpty ? ":ffa" : ":party"]
        if !partyCode.isEmpty {
            body["token"] = partyCode
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession.shared
        NetworkInterceptor.shared.botSessions.add(session)

        session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ServerError.invalidResponse))
                return
            }

            var serverURL: String?
            if let endpoints = json["endpoints"] as? [[String: Any]],
               let first = endpoints.first,
               let url = first["url"] as? String {
                serverURL = url
            } else if let url = json["url"] as? String {
                serverURL = url
            } else if let url = json["server"] as? String {
                serverURL = url
            }

            guard let server = serverURL else {
                completion(.failure(ServerError.noServerFound))
                return
            }

            let token = (json["token"] as? String) ?? ""
            let wsURL = server.hasPrefix("wss://") ? server : "wss://\(server)"
            completion(.success(ServerInfo(url: wsURL, token: token)))
        }.resume()
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse
        case noServer

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No server in response"
            case .invalidResponse: return "Bad response"
            case .noServer: return "Play a game first so XRD can find your server"
            }
        }
    }
}
