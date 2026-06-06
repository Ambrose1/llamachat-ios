import Foundation

// MARK: - 引擎类型

enum EngineType: String, CaseIterable, Identifiable {
    case llamaCpp = "llama.cpp"
    case appleFoundation = "Apple AI"
    var id: String { rawValue }
}

// MARK: - 统一协议

/// 两个引擎都实现这个协议，ViewModel 通过 `any LLMEngine` 调用，无需关心后端。
///
/// 标注 @MainActor：LlamaEngine 通过 @Observable 隐式在主 actor；
/// AppleFoundationEngine 也显式标注 @MainActor，保持一致性。
@MainActor
protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }
    var isAvailable: Bool { get async }
    /// 引擎是否需要 ViewModel 拼接 ChatTemplate 格式的完整 prompt。
    /// llama.cpp 需要（模型只接受裸 token），Apple AI 不需要（系统指令在 session 初始化时注入）。
    var needsFormattedPrompt: Bool { get }
    /// 加载模型／会话。llama.cpp 需在调用前通过 `pendingModelPath` 设置路径。
    func load() async throws
    func unload()
    func generate(prompt: String) -> AsyncThrowingStream<String, Error>
    func stopGeneration()
}

// MARK: - 引擎工厂

/// 根据设备能力自动选择最优引擎。
/// - Parameter preferApple: 是否优先使用 Apple Foundation Models（默认 true）
///
/// 注：AppleFoundationEngine 仅在 `canImport(FoundationModels)` 为 true 时真正可用
/// （需要 Xcode 17+ / iOS 26 SDK）。否则 isAvailable 始终为 false，load() 会抛出
/// unavailable 错误。ViewModel 应检查 engine.isAvailable 后再使用。
func makeEngine(preferApple: Bool = true) -> (any LLMEngine, EngineType) {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *), preferApple {
        return (AppleFoundationEngine(), .appleFoundation)
    }
#else
    if #available(iOS 18.1, *), preferApple {
        return (AppleFoundationEngine(), .appleFoundation)
    }
#endif
    return (LlamaEngine(), .llamaCpp)
}

// ============================================================================
// MARK: - Apple Foundation Models 实现（需要 iOS 26 / Xcode 17+）
// ============================================================================
//
// ⚠️ FoundationModels 框架仅存在于 iOS 26 SDK（Xcode 17 Beta+）。
//    当前 SDK（iOS 18.4 / Xcode 16.3）中 canImport(FoundationModels) == false，
//    因此 Apple AI 引擎 isAvailable 始终为 false，应用自动降级到 llama.cpp。
//    升级 Xcode 17 后，下方 #if 块自动激活真实实现。
//
// 真实 API 参考（Apple Developer Documentation）：
//   import FoundationModels
//   let session = LanguageModelSession()
//   let response = try await session.respond(to: prompt)

#if canImport(FoundationModels)
// ===== 真实实现（Xcode 17+ / iOS 26+）=====

import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class AppleFoundationEngine: LLMEngine {

    private var _session: LanguageModelSession?
    private var generationTask: Task<Void, Never>?

    var isLoaded: Bool { _session != nil }

    /// Apple AI 系统指令在 session 初始化时注入，不需要 ViewModel 拼接 ChatTemplate
    var needsFormattedPrompt: Bool { false }

    var isAvailable: Bool {
        get async {
            await SystemLanguageModel.default.availability == .available
        }
    }

    func load() async throws {
        guard await isAvailable else {
            throw LLMEngineError.unavailable
        }
        generationTask?.cancel()
        generationTask = nil
        _session = LanguageModelSession(
            model: .default,
            instructions: Instructions(ModelCatalog.systemPrompt)
        )
    }

    func unload() {
        generationTask?.cancel()
        generationTask = nil
        _session = nil
    }

    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let session = _session else {
            return AsyncThrowingStream<String, Error> { continuation in
                continuation.finish(throwing: LLMEngineError.unavailable)
            }
        }
        let responseStream = session.streamResponse(to: Prompt(prompt))
        return AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await snapshot in responseStream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.generationTask = task
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }
}

#else
// ===== 占位实现：FoundationModels 不可用时直接返回 unavailable =====

@available(iOS 18.1, *)
final class AppleFoundationEngine: LLMEngine {

    var isLoaded: Bool { false }
    var needsFormattedPrompt: Bool { false }

    var isAvailable: Bool {
        get async { false }
    }

    func load() async throws {
        throw LLMEngineError.unavailable
    }

    func unload() {}

    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMEngineError.unavailable)
        }
    }

    func stopGeneration() {}
}

#endif

// ============================================================================
// MARK: - llama.cpp 实现（扩展已有 LlamaEngine）
// ============================================================================

extension LlamaEngine: LLMEngine {

    /// llama.cpp 需要完整的 ChatTemplate prompt，不能只传裸文本
    var needsFormattedPrompt: Bool { true }

    /// 为遵从协议，新增 `load() async throws`，内部调用已有 `load(path:)`.
    /// ViewModel 需要在调用前设置 `pendingModelPath`（指向当前选中模型）。
    func load() async throws {
        guard let path = pendingModelPath else {
            throw LLMEngineError.modelNotFound
        }
        try load(path: path)
    }

    /// 协议要求的单参数版本，委托给已有的双参数 generate
    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        generate(prompt: prompt, params: GenerateParams())
    }

    var isAvailable: Bool {
        get async {
            if #available(iOS 17.0, *) { return true }
            return false
        }
    }
}

// ============================================================================
// MARK: - 错误类型
// ============================================================================

enum LLMEngineError: LocalizedError {
    case unavailable
    case unimplemented
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .unavailable:   return "当前设备不支持此模型"
        case .unimplemented: return "功能未实现"
        case .modelNotFound: return "模型文件未找到"
        }
    }
}
