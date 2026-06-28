import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"
    case mlx = "MLX"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .claude: "claude-opus-4-6"
        case .openai: "gpt-4o"
        case .ollama: "gemma3:4b"
        case .mlx: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }
}

@Observable
final class AIConfig {
    private static let currentHost = "192.168.1.8"
    private static let staleHosts = ["192.168.1.21", "192.168.1.100", "127.0.0.1", "localhost"]

    var provider: AIProvider
    var apiKey: String
    var ollamaURL: String
    var mlxURL: String
    var model: String

    private enum Key: String {
        case provider
        case apiKey
        case ollamaURL
        case mlxURL
        case model
    }

    init() {
        let defaults = UserDefaults.standard
        let savedProviderRaw = defaults.string(forKey: Key.provider.rawValue) ?? ""
        let savedProvider = AIProvider(rawValue: savedProviderRaw) ?? .mlx
        let savedModel = defaults.string(forKey: Key.model.rawValue) ?? ""
        let shouldMigrateToMLX = savedProvider == .ollama && (
            savedModel.isEmpty
            || savedModel.hasPrefix("qwen3-vl")
            || savedModel.hasPrefix("llava")
            || savedModel == "gemma3:4b"
            || savedModel.hasPrefix("local-")
        )
        provider = shouldMigrateToMLX ? .mlx : savedProvider
        apiKey = defaults.string(forKey: Key.apiKey.rawValue) ?? ""
        let savedOllamaURL = defaults.string(forKey: Key.ollamaURL.rawValue) ?? ""
        ollamaURL = Self.normalizedServerURL(savedOllamaURL, port: 11434)
        let savedMLXURL = defaults.string(forKey: Key.mlxURL.rawValue) ?? ""
        mlxURL = Self.normalizedServerURL(savedMLXURL, port: 8080)
        if shouldMigrateToMLX {
            model = AIProvider.mlx.defaultModel
        } else if savedProvider == .mlx || (
            savedProvider == .ollama && (
                savedModel.hasPrefix("qwen3-vl")
                || savedModel.hasPrefix("llava")
                || savedModel == "gemma3:4b"
                || savedModel.hasPrefix("local-")
            )
        ) {
            model = savedProvider.defaultModel
        } else {
            model = savedModel.isEmpty ? savedProvider.defaultModel : savedModel
        }

        if provider.rawValue != savedProviderRaw
            || savedOllamaURL != ollamaURL
            || savedMLXURL != mlxURL
            || savedModel != model {
            save()
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(provider.rawValue, forKey: Key.provider.rawValue)
        defaults.set(apiKey, forKey: Key.apiKey.rawValue)
        defaults.set(ollamaURL, forKey: Key.ollamaURL.rawValue)
        defaults.set(mlxURL, forKey: Key.mlxURL.rawValue)
        defaults.set(model, forKey: Key.model.rawValue)
    }

    private static func normalizedServerURL(_ rawValue: String, port: Int) -> String {
        let fallback = "http://\(currentHost):\(port)"
        guard !rawValue.isEmpty else { return fallback }
        guard var components = URLComponents(string: rawValue) else { return rawValue }

        if let host = components.host, staleHosts.contains(host) {
            components.scheme = components.scheme ?? "http"
            components.host = currentHost
            components.port = port
            return components.string ?? fallback
        }

        return rawValue
    }
}
