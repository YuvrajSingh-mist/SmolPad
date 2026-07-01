import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable {
    case onDevice = "On Device"
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"
    case mlx = "MLX"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .onDevice: TextModelCatalog.defaultOptionID
        case .claude: "claude-opus-4-6"
        case .openai: "gpt-4o"
        case .ollama: "gemma3:4b"
        case .mlx: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }
}

enum InferencePath: String, CaseIterable, Identifiable {
    case directVLM = "Direct VLM"
    case appleVisionOCRPlusText = "Vision OCR + Text"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .directVLM:
            "Send the selected note image directly to the active AI backend for image-grounded answers."
        case .appleVisionOCRPlusText:
            "Extract note text on-device with Apple Vision first, then send the OCR transcript along with the image for faster text-first reasoning."
        }
    }
}

enum OCRBackend: String, CaseIterable, Identifiable {
    case appleVision = "Apple Vision"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .appleVision:
            "Built-in on-device OCR with bounding-box and confidence support."
        }
    }
}

struct TextModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let runtime: String
    let summary: String
}

enum TextModelCatalog {
    static let options: [TextModelOption] = [
        TextModelOption(
            id: "trymirai/Qwen3.5-4B-L",
            displayName: "Qwen 3.5 4B L",
            runtime: "Mirai",
            summary: "Default on-device choice. Best balance of speed, memory, and conversation quality."
        ),
        TextModelOption(
            id: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B 4-bit",
            runtime: "MLX / Mirai-ready",
            summary: "Strong reasoning fallback with a compact 4-bit footprint."
        ),
        TextModelOption(
            id: "trymirai/Qwen3.5-2B-L",
            displayName: "Qwen 3.5 2B L",
            runtime: "Mirai",
            summary: "Speed mode for lower latency and memory use."
        ),
        TextModelOption(
            id: "mlx-community/gemma-3-4b-it-8bit",
            displayName: "Gemma 3 4B 8-bit",
            runtime: "MLX / Mirai-ready",
            summary: "Higher-quality Gemma option when memory headroom allows."
        )
    ]

    static let defaultOptionID = "trymirai/Qwen3.5-4B-L"

    static func option(for id: String) -> TextModelOption? {
        options.first { $0.id == id }
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
    var inferencePath: InferencePath
    var ocrBackend: OCRBackend
    var textModelID: String

    private enum Key: String {
        case provider
        case apiKey
        case ollamaURL
        case mlxURL
        case model
        case inferencePath
        case ocrBackend
        case textModelID
    }

    init() {
        let defaults = UserDefaults.standard
        let savedProviderRaw = defaults.string(forKey: Key.provider.rawValue) ?? ""
        provider = AIProvider(rawValue: savedProviderRaw) ?? .mlx
        apiKey = defaults.string(forKey: Key.apiKey.rawValue) ?? ""
        let savedOllamaURL = defaults.string(forKey: Key.ollamaURL.rawValue) ?? ""
        ollamaURL = Self.normalizedServerURL(savedOllamaURL, port: 11434)
        let savedMLXURL = defaults.string(forKey: Key.mlxURL.rawValue) ?? ""
        mlxURL = Self.normalizedServerURL(savedMLXURL, port: 8080)
        let savedModel = defaults.string(forKey: Key.model.rawValue) ?? ""
        let defaultModel = provider.defaultModel
        model = savedModel.isEmpty ? defaultModel : savedModel
        let savedInferencePath = defaults.string(forKey: Key.inferencePath.rawValue) ?? ""
        inferencePath = InferencePath(rawValue: savedInferencePath) ?? .directVLM
        let savedOCRBackend = defaults.string(forKey: Key.ocrBackend.rawValue) ?? ""
        ocrBackend = OCRBackend(rawValue: savedOCRBackend) ?? .appleVision
        let savedTextModelID = defaults.string(forKey: Key.textModelID.rawValue) ?? ""
        textModelID = TextModelCatalog.option(for: savedTextModelID) != nil
            ? savedTextModelID
            : TextModelCatalog.defaultOptionID
        applyProviderDefaultsIfNeeded()

        if provider.rawValue != savedProviderRaw
            || savedOllamaURL != ollamaURL
            || savedMLXURL != mlxURL
            || savedModel != model
            || savedInferencePath != inferencePath.rawValue
            || savedOCRBackend != ocrBackend.rawValue
            || savedTextModelID != textModelID {
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
        defaults.set(inferencePath.rawValue, forKey: Key.inferencePath.rawValue)
        defaults.set(ocrBackend.rawValue, forKey: Key.ocrBackend.rawValue)
        defaults.set(textModelID, forKey: Key.textModelID.rawValue)
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

    var selectedTextModel: TextModelOption {
        TextModelCatalog.option(for: textModelID) ?? TextModelCatalog.options[0]
    }

    func applyProviderDefaultsIfNeeded() {
        if provider == .onDevice {
            inferencePath = .appleVisionOCRPlusText
            model = selectedTextModel.id
        }
    }
}
