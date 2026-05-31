import SwiftUI
import LlamaKit

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isGenerating = false
    var isModelLoaded = false
    var streamingText = ""

    var statusText: String {
        if isGenerating { return "生成中..." }
        if isModelLoaded { return "TinyLlama 1.1B · Metal" }
        return "模型未加载"
    }

    private let service = LlamaService.shared

    func loadModel() {
        service.loadModel()
        isModelLoaded = service.isLoaded
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isModelLoaded, !isGenerating else { return }

        inputText = ""
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)

        let prompt = buildPrompt(messages: messages)

        isGenerating = true
        streamingText = ""

        let assistantMsg = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMsg)

        Task {
            do {
                for try await token in service.generate(prompt: prompt) {
                    streamingText += token
                    if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                        messages[idx].content = streamingText
                    }
                }
            } catch {
                if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                    messages[idx].content = "[错误] \(error.localizedDescription)"
                }
            }
            isGenerating = false
            streamingText = ""
        }
    }

    func stopGeneration() {
        service.stopGeneration()
        isGenerating = false
        streamingText = ""
        loadModel()
    }

    private func buildPrompt(messages: [ChatMessage]) -> String {
        var prompt = "<|system|>\n你是语日记的AI助手，请用中文简洁回答用户的问题。</s>\n"
        for msg in messages where msg.role != .assistant || msg.content.isEmpty {
            if msg.role == .user {
                prompt += "<|user|>\n\(msg.content)</s>\n"
            }
        }
        prompt += "<|assistant|>\n"
        return prompt
    }
}
