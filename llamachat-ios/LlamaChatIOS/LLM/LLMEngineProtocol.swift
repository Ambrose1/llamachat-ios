import Foundation
import Combine

// MARK: - 引擎类型

enum EngineType: String, CaseIterable, Identifiable {
    case llamaCpp = "llama.cpp"
    case appleFoundation = "Apple AI"
    var id: String { rawValue }
}

// MARK: - 统一协议

/// 两个引擎都实现这个协议，ViewModel 通过 `any LLMEngine` 调用，无需关心后端。
protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }
    var isAvailable: Bool { get async }
    /// 加载模型／会话。llama.cpp 需在调用前通过 `modelPath` 设置路径。
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
    if #available(iOS 18.1, *), preferApple {
        return (AppleFoundationEngine(), .appleFoundation)
    }
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
final class AppleFoundationEngine: LLMEngine {

    private var _session: LanguageModelSession?
    private var shouldStop = false

    var isLoaded: Bool { _session != nil }

    var isAvailable: Bool {
        get async { await SystemLanguageModel.default.availability == .available }
    }

    func load() async throws {
        shouldStop = false
        _session = LanguageModelSession()
    }

    func unload() {
        _session = nil
        shouldStop = false
    }

    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let session = self._session else {
                continuation.finish(throwing: LLMEngineError.unavailable)
                return
            }
            Task {
                do {
                    let response = try await session.respond(to: prompt)
                    continuation.yield(response.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func stopGeneration() {
        shouldStop = true
    }
}

#else
// ===== 占位实现：FoundationModels 不可用时直接返回 unavailable =====

@available(iOS 18.1, *)
final class AppleFoundationEngine: LLMEngine {

    var isLoaded: Bool { false }

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

    /// 为遵从协议，新增 `load() async throws`，内部调用已有 `load(path:)`.
    /// ViewModel 需要在调用前设置 `pendingModelPath`（指向当前选中模型）。
    @MainActor
    func load() async throws {
        guard let path = pendingModelPath else {
            throw LLMEngineError.modelNotFound
        }
        try load(path: path)
    }

    /// 协议要求的单参数版本，委托给已有的双参数 generate
    /// 注：@MainActor 警告在 Swift 5 模式无害，升级 Swift 6 时需调整协议本身
    @MainActor
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
