import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

struct VoiceReply {
    let text: String
    let audio: Data?
}

/// Local inference. Model weights download once to the app's private cache.
@MainActor
final class VoiceBackend {
    private var model: ModelContainer?
    private var modelTask: Task<ModelContainer, Error>?
    private var session: ChatSession?
    var isReady: Bool { session != nil }

    private let instructions = """
        You are Jarvis, a capable voice-first personal assistant on an iPhone.
        Speak naturally and answer clearly in one or two sentences unless asked for detail.
        You work offline and cannot look up live facts or control an app unless the phone handles that action.
        Never claim to have searched the web or completed a device action you did not perform.
        """

    func ask(_ command: String) async throws -> VoiceReply {
        let chat = try await prepareSession()
        var answer = ""
        for try await part in chat.streamResponse(to: command) {
            answer += part
            if answer.count > 1200 { break }
        }
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LocalAIError.emptyResponse }
        return VoiceReply(text: clean, audio: nil)
    }

    func synthesize(_ text: String) -> VoiceReply {
        VoiceReply(text: text, audio: nil)
    }

    private func prepareSession() async throws -> ChatSession {
        if let session { return session }
        let loaded = try await loadModel()
        let session = ChatSession(
            loaded,
            instructions: instructions,
            generateParameters: GenerateParameters(temperature: 0.5)
        )
        self.session = session
        return session
    }

    private func loadModel() async throws -> ModelContainer {
        if let model { return model }
        if let modelTask { return try await modelTask.value }

        let task = Task<ModelContainer, Error> {
            Memory.cacheLimit = 20 * 1024 * 1024
            return try await #huggingFaceLoadModelContainer(
                configuration: LLMRegistry.qwen3_8b_4bit
            ) { _ in }
        }
        modelTask = task
        do {
            let loaded = try await task.value
            model = loaded
            modelTask = nil
            return loaded
        } catch {
            modelTask = nil
            throw error
        }
    }
}

enum LocalAIError: Error {
    case emptyResponse
}
