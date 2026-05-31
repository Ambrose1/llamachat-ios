import Foundation
import Observation

/// 管理模型选择、下载、本地文件发现。
@MainActor
@Observable
final class LlamaModel {
    // MARK: - Published state

    /// 当前选中的模型（持久化到 UserDefaults）
    var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "selectedModelID") }
    }

    /// 当前正在下载的模型 ID，nil 表示未在下载
    private(set) var downloadingModelID: String?
    private(set) var downloadProgress: Double = 0

    /// **关键**：已下载模型 ID 集合（stored property，驱动 UI 更新）。
    /// 在 init 时从文件系统扫描，下载成功/删除时主动维护。
    /// 不依赖纯文件系统计算的 `ModelInfo.isDownloaded`，避免 @Observable 追踪失效。
    private(set) var downloadedModelIDs: Set<String> = []
    private(set) var lastDownloadError: String?

    // MARK: - Private

    private var downloadTask: URLSessionDownloadTask?
    private let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    // MARK: - Init

    init() {
        // 扫描文件系统，初始化已下载模型集合
        var ids = Set<String>()
        for model in ModelCatalog.allModels {
            if model.isDownloaded { ids.insert(model.id) }
        }
        self.downloadedModelIDs = ids

        let saved = UserDefaults.standard.string(forKey: "selectedModelID")
        // 默认选第一个已下载的模型，否则选第一个（Qwen2.5 0.5B）
        if let saved, ModelCatalog.allModels.contains(where: { $0.id == saved }) {
            self.selectedModelID = saved
        } else if let first = ModelCatalog.allModels.first(where: { ids.contains($0.id) }) {
            self.selectedModelID = first.id
        } else {
            self.selectedModelID = ModelCatalog.allModels.first!.id
        }
    }

    // MARK: - Computed

    /// 所有可选模型
    var availableModels: [ModelInfo] { ModelCatalog.allModels }

    /// 当前选中的模型信息
    var selectedModel: ModelInfo? {
        ModelCatalog.allModels.first { $0.id == selectedModelID }
    }

    /// 当前模型是否已下载（读 stored property，确保 @Observable 追踪）
    var isModelAvailable: Bool { downloadedModelIDs.contains(selectedModelID) }

    /// 当前模型的本地文件路径
    var modelPath: String? { selectedModel?.localPath }

    /// 当前模型的对话模板
    var chatTemplate: ChatTemplate { selectedModel?.chatTemplate ?? .qwen }

    /// 是否正在下载
    var isDownloading: Bool { downloadingModelID != nil }

    /// 已下载的模型列表（读 stored property，确保 UI 更新）
    var downloadedModels: [ModelInfo] {
        ModelCatalog.allModels.filter { downloadedModelIDs.contains($0.id) }
    }

    /// 返回指定模型的本地路径（不限于当前选中模型）
    static func path(for modelID: String) -> String? {
        ModelCatalog.allModels.first { $0.id == modelID }?.localPath
    }

    // MARK: - Actions

    /// 下载指定模型
    func downloadModel(_ modelID: String? = nil) {
        let id = modelID ?? selectedModelID
        guard let model = ModelCatalog.allModels.first(where: { $0.id == id }),
              !model.isDownloaded,
              !isDownloading else { return }

        downloadingModelID = id
        downloadProgress = 0
        lastDownloadError = nil

        let dest = documentsDir.appendingPathComponent(model.filename)

        let session = URLSession(
            configuration: .default,
            delegate: DownloadDelegate(
                destinationURL: dest,
                progress: { [weak self] p in
                    Task { @MainActor in self?.downloadProgress = p }
                },
                completion: { [weak self] success in
                    Task { @MainActor in
                        self?.handleDownloadComplete(success: success, model: model)
                    }
                }
            ),
            delegateQueue: nil
        )

        downloadTask = session.downloadTask(with: model.downloadURL)
        downloadTask?.resume()
    }

    /// 取消当前下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModelID = nil
        downloadProgress = 0
    }

    /// 删除已下载的模型文件释放空间
    func deleteModel(_ modelID: String) {
        guard let model = ModelCatalog.allModels.first(where: { $0.id == modelID }),
              downloadedModelIDs.contains(modelID) else { return }
        let file = documentsDir.appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: file)
        // **关键修复**：维护 stored property
        downloadedModelIDs.remove(modelID)
        print("[LlamaModel] 模型已删除：\(model.name)")
    }

    // MARK: - Private

    private func handleDownloadComplete(success: Bool, model: ModelInfo) {
        downloadingModelID = nil
        downloadTask = nil

        guard success else {
            downloadProgress = 0
            lastDownloadError = "下载失败：网络错误或文件保存失败"
            print("[LlamaModel] 下载失败：Delegate 返回 success=false")
            return
        }

        let dest = documentsDir.appendingPathComponent(model.filename)

        // 验证文件确实存在（delegate 中已同步 move，这里二次确认）
        guard FileManager.default.fileExists(atPath: dest.path) else {
            downloadProgress = 0
            lastDownloadError = "文件保存后验证失败"
            print("[LlamaModel] 错误：文件不存在于 \(dest.path)")
            return
        }

        downloadProgress = 1.0
        downloadedModelIDs.insert(model.id)
        selectedModelID = model.id
        lastDownloadError = nil
        print("[LlamaModel] 模型下载完成：\(model.name) → \(dest.path)")
    }
}

// MARK: - URLSession Download Delegate

/// 在 `didFinishDownloadingTo` 回调内同步将临时文件移动到目标路径，
/// 因为系统会在该回调返回后删除临时文件，异步移动会导致文件丢失。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    let progressHandler: (Double) -> Void
    let completionHandler: (Bool) -> Void

    init(destinationURL: URL,
         progress: @escaping (Double) -> Void,
         completion: @escaping (Bool) -> Void) {
        self.destinationURL = destinationURL
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(p)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // ⚠️ 关键：必须在 delegate 回调内同步 move，系统会在返回后清理临时文件
        let dest = destinationURL

        // 删除旧文件 + 确保父目录存在
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.moveItem(at: location, to: dest)
            print("[DownloadDelegate] 文件已移动到 \(dest.path)")
            completionHandler(true)
        } catch {
            print("[DownloadDelegate] 文件移动失败: \(error.localizedDescription)")
            completionHandler(false)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            print("[DownloadDelegate] 下载出错: \(error!.localizedDescription)")
            completionHandler(false)
        }
    }
}
