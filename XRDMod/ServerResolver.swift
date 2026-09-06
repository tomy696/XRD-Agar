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

    private static func hostnameForIP(_ ip: String) -> String {
        if let cached = NetworkInterceptor.shared.capturedServerHostname,
           !cached.isEmpty, !isIPAddress(cached) {
            return cached
        }
        let dnsLog = UserDefaults.standard.stringArray(forKey: "XRD_bsdDNS") ?? []
        for entry in dnsLog.reversed() {
            for region in gameRegions {
                if entry.contains(region) { return region }
            }
        }
        return gameRegions[0]
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
            let hostname = isIPAddress(host) ? hostnameForIP(ip) : host

            completion(.success(ServerInfo(
                url: "wss://\(hostname):\(port)",
                token: token, ip: ip, port: port, hostname: hostname
            )))
            return
        }

        if let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer"),
           !bsdServer.isEmpty,
           let parsed = URLComponents(string: bsdServer), let host = parsed.host {
            let port = parsed.port ?? 443
            let hostname = isIPAddress(host) ? hostnameForIP(host) : host

            completion(.success(ServerInfo(
                url: "wss://\(hostname):\(port)",
                token: partyCode, ip: host, port: port, hostname: hostname
            )))
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
                let hostname = isIPAddress(host) ? hostnameForIP(host) : host
                completion(.success(ServerInfo(
                    url: wsURL, token: token, ip: host, port: p, hostname: hostname
                )))
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
