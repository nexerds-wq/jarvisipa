import Foundation

/// Optional LAN/remote Ollama path. Credentials are entered in the app and
/// intentionally not committed to source control or saved in UserDefaults.
enum JarvisOllama {
    enum Failure: LocalizedError {
        case invalidURL, badResponse(Int), emptyAnswer
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter a full Ollama HTTP or HTTPS address."
            case .badResponse(let code): return "Ollama returned HTTP \(code). Check server, model and API key."
            case .emptyAnswer: return "Ollama returned no answer."
            }
        }
    }

    static func answer(_ question: String,
                       baseURL: String,
                       model: String,
                       apiKey: String,
                       googleKey: String) async throws -> String {
        var questionWithSources = question
        if !googleKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let sources = try? await googleContext(query: question, key: googleKey) {
                questionWithSources += "\n\nSearch results (independent results, verify sources):\n" + sources
            }
        }
        let root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + "/api/chat"),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 55
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "messages": [
                ["role":"system","content":"You are JARVIS, a voice and heads-up-display assistant. Reply in 1-3 short, accurate sentences. If sources are given, distinguish reported results from known facts. Never invent live sensor values."],
                ["role":"user","content":questionWithSources]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Failure.emptyAnswer }
        guard (200..<300).contains(http.statusCode) else { throw Failure.badResponse(http.statusCode) }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any]
        let msg = obj?["message"] as? [String:Any]
        let answer = (msg?["content"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !answer.isEmpty else { throw Failure.emptyAnswer }
        return answer
    }

    private static func googleContext(query: String, key: String) async throws -> String {
        guard let url = URL(string: "https://google.serper.dev/search") else { return "" }
        var req = URLRequest(url:url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue(key, forHTTPHeaderField:"X-API-KEY")
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject:["q":query,"num":4])
        let (data, response) = try await URLSession.shared.data(for:req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return "" }
        let obj = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let results = (obj?["organic"] as? [[String:Any]] ?? []).prefix(4)
        return results.map { item in
            let title = item["title"] as? String ?? ""
            let link = item["link"] as? String ?? ""
            let snippet = item["snippet"] as? String ?? ""
            return title + " (" + link + "): " + snippet
        }.joined(separator:"\n").prefix(2500).description
    }
}
