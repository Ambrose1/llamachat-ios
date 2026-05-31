import Foundation

// MARK: - Chat Template

/// 不同模型的对话模板格式
enum ChatTemplate: String, CaseIterable {
    case qwen    // Qwen2.5/3/3.5: <|im_start|>system/user/assistant<|im_end|>
    case zephyr  // TinyLlama/Zephyr: <|system|>/<|user|>/<|assistant|>
    case llama3  // Llama 3: <|start_header_id|>...<|eot_id|>
    case gemma   // Gemma 4: <start_of_turn>user/model<end_of_turn>

    /// 根据模板格式构建完整 prompt
    func buildPrompt(system: String, userMessages: [String]) -> String {
        switch self {
        case .qwen:
            var prompt = "<|im_start|>system\n\(system)<|im_end|>\n"
            for msg in userMessages {
                prompt += "<|im_start|>user\n\(msg)<|im_end|>\n"
            }
            prompt += "<|im_start|>assistant\n"
            return prompt

        case .zephyr:
            var prompt = "<|system|>\n\(system)</s>\n"
            for msg in userMessages {
                prompt += "<|user|>\n\(msg)</s>\n"
            }
            prompt += "<|assistant|>\n"
            return prompt

        case .llama3:
            var prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>"
            for msg in userMessages {
                prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(msg)<|eot_id|>"
            }
            prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
            return prompt

        case .gemma:
            var prompt = "<bos><start_of_turn>system\n\(system)<end_of_turn>\n"
            for msg in userMessages {
                prompt += "<start_of_turn>user\n\(msg)<end_of_turn>\n"
            }
            prompt += "<start_of_turn>model\n"
            return prompt
        }
    }
}

// MARK: - Model Info

/// 描述一个可下载的 GGUF 模型
struct ModelInfo: Identifiable, Equatable {
    /// 唯一标识
    let id: String
    /// 显示名称
    let name: String
    /// 简短描述
    let description: String
    /// 预估下载大小（MB）
    let sizeMB: Int
    /// GGUF 文件名
    let filename: String
    /// HF Mirror 下载地址
    let downloadURL: URL
    /// 对话模板
    let chatTemplate: ChatTemplate
    /// 推荐最低运行内存（GB）
    let minRAMGB: Int
    /// 是否为中文优化模型
    let chineseOptimized: Bool

    var isDownloaded: Bool { localPath != nil }

    var localPath: String? {
        let file = documentsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: file.path) ? file.path : nil
    }

    var formattedSize: String {
        if sizeMB >= 1024 {
            String(format: "%.1f GB", Double(sizeMB) / 1024.0)
        } else {
            "\(sizeMB) MB"
        }
    }

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

// MARK: - Model Catalog

/// 所有可选模型的定义
enum ModelCatalog {
    /// 系统默认提示词
    static let systemPrompt = "你是语日记的AI助手，请用中文简洁回答。"

    static let allModels: [ModelInfo] = [
        ModelInfo(
            id: "qwen2.5-0.5b",
            name: "Qwen2.5 0.5B",
            description: "超轻量中文模型，下载快、响应快",
            sizeMB: 491,
            filename: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 2,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "qwen2.5-1.5b",
            name: "Qwen2.5 1.5B",
            description: "推荐！中文对话更流畅自然",
            sizeMB: 1147,
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 3,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "qwen3-0.6b",
            name: "Qwen3 0.6B",
            description: "最新千问3代，32K上下文、超轻量",
            sizeMB: 484,
            filename: "Qwen_Qwen3-0.6B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/bartowski/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 2,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B",
            description: "推荐！3.5代最强小模型，中文一流",
            sizeMB: 1280,
            filename: "Qwen3.5-2B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 4,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "qwen3.5-4b",
            name: "Qwen3.5 4B",
            description: "性能飞跃，接近云端体验",
            sizeMB: 2740,
            filename: "Qwen3.5-4B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 6,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "gemma4-e2b",
            name: "Gemma 4 E2B",
            description: "Google最新端侧，Apache 2.0可商用",
            sizeMB: 3460,
            filename: "google_gemma-4-E2B-it-Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!,
            chatTemplate: .gemma,
            minRAMGB: 6,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "minicpm5-1b",
            name: "MiniCPM5 1B",
            description: "面壁端侧SOTA，支持思考模式",
            sizeMB: 688,
            filename: "MiniCPM5-1B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/openbmb/MiniCPM5-1B-GGUF/resolve/main/MiniCPM5-1B-Q4_K_M.gguf")!,
            chatTemplate: .qwen,
            minRAMGB: 3,
            chineseOptimized: true
        ),
        ModelInfo(
            id: "tinyllama-1.1b",
            name: "TinyLlama 1.1B",
            description: "经典英文小模型，通用对话",
            sizeMB: 637,
            filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            downloadURL: URL(string: "https://hf-mirror.com/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!,
            chatTemplate: .zephyr,
            minRAMGB: 2,
            chineseOptimized: false
        ),
    ]

    /// 返回首个已下载的模型，若都未下载则返回 nil
    static var firstDownloaded: ModelInfo? {
        allModels.first { $0.isDownloaded }
    }
}
