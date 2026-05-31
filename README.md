# LlamaChat iOS

> 端侧中文大模型聊天应用 — 免联网、零延迟、完全隐私

LlamaChat 是一个纯本地运行的 iOS 大模型聊天应用，基于 [llama.cpp](https://github.com/ggml-org/llama.cpp) 推理引擎，支持 Qwen、Gemma、MiniCPM 等多个中文优化模型在 iPhone/iPad 上离线运行。

---

## 功能

- 🚀 **纯本地推理** — 模型在设备上运行，无需联网、不消耗 API
- 🇨🇳 **中文一流** — 搭载 Qwen3.5、Gemma 4 等中文优化模型
- 📦 **模型即下即用** — 从 HF Mirror 一键下载 GGUF 模型
- 🧠 **双引擎架构** — llama.cpp C API（当前主力）+ Apple Foundation Models（iOS 26+ 预备）
- ⚡ **Metal GPU 加速** — 自动卸载 99 层到 GPU，提速明显
- 🎛️ **灵活采样** — top_p=0.9 + temp=0.7 的采样链配置

---

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Layer                        │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ App.swift │──│ ContentView  │──│ ChatBubbleView    │  │
│  │  (@main)  │  │ (消息列表+   │  │ (单条消息气泡)     │  │
│  │           │  │  输入+工具栏) │  │                    │  │
│  └──────────┘  └──────┬───────┘  └───────────────────┘  │
│                       │ @Observed                         │
│              ┌────────▼────────┐                         │
│              │  ChatViewModel  │  @Observable             │
│              │ - messages      │  @MainActor              │
│              │ - isGenerating  │                          │
│              │ - send()        │                          │
│              │ - stop()        │                          │
│              └───┬────────┬────┘                         │
│                  │        │                               │
│         ┌────────▼──┐ ┌──▼────────────┐                  │
│         │LlamaModel │ │ LLMEngine      │                  │
│         │(模型管理)  │ │ (推理协议)      │                  │
│         │- 下载/删除 │ │ load/generate  │                  │
│         │- 选择/持久 │ │ stop/unload    │                  │
│         └───────────┘ └──┬─────────────┘                  │
│                          │                                │
│            ┌─────────────┼──────────────┐                 │
│     ┌──────▼──────┐ ┌────▼──────┐ ┌─────▼──────────┐    │
│     │LlamaEngine  │ │Apple       │ │ModelCatalog    │    │
│     │(llama.cpp)  │ │Foundation  │ │(8个模型定义)    │    │
│     │C API 直调   │ │(iOS 26+预备)│ │4种ChatTemplate │    │
│     └──────┬──────┘ └────────────┘ └────────────────┘    │
│            │                                              │
└────────────┼──────────────────────────────────────────────┘
             │ import llama
     ┌───────▼────────┐
     │ llama.xcframework │  静态库 (Metal GPU 加速)
     │ - libllama.a     │
     │ - module.modulemap│
     │ - llama.h/ggml.h │
     └────────────────┘
```

### 分层说明

| 层 | 文件 | 职责 |
|---|---|---|
| **UI 层** | `App.swift`, `ContentView.swift`, `ChatBubbleView.swift` | SwiftUI 视图，纯展示 |
| **状态层** | `ChatViewModel.swift` | `@Observable @MainActor`，管理消息列表、生成状态、引擎切换 |
| **模型管理层** | `LlamaModel.swift` + `ModelCatalog.swift` | 模型下载（URLSession）、本地存储、选择持久化（UserDefaults） |
| **推理协议层** | `LLMEngineProtocol.swift` | `LLMEngine` 协议抽象，工厂方法 `makeEngine()` |
| **推理实现层** | `LlamaEngine.swift` | llama.cpp C API 封装，Metal GPU 卸载，流式输出 |
| **C/C++ 底层** | `llama.xcframework` | 静态编译 libllama.a，包含 GGML Metal 后端 |

---

## 模型加载流程

这是整个应用最核心的路径，从用户点击「加载」到模型就绪的全过程：

### 第一步：模型文件定位

```
用户选择模型
    │
    ▼
LlamaModel.selectedModelID = "qwen3.5-2b"    // 持久化到 UserDefaults
    │
    ▼
LlamaModel.modelPath                          // 计算属性
    ├─ 文件在 Documents/qwen3.5-2b-Q4_K_M.gguf? → 返回路径
    └─ 未下载? → 提示用户先下载
```

模型通过 `URLSession` 从 **HF Mirror** (`hf-mirror.com`) 下载，走 `DownloadDelegate` 回调，下载完成后自动将临时文件移动到 `Documents/` 目录。

### 第二步：引擎初始化（LlamaEngine.load）

```swift
// ===== 阶段 1: 初始化 llama.cpp 后端 =====
llama_backend_init()          // 一次性全局初始化 Metal/CPU 后端

// ===== 阶段 2: 加载模型权重（GGUF 文件） =====
var mparams = llama_model_default_params()
mparams.n_gpu_layers = 99     // 将 99 层卸载到 GPU（Metal）
mparams.use_mmap = true       // 使用 mmap 映射文件，节省内存
let model = llama_model_load_from_file(path, mparams)
```

关键参数说明：

| 参数 | 值 | 含义 |
|---|---|---|
| `n_gpu_layers` | 99 | 将最多的层卸载到 GPU。数值越大 GPU 利用率越高。99 表示全部推给 GPU |
| `use_mmap` | true | 用 `mmap` 映射 GGUF 文件到虚拟内存，多个进程可共享只读内存页（iOS 上即使只有一个进程也会降低物理内存压力） |

### 第三步：创建推理上下文

```swift
// ===== 阶段 3: 创建上下文（KV Cache） =====
var cparams = llama_context_default_params()
cparams.n_ctx = 2048          // 上下文窗口大小（token 数）
cparams.n_batch = 512         // 批处理大小，影响首 token 延迟
cparams.n_threads = 处理器核数  // CPU 线程数（越小模型这个越不重要）
let context = llama_init_from_model(model, cparams)
```

关键参数说明：

| 参数 | 值 | 含义 |
|---|---|---|
| `n_ctx` | 2048 | 上下文窗口 = 2048 tokens，影响 KV Cache 显存占用。当前主力是「输入 + 输出 ≤ 2048」 |
| `n_batch` | 512 | 首次 decode 的 batch size。prompt tokenize 后打包一个 batch 一次解码，越大越快但越吃内存 |
| `n_threads` | 自动检测 | 从 `ProcessInfo.activeProcessorCount` 获取，随设备动态调整 |

> **KV Cache 计算公式**：`2 * bytes_per_element * n_embd * n_layer * n_ctx`  
> 以 Qwen3.5 2B (n_embd=1536, n_layer=28, Q4_K_M) 为例约 336 MB 显存

### 第四步：构建采样器链

```swift
// ===== 阶段 4: 采样器链 =====
let chain = llama_sampler_chain_init(params)
llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))   // ①
llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))       // ②
llama_sampler_chain_add(chain, llama_sampler_init_dist(random_seed)) // ③
```

采样器按顺序执行，**dist 必须放在链末尾**：

```
Top-P (0.9, min_keep=1)  →  Temperature (0.7)  →  Distribution (采样)
  过滤低概率 token             调整概率分布            实际采样输出
