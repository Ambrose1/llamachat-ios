import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showModelPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 状态栏
                statusBar

                // 下载进度
                if viewModel.selectedEngine == .llamaCpp,
                   viewModel.model.isDownloading {
                    downloadProgressBar
                }

                Divider()

                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.messages.isEmpty,
                               !viewModel.engine.isLoaded {
                                welcomeView
                            }
                            ForEach(viewModel.messages) { msg in
                                ChatBubbleView(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: viewModel.streamingText) { _, _ in
                        if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                Divider()

                // 输入栏
                inputBar
            }
            .navigationTitle("LlamaChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(model: viewModel.model) { modelID in
                    viewModel.switchModel(to: modelID)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Picker("引擎", selection: $viewModel.selectedEngine) {
                ForEach(EngineType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 8) {
                // 模型选择按钮
                if viewModel.selectedEngine == .llamaCpp {
                    Button { showModelPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(viewModel.model.selectedModel?.name ?? "选择模型")
                                .font(.caption)
                        }
                    }
                }

                if !viewModel.engine.isLoaded,
                   viewModel.selectedEngine == .llamaCpp,
                   viewModel.model.isModelAvailable {
                    Button("加载") { viewModel.loadModelIfNeeded() }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 16) {
            if viewModel.selectedEngine == .llamaCpp {
                if let err = viewModel.model.lastDownloadError {
                    // 下载出错了
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)

                    Text("下载失败")
                        .font(.headline)

                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    modelDownloadList
                } else if viewModel.model.downloadedModels.isEmpty {
                    // 没有任何已下载模型
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.indigo)

                    Text("下载模型开始使用")
                        .font(.headline)

                    Text("推荐 Qwen2.5 1.5B（中文优化）")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    modelDownloadList
                } else if !viewModel.model.isModelAvailable {
                    // 有其他模型但当前选中的未下载
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("\(viewModel.model.selectedModel?.name ?? "") 未下载")
                        .font(.headline)

                    Text("点击下载或切换到已下载模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    downloadCurrentButton
                } else {
                    // 模型已下载
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("\(viewModel.model.selectedModel?.name ?? "") 已就绪")
                        .font(.headline)

                    if let loadErr = viewModel.lastLoadError {
                        Text("加载失败: \(loadErr)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("点击右上角「加载」开始对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "apple.logo")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Apple AI 不可用")
                    .font(.headline)

                Text("需要 Xcode 17+ / iOS 26 SDK\n当前 SDK 不含 FoundationModels 框架")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 40)
    }

    private var modelDownloadList: some View {
        VStack(spacing: 10) {
            ForEach(ModelCatalog.allModels) { modelInfo in
                modelDownloadRow(modelInfo)
            }
        }
        .padding(.horizontal, 24)
    }

    private func modelDownloadRow(_ modelInfo: ModelInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(modelInfo.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if modelInfo.chineseOptimized {
                        Text("中文优化")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(modelInfo.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if modelInfo.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else if viewModel.model.downloadingModelID == modelInfo.id {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button { viewModel.downloadModel(modelInfo.id) } label: {
                    Text(modelInfo.formattedSize)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if modelInfo.isDownloaded {
                viewModel.switchModel(to: modelInfo.id)
            } else if viewModel.model.downloadingModelID != modelInfo.id {
                viewModel.downloadModel(modelInfo.id)
            }
        }
    }

    private var downloadCurrentButton: some View {
        Button {
            viewModel.downloadModel()
        } label: {
            Text("下载 \(viewModel.model.selectedModel?.formattedSize ?? "")")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.model.isDownloading)
    }

    // MARK: - Download Progress

    private var downloadProgressBar: some View {
        VStack(spacing: 4) {
            if let name = viewModel.model.selectedModel?.name {
                Text("正在下载 \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.model.downloadProgress)
                .progressViewStyle(.linear)
            Text("\(Int(viewModel.model.downloadProgress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isGenerating {
                ProgressView()
                    .scaleEffect(0.6)
                Button("停止") { viewModel.stopGeneration() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        if viewModel.engine.isLoaded { return .green }
        if viewModel.lastLoadError != nil { return .red }
        if viewModel.model.lastDownloadError != nil { return .red }
        return .orange
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入消息...", text: $viewModel.inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.send() }
                .disabled(!viewModel.canType)

            Button { viewModel.send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .disabled(!viewModel.canType)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerView: View {
    let model: LlamaModel
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("已下载") {
                    if model.downloadedModels.isEmpty {
                        Text("暂无已下载模型")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(model.downloadedModels) { modelInfo in
                            modelRow(modelInfo, isDownloaded: true)
                        }
                    }
                }

                Section("可下载") {
                    ForEach(ModelCatalog.allModels.filter { !$0.isDownloaded }) { modelInfo in
                        modelRow(modelInfo, isDownloaded: false)
                    }
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func modelRow(_ modelInfo: ModelInfo, isDownloaded: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(modelInfo.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if modelInfo.chineseOptimized {
                        Text("中文")
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    if modelInfo.id == model.selectedModelID {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                Text(modelInfo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(modelInfo.formattedSize) · 最低 \(modelInfo.minRAMGB)GB 内存")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDownloaded {
                Button("选择") {
                    onSelect(modelInfo.id)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.downloadingModelID == modelInfo.id {
                VStack(spacing: 2) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("\(Int(model.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("下载") {
                    model.downloadModel(modelInfo.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
