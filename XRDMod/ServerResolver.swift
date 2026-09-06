import Foundation

class ServerResolver {

    private static let gameRegions = [
        "eu-west-3.mobile-live-v26.agario.miniclippt.com",
        "us-east-1.mobile-live-v26.agario.miniclippt.com",
        "us-west-2.mobile-live-v26.agario.miniclippt.com",
        "ap-southeast-1.mobile-live-v26.agario.miniclippt.com",
        "ap-northeast-1.mobile-live-v26.agario.miniclippt.com",
        "eu-west-1.mobile-live-v26.agario.miniclippt.com",
        "sa-east-1.mobile-live-v26.agario.miniclippt.com",
        "ap-south-1.mobile-live-v26.agario.miniclippt.com",
        "eu-central-1.mobile-live-v26.agario.miniclippt.com",
        "ap-southeast-2.mobile-live-v26.agario.miniclippt.com"
    ]

    struct ServerInfo {
        let url: String
        let token: String
        let ip: String
        let port: Int
        let hostname: String
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        return host.withCString { cs in
            inet_pton(AF_INET, cs, &sin.sin_addr) == 1 ||
            inet_pton(AF_INET6, cs, &sin6.sin6_addr) == 1
        }
    }

    private static func findRegionFromBSDLog() -> String? {
        let dnsLog = UserDefaults.standard.stringArray(forKey: "XRD_bsdDNS") ?? []
        for entry in dnsLog.reversed() {
            for region in gameRegions {
                if entry.contains(region) { return region }
            }
        }
        return nil
    }

    private static func setDNSOverride(hostname: String, ip: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("XRDSetDNSOverride"),
            object: nil, userInfo: ["host": hostname, "ip": ip]
        )
    }

    static func clearDNSOverrides() {
        NotificationCenter.default.post(
            name: NSNotification.Name("XRDClearDNSOverrides"),
            object: nil
        )
    }

    private static func resolveHostnameForIP(
        _ ip: String,
        port: Int,
        token: String,
        completion: @escaping (ServerInfo) -> Void
    ) {
        if let cached = NetworkInterceptor.shared.capturedServerHostname,
           !cached.isEmpty, !isIPAddress(cached) {
            setDNSOverride(hostname: cached, ip: ip)
            completion(ServerInfo(
                url: "wss://\(cached):\(port)",
                token: token, ip: ip, port: port, hostname: cached
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for region in gameRegions {
                var hints = addrinfo(
                    ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                    ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                    ai_addr: nil, ai_next: nil
                )
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(region, nil, &hints, &result) == 0,
                      let res = result else { continue }
                defer { freeaddrinfo(res) }

                var rp: UnsafeMutablePointer<addrinfo>? = res
                while let current = rp {
                    if current.pointee.ai_family == AF_INET,
                       let addr = current.pointee.ai_addr {
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                            var sinAddr = sin.pointee.sin_addr
                            inet_ntop(AF_INET, &sinAddr, &buf, socklen_t(INET_ADDRSTRLEN))
                        }
                        if String(cString: buf) == ip {
                            DispatchQueue.main.async {
                                completion(ServerInfo(
                                    url: "wss://\(region):\(port)",
                                    token: token, ip: ip, port: port, hostname: region
                                ))
                            }
                            return
                        }
                    }
                    rp = current.pointee.ai_next
                }
            }

            // Reverse DNS didn't match — use DNS override to force hostname → IP
            let hostname = findRegionFromBSDLog() ?? gameRegions[0]
            setDNSOverride(hostname: hostname, ip: ip)

            DispatchQueue.main.async {
                completion(ServerInfo(
                    url: "wss://\(hostname):\(port)",
                    token: token, ip: ip, port: port, hostname: hostname
                ))
            }
        }
    }

    static func resolveServer(
        partyCode: String = "",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        let interceptor = NetworkInterceptor.shared

        if let wsURL = interceptor.bestServerURL,
           let parsed = URLComponents(string: wsURL),
           let host = parsed.host {
            let token = interceptor.capturedToken ?? partyCode
            let port = parsed.port ?? 443
            let ip = interceptor.capturedServerIP ?? host

            if isIPAddress(host) {
                resolveHostnameForIP(ip, port: port, token: token) { info in
                    completion(.success(info))
                }
                return
            }

            completion(.success(ServerInfo(url: wsURL, token: token, ip: ip, port: port, hostname: host)))
            return
        }

        if let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer"),
           !bsdServer.isEmpty,
           let parsed = URLComponents(string: bsdServer), let host = parsed.host {
            let port = parsed.port ?? 443

            if isIPAddress(host) {
                resolveHostnameForIP(host, port: port, token: partyCode) { info in
                    completion(.success(info))
                }
                return
            }

            completion(.success(ServerInfo(url: bsdServer, token: partyCode, ip: host, port: port, hostname: host)))
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
            if let parsed = URLComponents(string: wsURL), let host = parsed.host {
                let p = parsed.port ?? 443
                if isIPAddress(host) {
                    resolveHostnameForIP(host, port: p, token: token) { info in
                        completion(.success(info))
                    }
                } else {
                    completion(.success(ServerInfo(url: wsURL, token: token, ip: host, port: p, hostname: host)))
                }
            } else {
                completion(.failure(ServerError.invalidResponse))
            }
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