```

### 完整加载状态机

```
未加载 ──load(path)────────────────────────────────────► 已加载
         ├─ llama_backend_init()         ← 后端初始化
         ├─ llama_model_load_from_file() ← 模型权重加载（耗时最长）
         ├─ llama_init_from_model()      ← 创建上下文/KV Cache
         └─ llama_sampler_chain_init()   ← 采样器链

已加载 ──unload()──────────────────────────────────────► 未加载
         ├─ llama_sampler_free()         ← 释放采样器
         ├─ llama_free()                 ← 释放上下文
         ├─ llama_model_free()           ← 释放模型权重
         └─ shouldStop = false           ← 重置停止标志
```

---

## 推理运行流程

这是用户发送消息后，从 prompt 到流式 token 输出的完整路径：

### 第一步：构建 Prompt（ChatViewModel）

```
用户输入 "你好"
    │
    ▼
LlamaModel.chatTemplate.buildPrompt()
    │
    ▼
输出完整 prompt:
<|im_start|>system
你是语日记的AI助手，请用中文简洁回答。<|im_end|>
<|im_start|>user
你好<|im_end|>
<|im_start|>assistant
```

不同模型使用不同的 ChatTemplate：

| 模板 | 格式 | 适用模型 |
|---|---|---|
| `qwen` | `<\|im_start\|>system/user/assistant<\|im_end\|>` | Qwen 2.5/3/3.5、MiniCPM5 |
| `gemma` | `<start_of_turn>system/user/model<end_of_turn>` | Gemma 4 |
| `zephyr` | `<\|system\|>/<\|user\|>/<\|assistant\|>` | TinyLlama |

### 第二步：Tokenize（主线程）

```swift
// 第一次调用获取 token 数量（nTokens 返回负值 = 所需缓冲区大小）
let nTokens = llama_tokenize(vocab, prompt, nil, 0, true, true)
// nTokens = -15 → 需要 15 个 token 的空间

