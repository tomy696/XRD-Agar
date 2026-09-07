import Foundation

class ServerResolver {

    private static let webServers = [
        "web-arenas-live-v25-0.agario.miniclippt.com",
        "web-arenas-live-v25-1.agario.miniclippt.com",
        "web-arenas-live-v25-2.agario.miniclippt.com",
        "web-arenas-live-v25-3.agario.miniclippt.com",
        "web-arenas-live-v25-4.agario.miniclippt.com"
    ]

    private static let mobileToWebMap: [String: String] = [
        "mobile-live-v26": "web-arenas-live-v25-0"
    ]

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

    private static func mobileToWeb(_ hostname: String) -> String {
        if hostname.contains("mobile-live-v26") {
            return webServers[0]
        }
        return hostname
    }

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
            let rawHostname = isIPAddress(host) ? hostnameForIP(host) : host
            let hostname = mobileToWeb(rawHostname)
            let port = hostname.contains("web-arenas") ? 443 : (parsed.port ?? 443)

            completion(.success(ServerInfo(
                url: "wss://\(hostname):\(port)",
                token: token, ip: host, port: port, hostname: hostname
            )))
            return
        }

        if let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer"),
           !bsdServer.isEmpty,
           let parsed = URLComponents(string: bsdServer), let host = parsed.host {
            let rawHostname = isIPAddress(host) ? hostnameForIP(host) : host
            let hostname = mobileToWeb(rawHostname)
            let port = hostname.contains("web-arenas") ? 443 : (parsed.port ?? 443)

            completion(.success(ServerInfo(
                url: "wss://\(hostname):\(port)",
                token: partyCode, ip: host, port: port, hostname: hostname
            )))
            return
        }

        let fallback = webServers[0]
        completion(.success(ServerInfo(
            url: "wss://\(fallback)",
            token: partyCode, ip: fallback, port: 443, hostname: fallback
        )))
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
