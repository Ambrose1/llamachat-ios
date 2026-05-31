import Foundation
import llama

/// Wraps llama.cpp C API for on-device inference.
///
/// Inference runs on a background DispatchQueue; token generation is streamed via ``generate(prompt:)``.
///
/// - Important: Call ``load(path:)`` and ``generate(prompt:)`` from the main actor.
///   Cleanup / ``stopGeneration()`` / ``unload()`` are safe from any context.
final class LlamaEngine: @unchecked Sendable {
    // C pointers — non-Sendable, only accessed from main thread (load) or inference queue (generate)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    // llama_sampler is fully defined in llama.h → concrete Swift struct
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    private let queue = DispatchQueue(label: "com.llamachat.inference", qos: .userInitiated)
    private var shouldStop = false

    /// 为遵从 LLMEngine 协议，外部可在调用 `load() async throws` 之前设置模型路径
    var pendingModelPath: String? = nil

    var isLoaded: Bool { model != nil && context != nil }

    deinit { unload() }

    // MARK: - Load / Unload

    /// Load model from GGUF file path. Must be called on the main actor.
    @MainActor
    func load(path: String) throws {
        unload()

        llama_backend_init()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 99
        mparams.use_mmap = true

        guard let m = llama_model_load_from_file(path, mparams) else {
            llama_backend_free()
            throw LlamaError.modelLoadFailed
        }
        model = m

        var cparams = llama_context_default_params()
        cparams.n_ctx = 2048
        cparams.n_batch = 512
        cparams.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
        cparams.n_threads_batch = Int32(ProcessInfo.processInfo.activeProcessorCount)

        guard let ctx = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            llama_backend_free()
            model = nil
            throw LlamaError.contextFailed
        }
        context = ctx
        vocab = llama_model_get_vocab(m)