// 第二次调用实际 tokenize
var inputTokens = [llama_token](repeating: 0, count: 15)
let actual = llama_tokenize(vocab, prompt, &inputTokens, 15, true, true)
// inputTokens = [151644, 8948, 198, 2610, ...]
```

`add_bos` (true) 会自动在开头插入 BOS token (`<|im_start|>` for Qwen, `<bos>` for Gemma)。

### 第三步：首次 Decode（后台队列）

```swift
// 把所有 prompt token 打包成一个 batch，一次 decode
let batch = llama_batch_get_one(&inputTokens, batchSize)
llama_decode(context, batch)
```

这一步会把所有 prompt token 一次性送入 transformer，结果写入 KV Cache。这是推理过程中 **单次耗时最长** 的操作。

### 第四步：自回归生成循环（后台队列）

```swift
for step in 0..<maxTokens {
    // ① 采样下一个 token
    nextToken = llama_sampler_sample(sampler, context, -1)
    
    // ② 检查是否结束
    if nextToken == eos || isEOG(nextToken) { break }
    
    // ③ 将 token ID 转回文本
    let len = llama_token_to_piece(vocab, nextToken, &buf, 256, 0, true)
    let text = String(data: buf[...len], encoding: .utf8)
    continuation.yield(text)    // ← 流式输出到 UI
    
    // ④ 用当前 token 喂下一轮 decode
    let batch = llama_batch_get_one(&nextToken, 1)
    llama_decode(context, batch)
}
```

### 并发模型

```
主线程 (@MainActor)                    后台队列 (serial)
─────────────────                    ─────────────────
send() ──► tokenize 同步 ──┐          queue.async {
                          │            llama_decode(首次 batch)
                          │            for step...{
                          │              llama_sampler_sample()
                          │              → continuation.yield(text)
                          │              llama_decode(单 token)
                          │            }
                          │            continuation.finish()
                          └─ AsyncThrowingStream ──► ViewModel 收集 streamingText
                                                         │
                                                         ▼
                                                    UI 实时更新
```

**为什么 tokenize 在主线程做？**
- `llama_tokenize` 是纯 CPU 运算且极快（毫秒级）
- `context/vocab/sampler` 指针不是 `Sendable`，需要在主线程上安全访问
- 实际的 decode 循环在后台 `DispatchQueue` 进行，不阻塞 UI

**`nonisolated(unsafe)` 的使用：**
```swift
nonisolated(unsafe) let ctxRef = context   // 将 C 指针穿入 @Sendable closure
```
这是因为 llama.cpp 的 opaque pointer 在 Swift 上不是 `Sendable`，但推理队列是串行的，实际不会并发访问，所以用 `nonisolated(unsafe)` 显式声明安全。

### 停止生成

```swift
func stopGeneration() {
    shouldStop = true   // 设置标志位
}
```

生成循环在每次迭代开始时检查 `shouldStop`，一旦为 `true` 立即退出。`shouldStop` 不是 `@MainActor` 隔离的，所以任何线程都可以安全设置。

---

## 模型目录

8 个预置模型，涵盖 0.5B ~ 4B 参数范围，全部 Q4_K_M 量化：

| 模型 | 大小 | 推荐内存 | ChatTemplate | 特点 |
|---|---|---|---|---|
| Qwen2.5 0.5B | 491 MB | 2 GB | qwen | 超轻量入门，下载快、响应快 |
| Qwen2.5 1.5B | 1.15 GB | 3 GB | qwen | 推荐！中文流畅自然 |
| Qwen3 0.6B | 484 MB | 2 GB | qwen | 最新千问3代，32K 上下文 |
| Qwen3.5 2B | 1.28 GB | 4 GB | qwen | **推荐！** 3.5 代最强小模型 |
| Qwen3.5 4B | 2.74 GB | 6 GB | qwen | 接近云端体验 |
| MiniCPM5 1B | 688 MB | 3 GB | qwen | 面壁端侧 SOTA，支持思考模式 |
| Gemma 4 E2B | 3.46 GB | 6 GB | gemma | Google 最新端侧，Apache 2.0 开源 |
| TinyLlama 1.1B | 637 MB | 2 GB | zephyr | 经典英文小模型 |

> 所有模型均从 [HF Mirror](https://hf-mirror.com) 下载，格式为 GGUF Q4_K_M。

---

## llama.cpp 集成

### XCFramework 构建

llama.cpp 通过 CMake 交叉编译为静态 XCFramework：

```bash
# 设备端 (arm64)
cmake -B build-device -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
  -DPLATFORM=OS64 -DGGML_METAL=ON

# 模拟器 (arm64 + x86_64)
cmake -B build-sim -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
  -DPLATFORM=SIMULATOR64 -DGGML_METAL=ON

# 打包 XCFramework
xcodebuild -create-xcframework \
  -framework build-device/llama.framework \
  -framework build-sim/llama.framework \
  -output llamachat-ios/llama.xcframework
```

### 模块映射（无需 Bridging Header）

通过 XCFramework 内部的 `module.modulemap` 直接暴露 C API 给 Swift：

```
framework module llama {
    umbrella header "llama.h"
    export *
    module * { export * }
}
```

Swift 代码只需 `import llama` 即可调用 `llama_model_load_from_file`、`llama_decode` 等 C 函数。

### 链接选项

| 标志 | 用途 |
|---|---|
| `-lc++` | 链接 C++ 标准库（llama.cpp 用 C++17 编写） |
| `-framework Accelerate` | 链接 Apple 的 Accelerate 框架（BLAS/LAPACK，GGML 在非 Metal 路径上使用） |

---

## 项目结构

```
llamachat-ios/
├── LlamaChatIOS/
│   ├── App/
│   │   ├── App.swift               # @main 入口
│   │   ├── ContentView.swift       # 主界面
│   │   ├── ChatBubbleView.swift    # 消息气泡
│   │   └── ChatViewModel.swift     # 核心 ViewModel
│   └── LLM/
│       ├── LLMEngineProtocol.swift # 引擎协议 + Apple Foundation 适配
│       ├── LlamaEngine.swift       # llama.cpp C API 封装
│       ├── LlamaModel.swift        # 模型下载/管理
│       └── ModelCatalog.swift      # 8 模型定义 + ChatTemplate
├── llama.xcframework/              # 预编译的 llama.cpp 静态库
├── LlamaChatIOS.xcodeproj/
└── Info.plist

llamachat/                           # macOS SwiftPM 版本（通过 subprocess 调用 llama-cli）
├── Package.swift
├── App/
│   ├── LlamaChatApp.swift
│   ├── ChatViewModel.swift
│   ├── ContentView.swift
│   └── MessageBubble.swift
└── Sources/LlamaKit/
    ├── LlamaModel.swift             # Process + llama-cli 子进程
    ├── LlamaService.swift
    └── ModelManager.swift

llama.cpp/                           # git submodule，用于编译 llama.xcframework
```

---

## 环境要求

| 项目 | 最低版本 |
|---|---|
| iOS | 17.0+ |
| Xcode | 16.3+ |
| Swift | 5.0+ |
| 设备内存 | 2 GB+ (取决于所选模型) |

---

## 许可

MIT License
