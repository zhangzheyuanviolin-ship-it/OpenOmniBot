import Foundation

#if canImport(OmniInferServer)
import OmniInferServer
#endif

@MainActor
final class LocalModelCoordinator {
    static let shared = LocalModelCoordinator()

    private var backend = "llama.cpp"
    private var loadedBackend = "llama.cpp"
    private var activeModelId: String?
    private var loadedModelId: String?
    private let apiPort = 9099

    private init() {}

    func statusMessage() async -> LocalModelStatusMessage {
        LocalModelStatusMessage(
            apiRunning: loadedModelId != nil,
            apiReady: loadedModelId != nil,
            apiState: loadedModelId == nil ? "stopped" : "running",
            apiHost: "127.0.0.1",
            apiPort: Int64(apiPort),
            baseUrl: "http://127.0.0.1:\(apiPort)",
            activeModelId: activeModelId,
            backend: backend,
            loadedBackend: loadedBackend,
            loadedModelId: loadedModelId,
            backends: [
                LocalModelBackendMessage(id: "llama.cpp", label: "llama.cpp", available: true),
                LocalModelBackendMessage(id: "mlx", label: "MLX", available: true),
            ]
        )
    }

    func loadModel(modelId: String, backendId: String) async throws -> LocalModelStatusMessage {
        if modelId.isEmpty == false {
            activeModelId = modelId
        }
        backend = backendId.isEmpty ? backend : backendId

#if canImport(OmniInferServer)
        if #available(iOS 17, *) {
            let modelURL = modelDirectory().appendingPathComponent(activeModelId ?? "default")
            let success = await OmniInferServer.shared.loadModel(
                modelPath: modelURL.path,
                backend: backend
            )
            if success {
                loadedModelId = activeModelId
                loadedBackend = backend
            }
        }
#else
        loadedModelId = activeModelId
        loadedBackend = backend
#endif
        return await statusMessage()
    }

    func stopModel() async -> LocalModelStatusMessage {
#if canImport(OmniInferServer)
        if #available(iOS 17, *) {
            await OmniInferServer.shared.stop()
        }
#endif
        loadedModelId = nil
        return await statusMessage()
    }

    private func modelDirectory() -> URL {
        let workspace = TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
        let base = URL(fileURLWithPath: workspace.internalRootPath, isDirectory: true)
        return base.appendingPathComponent("models/OmniInfer-llama", isDirectory: true)
    }
}
