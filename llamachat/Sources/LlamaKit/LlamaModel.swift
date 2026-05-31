import Foundation

/// Calls llama-cli as a subprocess and streams token output.
public final class LlamaModel {
    private let cliPath: String
    private let modelPath: String
    private let gpuLayers: Int32
    private let contextSize: UInt32

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?

    public init(cliPath: String, modelPath: String, gpuLayers: Int32 = 99, contextSize: UInt32 = 2048) {
        self.cliPath = cliPath
        self.modelPath = modelPath
        self.gpuLayers = gpuLayers
        self.contextSize = contextSize
    }

    /// Stream generation tokens from the model.
    public func generate(
        prompt: String,
        maxTokens: Int32 = 256,
        temperature: Float = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let p = Process()
            let outPipe = Pipe()
            let inPipe = Pipe()

            let binDir = (cliPath as NSString).deletingLastPathComponent
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = binDir
            p.environment = env

            p.executableURL = URL(fileURLWithPath: cliPath)
            p.arguments = [
                "-m", modelPath,
                "-ngl", "\(gpuLayers)",
                "-c", "\(contextSize)",
                "-n", "\(maxTokens)",
                "--temp", "\(temperature)",
                "--no-display-prompt",
                "--conversation",
                "-p", prompt,
            ]

            p.standardOutput = outPipe
            p.standardInput = inPipe
            p.standardError = FileHandle.nullDevice

            self.process = p
            self.stdoutPipe = outPipe
            self.stdinPipe = inPipe

            let fileHandle = outPipe.fileHandleForReading
            fileHandle.readabilityHandler = { [weak self] fh in
                guard self != nil else { return }
                let data = fh.availableData
                if data.isEmpty {
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(text)
                }
            }

            p.terminationHandler = { _ in
                fileHandle.readabilityHandler = nil
                continuation.finish()
            }

            do {
                try p.run()
            } catch {
                fileHandle.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }

    /// Send raw line to stdin (for multi-turn conversation).
    public func sendLine(_ line: String) {
        guard let stdinPipe else { return }
        if let data = (line + "\n").data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
    }

    /// Stop generation and terminate the process.
    public func stop() {
        process?.terminate()
        process = nil
        stdoutPipe = nil
        stdinPipe = nil
    }

    deinit {
        stop()
    }
}
