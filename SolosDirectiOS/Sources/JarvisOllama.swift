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
                ["role":"system","content":"You are JARVIS, a warm, perceptive voice assistant. Be naturally witty when the moment is light, gentle when someone needs emotional support, and clear and direct when urgent safety action is needed. Never claim to be human, read emotion from audio, or invent live sensor values. Use natural punctuation and 1-3 accurate sentences. If sources are given, distinguish results from known facts."],
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

    /// Unified Jarvis conversation persona with opt-in recent context.
    static func companionReply(_ observation:String, baseURL:String, model:String, apiKey:String, history:[[String:String]] = [], memory:String = "") async throws -> String {
        let root = baseURL.trimmingCharacters(in:.whitespacesAndNewlines)
            .trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        guard let url = URL(string:root + "/api/chat"),
              ["http","https"].contains(url.scheme?.lowercased() ?? "") else { throw Failure.invalidURL }
        var request = URLRequest(url:url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer " + apiKey,forHTTPHeaderField:"Authorization") }
        let instructions = """
        You are JARVIS, the single conversational AI assistant running through a phone and smart glasses.
        Be warm, perceptive, witty when it fits, and pragmatic when action is needed.
        Respond to the meaning and context of the user's words rather than defaulting to a generic script.
        When the user explicitly says they are anxious, sad, excited, proud or frustrated,
        acknowledge their words naturally and offer useful support or an appropriate question.
        Never claim to infer an emotion reliably from someone's tone, crying, laughter, silence, or microphone loudness.
        Do not pretend to be human or promise to be the user's only friend.
        Speak conversationally, with warmth, gentle humor when appropriate, and clear practical thinking.
        Adapt response length: one sentence for quick checks, 2-4 sentences for conversation,
        longer only when the user asks for detailed help.
        Remember the last exchanges and user-approved notes without pretending to know more.
        Ask relevant follow-up questions sparingly. Never repeat generic comfort scripts.
        Be a supportive companion, not a replacement for human friendships or professional help.
        Respect boundaries: if the user says quiet, stop talking; if they ask for honesty,
        give constructive, respectful disagreement rather than automatic agreement.
        Avoid overly familiar pet names, forced enthusiasm, or claiming to have feelings.
        When the user is joking, respond playfully; when serious, be calm and focused.
        Let your wording carry a natural voice performance: shorter, focused sentences in urgent moments;
        reassuring language and comfortable pauses for difficult conversations;
        brighter, playful phrasing when the user makes a joke or celebrates a win.
        Don't become a comedian during grief or emergencies. Don't exaggerate urgency for everyday requests.
        Ask before assuming someone wants advice when they mostly need to be heard.
        Write clean sentences with natural punctuation so the iPhone voice can change its pace between sentences.
        Do not assume that silence, laughter, loudness or speech patterns prove emotion.
        The user has opted into emotional support. A transcript does NOT prove an emotion:
        never claim to detect crying, laughter, anger, threats or private relationships from audio.
        When uncertain, ask a gentle question rather than guessing.
        Do not intrude on conversations, phone calls, music, videos or arguments.
        Avoid unsolicited comments on other people's private conversations.
        Do not encourage emotional dependence or imply you are human.
        Be empathetic without flattery or judgment. If a user describes immediate danger,
        encourage contacting emergency services or a trusted nearby person.
        """
        let memoryContext = memory.isEmpty ? "" : "\nUser-approved personal notes (not verified facts):\n" + String(memory.prefix(1800))
        let safeHistory = history.suffix(12).compactMap { entry -> [String:String]? in
            guard let role = entry["role"], ["user","assistant"].contains(role),
                  let content = entry["content"] else { return nil }
            return ["role":role,"content":String(content.prefix(900))]
        }
        let messages = [["role":"system","content":instructions + memoryContext]] +
            safeHistory + [["role":"user","content":observation]]
        request.httpBody = try JSONSerialization.data(withJSONObject:[
            "model":model,"stream":false,"messages":messages
        ])
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw Failure.emptyAnswer }
        guard (200..<300).contains(http.statusCode) else { throw Failure.badResponse(http.statusCode) }
        let object = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let message = object?["message"] as? [String:Any]
        let reply = (message?["content"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !reply.isEmpty else { throw Failure.emptyAnswer }
        return String(reply.prefix(500))
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
