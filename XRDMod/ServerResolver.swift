import Foundation

class ServerResolver {

    struct ServerInfo {
        let url: String
        let token: String
    }

    static func resolveServer(
        region: ServerRegion,
        gameMode: GameMode,
        partyCode: String = "",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        if gameMode == .party && !partyCode.isEmpty {
            resolvePartyServer(partyCode: partyCode, region: region, completion: completion)
            return
        }

        let endpoint = URL(string: "https://mc-api.agar.io/api/v1/server")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")

        let body: [String: Any] = [
            "region": region.apiValue,
            "mode": gameMode.serverMode
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let endpoints = json["endpoints"] as? [[String: Any]],
                  let first = endpoints.first,
                  let serverURL = first["url"] as? String else {
                completion(.failure(ServerError.noServerFound))
                return
            }
            let token = (json["token"] as? String) ?? ""
            let wsURL = serverURL.hasPrefix("wss://") ? serverURL : "wss://\(serverURL)"
            completion(.success(ServerInfo(url: wsURL, token: token)))
        }.resume()
    }

    private static func resolvePartyServer(
        partyCode: String,
        region: ServerRegion,
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        let endpoint = URL(string: "https://mc-api.agar.io/api/v1/server")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")

        let body: [String: Any] = [
            "region": region.apiValue,
            "mode": ":party",
            "token": partyCode
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let endpoints = json["endpoints"] as? [[String: Any]],
                  let first = endpoints.first,
                  let serverURL = first["url"] as? String else {
                completion(.failure(ServerError.noServerFound))
                return
            }
            let token = (json["token"] as? String) ?? ""
            let wsURL = serverURL.hasPrefix("wss://") ? serverURL : "wss://\(serverURL)"
            completion(.success(ServerInfo(url: wsURL, token: token)))
        }.resume()
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No server found for this region/mode"
            case .invalidResponse: return "Invalid server response"
            }
        }
    }
}
