import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable {
    case onDevice = "On Device"
    case llamaCpp = "llama.cpp"
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"
    case mlx = "MLX"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .onDevice: TextModelCatalog.defaultOptionID
        case .llamaCpp: LlamaCppModelCatalog.defaultOptionID
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

struct LlamaCppModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let summary: String
    let estimatedFootprint: String
}

enum LlamaCppModelCatalog {
    static let options: [LlamaCppModelOption] = [
        LlamaCppModelOption(
            id: "Qwen2.5-VL-3B-Instruct-Q4_K_M",
            displayName: "Qwen 2.5 VL 3B Q4_K_M",
            summary: "Safest default for multi-turn VLM on constrained devices and local quantized llama.cpp deployments.",
            estimatedFootprint: "~3 GB total including the vision projector"
        ),
        LlamaCppModelOption(
            id: "Qwen2.5-VL-3B-Instruct-Q5_K_M",
            displayName: "Qwen 2.5 VL 3B Q5_K_M",
            summary: "Higher quality than Q4_K_M with a moderate storage and memory increase.",
            estimatedFootprint: "~3.5 GB total including the vision projector"
        ),
        LlamaCppModelOption(
            id: "Qwen2.5-VL-7B-Instruct-Q4_K_M",
            displayName: "Qwen 2.5 VL 7B Q4_K_M",
            summary: "Use only when you have plenty of RAM and want better visual reasoning than the 3B models.",
            estimatedFootprint: "~5.5 to 6.5 GB total including the vision projector"
        )
    ]

    static let defaultOptionID = "Qwen2.5-VL-3B-Instruct-Q4_K_M"

    static func option(for id: String) -> LlamaCppModelOption? {
        options.first { $0.id == id }
    }

    static let recommendedLaunchFlags = "--jinja --flash-attn --ctx-size 4096 --n-gpu-layers 99 --parallel 1"
}

struct TextModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let runtime: String
    let summary: String
    let recommendedProfile: String?
}

enum TextModelCatalog {
    static let options: [TextModelOption] = [
        TextModelOption(
            id: "trymirai/Qwen3.5-2B-M",
            displayName: "Qwen 3.5 2B M",
            runtime: "Mirai",
            summary: "Best default for 6 GB iPads. Lowest memory pressure while keeping chat quality solid.",
            recommendedProfile: "Recommended for 6 GB RAM"
        ),
        TextModelOption(
            id: "trymirai/Qwen3.5-2B-L",
            displayName: "Qwen 3.5 2B L",
            runtime: "Mirai",
            summary: "Higher-quality 2B option when you want better answers and can trade some latency.",
            recommendedProfile: "Recommended quality upgrade"
        ),
        TextModelOption(
            id: "trymirai/Qwen3.5-0.8B-L",
            displayName: "Qwen 3.5 0.8B L",
            runtime: "Mirai",
            summary: "Fast fallback for tighter memory budgets and quickest startup.",
            recommendedProfile: "Recommended fast fallback"
        ),
        TextModelOption(
            id: "trymirai/Qwen3.5-4B-M",
            displayName: "Qwen 3.5 4B M",
            runtime: "Mirai",
            summary: "Optional higher-capability model. Use only on devices with enough free RAM.",
            recommendedProfile: "Use with care on 6 GB RAM"
        )
    ]

    static let defaultOptionID = "trymirai/Qwen3.5-2B-M"

    static func option(for id: String) -> TextModelOption? {
        options.first { $0.id == id }
    }
}

@Observable
final class AIConfig {
    var provider: AIProvider
    var apiKey: String
    var llamaCppURL: String
    var ollamaURL: String
    var mlxURL: String
    var model: String
    var inferencePath: InferencePath
    var ocrBackend: OCRBackend
    var textModelID: String

    private enum Key: String {
        case provider
        case apiKey
        case llamaCppURL
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
        let resolvedProvider = AIProvider(rawValue: savedProviderRaw) ?? .llamaCpp
        provider = resolvedProvider
        apiKey = defaults.string(forKey: Key.apiKey.rawValue) ?? ""
        let savedOllamaURL = defaults.string(forKey: Key.ollamaURL.rawValue) ?? ""
        let savedMLXURL = defaults.string(forKey: Key.mlxURL.rawValue) ?? ""
        let savedLlamaCppURL = defaults.string(forKey: Key.llamaCppURL.rawValue) ?? ""
        llamaCppURL = Self.normalizedServerURL(
            savedLlamaCppURL.isEmpty
                ? Self.inferredLlamaCppURL(mlxURL: savedMLXURL, ollamaURL: savedOllamaURL)
                : savedLlamaCppURL,
            port: 8081
        )
        ollamaURL = Self.normalizedServerURL(savedOllamaURL, port: 11434)
        mlxURL = Self.normalizedServerURL(savedMLXURL, port: 8080)
        let savedModel = defaults.string(forKey: Key.model.rawValue) ?? ""
        let defaultModel = resolvedProvider.defaultModel
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
            || savedLlamaCppURL != llamaCppURL
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
        defaults.set(llamaCppURL, forKey: Key.llamaCppURL.rawValue)
        defaults.set(ollamaURL, forKey: Key.ollamaURL.rawValue)
        defaults.set(mlxURL, forKey: Key.mlxURL.rawValue)
        defaults.set(model, forKey: Key.model.rawValue)
        defaults.set(inferencePath.rawValue, forKey: Key.inferencePath.rawValue)
        defaults.set(ocrBackend.rawValue, forKey: Key.ocrBackend.rawValue)
        defaults.set(textModelID, forKey: Key.textModelID.rawValue)
    }

    private static func normalizedServerURL(_ rawValue: String, port: Int) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        components.scheme = components.scheme ?? "http"
        if components.port == nil {
            components.port = port
        }
        return components.string ?? trimmed
    }

    private static func inferredLlamaCppURL(mlxURL: String, ollamaURL: String) -> String {
        for candidate in [mlxURL, ollamaURL] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { continue }
            components.scheme = components.scheme ?? "http"
            components.port = 8081
            components.path = ""
            return components.string ?? ""
        }
        return ""
    }

    var selectedTextModel: TextModelOption {
        TextModelCatalog.option(for: textModelID) ?? TextModelCatalog.options[0]
    }

    var selectedLlamaCppModel: LlamaCppModelOption {
        LlamaCppModelCatalog.option(for: model) ?? LlamaCppModelCatalog.options[0]
    }

    func applyProviderDefaultsIfNeeded() {
        if provider == .onDevice {
            inferencePath = .appleVisionOCRPlusText
            model = selectedTextModel.id
        } else if provider == .llamaCpp {
            inferencePath = .directVLM
            if LlamaCppModelCatalog.option(for: model) == nil {
                model = LlamaCppModelCatalog.defaultOptionID
            }
        }
    }
}
