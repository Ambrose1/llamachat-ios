import Foundation

@MainActor
public final class LlamaService: ObservableObject {
    public static let shared = LlamaService()

    @Published public private(set) var isLoaded = false
    @Published public private(set) var isLoading = false
    @Published public private(set) var modelPath: String?

    private var model: LlamaModel?

    private let cliPath: String
    private let defaultModelPath: String

    private init() {
        let base = "/Users/ambrose/WorkBuddy/2026-05-31-task-4/llama.cpp"
        cliPath = "\(base)/build/bin/llama-cli"
        defaultModelPath = "\(base)/models/downloads/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    }

    public func loadModel(path: String? = nil) {
        let mp = path ?? defaultModelPath
        guard FileManager.default.fileExists(atPath: mp) else {
            print("[LlamaService] Model not found: \(mp)")
            return
        }
        guard FileManager.default.fileExists(atPath: cliPath) else {
            print("[LlamaService] llama-cli not found: \(cliPath)")
            return
        }

        isLoading = true
        model?.stop()
        model = LlamaModel(cliPath: cliPath, modelPath: mp)
        modelPath = mp
        isLoaded = true
        isLoading = false
    }

    public func unloadModel() {
        model?.stop()
        model = nil
        isLoaded = false
        modelPath = nil
    }

    public func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let model = model, isLoaded else {
            return AsyncThrowingStream { continuation in
                continuation.yield("[错误] 模型未加载。")
                continuation.finish()
            }
        }
        return model.generate(prompt: prompt)
    }

    public func stopGeneration() {
        model?.stop()
        isLoaded = false
    }
}
