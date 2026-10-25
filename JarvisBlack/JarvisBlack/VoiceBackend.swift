import Foundation

struct ChatLine: Codable {
    let role: String
    let content: String
}

struct VoiceReply {
    let text: String
    let audio: Data?
}

private struct ServerResponse: Decodable {
    let reply: String
    let audioBase64: String?
}

private struct SpeechResponse: Decodable {
    let audioBase64: String?
}

enum BackendError: LocalizedError {
    case notConfigured
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The AI server needs to be configured first."
        case .badResponse: "The AI server didn't respond correctly."
        }
    }
}

final class VoiceBackend {
    private let serverURL: URL?
    private let accessToken: String

    init() {
        let address = Bundle.main.object(forInfoDictionaryKey: "JARVIS_SERVER_URL") as? String ?? ""
        serverURL = address.contains("YOUR-SERVER") ? nil : URL(string: address)
        accessToken = Bundle.main.object(forInfoDictionaryKey: "JARVIS_CLIENT_TOKEN") as? String ?? ""
    }

    func ask(_ command: String, history: [ChatLine]) async throws -> VoiceReply {
        struct Payload: Encodable {
            let message: String
            let history: [ChatLine]
        }
        let data = try await post("chat", body: Payload(message: command, history: history))
        let decoded = try JSONDecoder().decode(ServerResponse.self, from: data)
        return VoiceReply(text: decoded.reply,
                          audio: decoded.audioBase64.flatMap { Data(base64Encoded: $0) })
    }

    func synthesize(_ text: String) async -> VoiceReply {
        struct Payload: Encodable { let text: String }
        do {
            let data = try await post("speak", body: Payload(text: text))
            let decoded = try JSONDecoder().decode(SpeechResponse.self, from: data)
            return VoiceReply(text: text,
                              audio: decoded.audioBase64.flatMap { Data(base64Encoded: $0) })
        } catch {
            return VoiceReply(text: text, audio: nil)
        }
    }

    private func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        guard let serverURL, serverURL.scheme == "https" else { throw BackendError.notConfigured }
        let endpoint = serverURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            throw BackendError.badResponse
        }
        return data
    }
}