        // Setup sampler chain
        // 顺序: top_p → temp → dist（dist 必须在最后，负责实际采样）
        // llama.cpp 新版 API 要求 chain 末尾必须有 distribution sampler
        var sparams = llama_sampler_chain_default_params()
        sparams.no_perf = false
        guard let chain = llama_sampler_chain_init(sparams) else {
            llama_free(ctx)
            llama_model_free(m)
            llama_backend_free()
            context = nil
            model = nil
            throw LlamaError.contextFailed
        }
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        let seed = UInt32.random(in: 0...UInt32.max)
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
        sampler = chain
    }

    /// Release all C resources. Safe from any context.
    func unload() {
        shouldStop = true
        if let s = sampler { llama_sampler_free(s); sampler = nil }
        if let c = context { llama_free(c); context = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
        shouldStop = false
    }

    // MARK: - Generation

    struct GenerateParams {
        var maxTokens: Int32 = 256
    }

    /// Start token generation, streaming tokens through an `AsyncThrowingStream`.
    /// Must be called on the main actor (reads model/context/vocab/sampler state).
    @MainActor
    func generate(prompt: String, params: GenerateParams = GenerateParams()) -> AsyncThrowingStream<String, Error> {
        guard let ctx = context, let voc = vocab, let smpl = sampler else {
            return AsyncThrowingStream { $0.finish(throwing: LlamaError.notLoaded) }
        }

        shouldStop = false

        // Tokenize prompt on the main thread
        let promptBytes = Int32(prompt.utf8.count)
        print("[LlamaEngine] tokenize 开始, prompt_len=\(promptBytes) bytes, prompt_preview=\(String(prompt.prefix(80)))")
        // llama.cpp 标准模式：第一次调用传 NULL / 0 获取需要的 token 数（返回负值 = 所需大小）
        var nTokens = llama_tokenize(voc, prompt, promptBytes, nil, 0, true, true)
        print("[LlamaEngine] tokenize 第一次返回 nTokens=\(nTokens)")
        if nTokens < 0 {
            // 负值表示需要的缓冲区大小，取绝对值后分配
            nTokens = -nTokens
            print("[LlamaEngine] tokenize 需要缓冲区大小=\(nTokens), 分配中...")
        }
        guard nTokens > 0 else {
            print("[LlamaEngine] ❌ tokenize 失败: nTokens=\(nTokens)")
            return AsyncThrowingStream { $0.finish(throwing: LlamaError.decodeFailed) }
        }
        var inputTokens = [llama_token](repeating: 0, count: Int(nTokens))
        let actualTokens = llama_tokenize(voc, prompt, promptBytes, &inputTokens, nTokens, true, true)
        print("[LlamaEngine] tokenize 完成, actualTokens=\(actualTokens), first=\(inputTokens.prefix(5)), last=\(inputTokens.suffix(5))")

        let eos = llama_vocab_eos(voc)
        print("[LlamaEngine] eos_token_id=\(eos)")

        // Use nonisolated(unsafe) to capture non-Sendable C pointers into the @Sendable closure.
        // This is safe because the pointers remain valid for the lifetime of the engine,
        // and the inference queue serialises access.
        nonisolated(unsafe) let ctxRef = ctx
        nonisolated(unsafe) let vocRef = voc
        nonisolated(unsafe) let smplRef = smpl

        return AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish(throwing: LlamaError.notLoaded)
                return
            }

            // Initial decode on background queue
            self.queue.async { [weak self] in
                guard let self else { return }

                let batchSize = Int32(inputTokens.count)
                print("[LlamaEngine] 首次 decode 开始, batch_size=\(batchSize)")
                var batch = llama_batch_get_one(&inputTokens, batchSize)
                let decodeResult = llama_decode(ctxRef, batch)
                print("[LlamaEngine] 首次 decode 结果: \(decodeResult)")
                if decodeResult != 0 {
                    print("[LlamaEngine] ❌ 首次 decode 失败, code=\(decodeResult)")
                    continuation.finish(throwing: LlamaError.decodeFailed)
                    return
                }

                var nextToken: llama_token = 0
                var stepCount: Int32 = 0

                for step in 0..<params.maxTokens {
                    stepCount = step + 1
                    if self.shouldStop {
                        print("[LlamaEngine] ⏹ 用户停止, step=\(stepCount)")
                        continuation.finish()
                        return
                    }

                    nextToken = llama_sampler_sample(smplRef, ctxRef, -1)

                    if nextToken == eos || llama_vocab_is_eog(vocRef, nextToken) {
                        print("[LlamaEngine] EOS/EOS token, step=\(stepCount), token=\(nextToken)")
                        break
                    }

                    var buf = [CChar](repeating: 0, count: 256)
                    let len = llama_token_to_piece(vocRef, nextToken, &buf, 256, 0, true)
                    if len > 0 {
                        // buf 是 UTF-8 字节（不一定 null 结尾），用 Data 截取正确长度后转 String
                        let pieceData = Data(bytes: buf, count: Int(len))
                        if let text = String(data: pieceData, encoding: .utf8) {
                            continuation.yield(text)
                        }
                    }

                    // Decode next single token
                    var t = nextToken
                    batch = llama_batch_get_one(&t, 1)
                    let stepDecodeResult = llama_decode(ctxRef, batch)
                    if stepDecodeResult != 0 {
                        print("[LlamaEngine] ❌ step \(stepCount) decode 失败, code=\(stepDecodeResult), token=\(nextToken)")
                        continuation.finish(throwing: LlamaError.decodeFailed)
                        return
                    }
                }

                print("[LlamaEngine] ✅ 推理完成, total_steps=\(stepCount)")

                continuation.finish()
            }
        }
    }

    /// Request generation to stop. Safe from any context.
    func stopGeneration() {
        shouldStop = true
    }
}

// MARK: - Errors

enum LlamaError: LocalizedError {
    case notLoaded
    case modelLoadFailed
    case contextFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notLoaded: return "模型未加载"
        case .modelLoadFailed: return "模型加载失败"
        case .contextFailed: return "上下文创建失败"
        case .decodeFailed: return "推理失败"
        }
    }
}
