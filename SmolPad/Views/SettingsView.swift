import SwiftUI

struct SettingsView: View {
    @Bindable var config: AIConfig
    @Bindable var voiceManager: VoiceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Provider") {
                    HStack(spacing: 0) {
                        ForEach(AIProvider.allCases) { provider in
                            Button {
                                config.provider = provider
                                config.model = provider.defaultModel
                                config.applyProviderDefaultsIfNeeded()
                            } label: {
                                Text(provider.rawValue)
                                    .font(.system(size: 13, weight: config.provider == provider ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(config.provider == provider
                                        ? Color.accentColor
                                        : Color.clear)
                                    .foregroundStyle(config.provider == provider
                                        ? Color.white
                                        : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                Section("Inference Path") {
                    Picker("Mode", selection: $config.inferencePath) {
                        ForEach(InferencePath.allCases) { path in
                            Text(path.rawValue).tag(path)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(config.inferencePath.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if config.provider == .llamaCpp {
                    Section("llama.cpp Model") {
                        Picker("Preset", selection: $config.model) {
                            ForEach(LlamaCppModelCatalog.options) { option in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName).tag(option.id)
                                    Text(option.estimatedFootprint)
                                }
                                .tag(option.id)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(config.selectedLlamaCppModel.estimatedFootprint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(config.selectedLlamaCppModel.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Install the GGUF text model and its matching `mmproj` file inside `Application Support/Models/llama.cpp/\(config.model)/` or `Documents/Models/llama.cpp/\(config.model)/`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if config.inferencePath == .appleVisionOCRPlusText {
                    Section("OCR") {
                        Picker("Backend", selection: $config.ocrBackend) {
                            ForEach(OCRBackend.allCases) { backend in
                                Text(backend.rawValue).tag(backend)
                            }
                        }

                        Text(config.ocrBackend.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Text Model") {
                        Picker("Preset", selection: $config.textModelID) {
                            ForEach(TextModelCatalog.options) { option in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName).tag(option.id)
                                    Text(option.recommendedProfile ?? option.runtime)
                                }
                                .tag(option.id)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(config.selectedTextModel.runtime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let recommendedProfile = config.selectedTextModel.recommendedProfile {
                                Text(recommendedProfile)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(config.selectedTextModel.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                switch config.provider {
                case .onDevice:
                    EmptyView()
                case .llamaCpp:
                    Section("Embedded Runtime") {
                        Text("Primary path: embedded `llama.cpp` + `libmtmd` with local GGUF files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Fallback path: `Uzu` OCR + text only when the local VLM files are missing or fail to load.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .claude, .openai:
                    Section("API Key") {
                        SecureField("Paste your API key", text: $config.apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                case .ollama:
                    Section("Ollama Server") {
                        TextField("http://192.168.1.8:11434", text: $config.ollamaURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                case .mlx:
                    Section("MLX Server") {
                        TextField("http://192.168.1.8:8080", text: $config.mlxURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                }

                if config.provider != .llamaCpp {
                    Section("Model") {
                        TextField("Model name", text: $config.model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text(modelHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Speech Input") {
                    Picker("Backend", selection: $voiceManager.preferredBackend) {
                        ForEach(SpeechRecognitionBackend.allCases) { backend in
                            Text(backend.rawValue).tag(backend)
                        }
                    }

                    Text(voiceManager.preferredBackendDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if voiceManager.preferredBackend != .appleSpeech {
                        TextField("WhisperKit model identifier", text: $voiceManager.whisperKitModelIdentifier)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text(
                            voiceManager.whisperKitAvailable
                                ? "WhisperKit runtime is available to this build."
                                : "WhisperKit runtime is not linked to this build yet, so Automatic will fall back to Apple Speech."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Recommended for production dictation: `large-v3-v20240930_626MB`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Your API key is stored locally on this device only. `llama.cpp` is the primary on-device multimodal path here, and `Uzu` stays available only as a fallback when the embedded VLM assets are unavailable.")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var modelHint: String {
        switch config.provider {
        case .onDevice: "Uses the selected on-device text model via Mirai."
        case .llamaCpp: "Uses the selected embedded GGUF preset."
        case .claude: "e.g. claude-opus-4-6, claude-sonnet-4-6"
        case .openai: "e.g. gpt-4o, gpt-4o-mini"
        case .ollama: "e.g. gemma3:4b"
        case .mlx: "e.g. mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }
}
