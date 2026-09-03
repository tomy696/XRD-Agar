import Foundation
import WebKit

class GameJSBridge: NSObject, WKScriptMessageHandler {
    weak var settings: GameSettings?
    var onPlayersUpdated: (([PlayerInfo]) -> Void)?
    var onServerURLReceived: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let data = body["data"] as? String else { return }

        switch type {
        case "players":
            handlePlayersUpdate(data)
        case "serverURL":
            settings?.serverURL = data
            onServerURLReceived?(data)
        case "ownIDs":
            handleOwnIDs(data)
        default:
            break
        }
    }

    private func handlePlayersUpdate(_ json: String) {
        guard let data = json.data(using: .utf8),
              let players = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let parsed: [PlayerInfo] = players.compactMap { dict in
            guard let id = dict["id"] as? UInt32,
                  let name = dict["name"] as? String,
                  let x = dict["x"] as? Double,
                  let y = dict["y"] as? Double,
                  let mass = dict["mass"] as? Double else { return nil }
            return PlayerInfo(id: id, name: name, x: x, y: y, mass: mass, color: 0, isVirus: false)
        }

        DispatchQueue.main.async { [weak self] in
            self?.settings?.currentPlayers = parsed
            self?.onPlayersUpdated?(parsed)
        }
    }

    private func handleOwnIDs(_ json: String) {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONSerialization.jsonObject(with: data) as? [UInt32] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.settings?.ownCellIDs = ids
        }
    }
}
