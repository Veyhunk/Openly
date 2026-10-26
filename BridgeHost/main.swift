import Foundation

let root = (ProcessInfo.processInfo.environment["OPENLY_STATE_DIR"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Openly")).appendingPathComponent("bridge")
func reply(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    var length = UInt32(data.count).littleEndian
    FileHandle.standardOutput.write(Data(bytes: &length, count: 4)); FileHandle.standardOutput.write(data)
}
func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}
while let header = readExactly(4) {
    let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard length > 0, length < 1_048_576, let body = readExactly(Int(length)) else { break }
    guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
          let token = message["token"] as? String, UUID(uuidString: token) != nil else { reply(["error": "Invalid request"]); continue }
    let action = message["action"] as? String
    let requestURL = root.appendingPathComponent(token + ".json")
    let claimedURL = root.appendingPathComponent(token + ".claimed.json")
    let source = action == "complete" ? claimedURL : requestURL
    guard let data = try? Data(contentsOf: source),
          let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let expires = request["expires"] as? Double, expires > Date().timeIntervalSince1970 else { reply(["error": "Expired or consumed request"]); continue }
    do {
        if action == "claim" {
            try FileManager.default.moveItem(at: requestURL, to: claimedURL)
            reply(request)
        } else if action == "complete", let result = message["result"] as? [String: Any] {
            try JSONSerialization.data(withJSONObject: result).write(to: root.appendingPathComponent(token + ".result.json"), options: .atomic)
            try FileManager.default.removeItem(at: claimedURL)
            reply(["ok": true])
        } else { reply(["error": "Invalid action"]) }
    } catch { reply(["error": error.localizedDescription]) }
}
