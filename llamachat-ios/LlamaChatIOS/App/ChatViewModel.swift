import SwiftUI
import Observation

// FoundationModels 只在不低于 iOS 26 的 SDK 上可用
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isGenerating = false
    var streamingText = ""
    var lastLoadError: String?

    /// 当前选中的引擎类型（UI 可切换）
    var selectedEngine: EngineType = .llamaCpp {
        didSet { if oldValue != selectedEngine { Task { await switchEngine(to: selectedEngine) } } }
    }

    private(set) var engine: any LLMEngine
    let model: LlamaModel

    init() {
        let model = LlamaModel()
        self.model = model
        // 当前 SDK 不含 FoundationModels（需 Xcode 17+ / iOS 26），默认用 llama.cpp
        #if canImport(FoundationModels)
        let (initialEngine, initialType) = makeEngine()
        #else
        let (initialEngine, initialType) = makeEngine(preferApple: false)
        #endif
        self.engine = initialEngine
        self.selectedEngine = initialType
    }

    // MARK: - Public API

    var statusText: String {
        if isGenerating { return "生成中..." }
        if engine.isLoaded {
            if selectedEngine == .appleFoundation {
                return "Apple 端智能 · 就绪"
            }
            if let m = model.selectedModel {
                return "\(m.name) · 就绪"
            }
            return "\(selectedEngine.rawValue) · 就绪"
        }
        if selectedEngine == .appleFoundation {
            if let err = lastLoadError, !engine.isLoaded {
                return "Apple AI 失败: \(err)"
            }
            return "Apple AI 加载中..."
        }
        if selectedEngine == .llamaCpp {
            if model.isDownloading {
                if let name = model.selectedModel?.name {
                    return "下载 \(name) 中..."
                }
                return "下载模型中..."
            }
            if let err = model.lastDownloadError {
                return "下载失败: \(err)"
            }
            if let err = lastLoadError, !engine.isLoaded {
                return "加载失败: \(err)"
            }
            if model.isModelAvailable { return "模型就绪，点击加载" }
            return "选择模型并下载"
        } else {
            return "Apple AI 不可用"
        }
    }

    var canType: Bool {
        engine.isLoaded && !isGenerating
    }

    /// 切换引擎（不自动加载！由用户显式点击「加载」触发）
    func switchEngine(to type: EngineType) async {
        engine.unload()
        lastLoadError = nil
        let (newEngine, _) = makeEngine(preferApple: type == .appleFoundation)
        engine = newEngine
        // llama.cpp 不会自动加载，需用户手动点「加载」
        if type == .appleFoundation {
            do {
                try await engine.load()
            } catch {
                lastLoadError = error.localizedDescription
                print("引擎加载失败: \(error.localizedDescription)")
            }
        }
    }

    /// llama.cpp：加载当前选中模型的 GGUF 文件
    func loadModelIfNeeded() {
        guard selectedEngine == .llamaCpp else { return }

        guard let path = model.modelPath else {
            lastLoadError = "模型文件未找到"
            print("[ChatViewModel] 加载失败：modelPath 为 nil (selectedModelID=\(model.selectedModelID))")
            return
        }

        guard let llama = engine as? LlamaEngine else {
            lastLoadError = "引擎类型不匹配"
            return
        }

        llama.pendingModelPath = path
        lastLoadError = nil

        Task {
            do {
                try await engine.load()
                print("[ChatViewModel] 引擎加载成功：\(path)")
            } catch {
                lastLoadError = error.localizedDescription
                print("[ChatViewModel] 引擎加载失败: \(error.localizedDescription)")
            }
        }
    }

    /// 切换模型（需重新加载引擎）
    func switchModel(to modelID: String) {
        let wasLoaded = engine.isLoaded
        engine.unload()
        model.selectedModelID = modelID
        if wasLoaded, let path = model.modelPath {
            if let llama = engine as? LlamaEngine {
                llama.pendingModelPath = path
            }
            Task { try? await engine.load() }
        }
    }

    func downloadModel() {
        model.downloadModel()
    }

    func downloadModel(_ modelID: String) {
        model.downloadModel(modelID)
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, engine.isLoaded, !isGenerating else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        messages.append(ChatMessage(role: .assistant, content: ""))

        isGenerating = true
        streamingText = ""

        // Apple AI: 系统指令在 session init 时注入，仅传用户裸文本
        // llama.cpp: 需要全量 ChatTemplate prompt（含 system + 历史对话）
        let prompt: String
        if engine.needsFormattedPrompt {
            prompt = buildPrompt(messages: messages)
            print("[ChatViewModel] send() llama.cpp prompt (\(prompt.count) chars), 模板=\(model.chatTemplate.rawValue)")
        } else {
            prompt = text
            print("[ChatViewModel] send() Apple AI prompt: \"\(text.prefix(80))\"")
        }

        Task {
            do {
                for try await token in engine.generate(prompt: prompt) {
                    streamingText += token
                    if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                        messages[idx].content = streamingText
                    }
                }
            } catch {
                print("[ChatViewModel] ❌ send() caught error: \(error)")
                if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                    messages[idx].content = "[错误] \(error.localizedDescription)"
                }
            }
            isGenerating = false
            streamingText = ""
        }
    }

    func stopGeneration() {
        engine.stopGeneration()
        isGenerating = false
        streamingText = ""
    }

    // MARK: - Private

    private func buildPrompt(messages: [ChatMessage]) -> String {
        let userMessages = messages
            .filter { $0.role == .user }
            .map { $0.content }
        return model.chatTemplate.buildPrompt(
            system: ModelCatalog.systemPrompt,
            userMessages: userMessages
        )
    }
}
