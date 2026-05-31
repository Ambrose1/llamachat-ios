import Foundation

public final class ModelManager {
    public static let shared = ModelManager()

    public func findModels(in directory: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var models: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "gguf" {
                models.append(url)
            }
        }
        return models.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func fileSize(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "未知"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
