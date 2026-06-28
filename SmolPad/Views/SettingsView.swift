import SwiftUI

struct SettingsView: View {
    @Bindable var config: AIConfig
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

                switch config.provider {
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

                Section("Model") {
                    TextField("Model name", text: $config.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Text(modelHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Your API key is stored locally on this device only. Nothing is sent except your image and query when you press send.")
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
        case .claude: "e.g. claude-opus-4-6, claude-sonnet-4-6"
        case .openai: "e.g. gpt-4o, gpt-4o-mini"
        case .ollama: "e.g. gemma3:4b"
        case .mlx: "e.g. mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }
}
