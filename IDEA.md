# SmolPad — Complete Implementation Brief

## What you are building

An iPad notes app with an exceptional handwriting experience powered by PencilKit. The user writes freely with Apple Pencil, selects any region (lasso or rectangle), and sends that captured region as an image to an AI model (Claude API, OpenAI API, or Ollama on LAN). A floating chat panel streams the response. Voice input is optional for the query. No cloud lock-in, no credits, no subscriptions — the user brings their own API key or Ollama server.

**Primary use case:** handwritten math → select region → ask AI to explain or solve → get streamed answer.

---

## Non-negotiables

- Writing must feel exceptional. PKCanvasView with `.anyInput` drawing policy. Palm rejection is automatic via PencilKit — do not interfere with it.
- Both lasso AND rectangle selection must be implemented. No exceptions.
- Three AI backends: Claude, OpenAI, Ollama. User configures in settings.
- Streaming responses only. Never wait for a full response before displaying text.
- No third-party dependencies. Zero. Pure Apple frameworks + URLSession.
- Deployment target: **iPadOS 17.0**
- Language: **Swift 5.9**, **SwiftUI**
- Do not use `@StateObject` or `ObservableObject`. Use `@Observable` (iOS 17 Observation framework) throughout.

---

## Xcode Project Setup

Create a new Xcode project:
- Template: App
- Interface: SwiftUI
- Language: Swift
- Bundle ID: com.smol.smolpad
- Deployment target: iPadOS 17.0
- Device: iPad only

**Info.plist — add these keys:**
```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>SmolPad uses speech recognition so you can ask questions about your notes by voice.</string>
<key>NSMicrophoneUsageDescription</key>
<string>SmolPad uses the microphone for voice queries.</string>
```

**No Swift Package dependencies.** Do not add any packages.

---

## File Structure

```
SmolPad/
├── SmolPadApp.swift
├── State/
│   ├── CanvasState.swift
│   └── AIConfig.swift
├── Views/
│   ├── ContentView.swift
│   ├── CanvasHostView.swift
│   ├── SelectionOverlayView.swift
│   ├── ToolbarView.swift
│   ├── ChatPanelView.swift
│   └── SettingsView.swift
└── Services/
    ├── AIClient.swift
    └── VoiceManager.swift
```

Create groups in Xcode matching these folders. All files go in the SmolPad target.

---

## Design System

### Colors

```swift
// Use these exact values everywhere. Do not use system colors for canvas elements.
let canvasBackground   = Color(red: 0.969, green: 0.965, blue: 0.957)  // #F7F6F4 warm white
let ruleLineColor      = Color(red: 0.0,   green: 0.0,   blue: 0.47, opacity: 0.055) // subtle blue rule
let marginLineColor    = Color(red: 0.86,  green: 0.0,   blue: 0.0, opacity: 0.10)   // faint red margin
let inkColor           = UIColor(red: 0.09, green: 0.09, blue: 0.16, alpha: 1.0)     // near-black ink
let toolbarBackground  = Material.ultraThinMaterial                                    // frosted glass
let accentGold         = Color(red: 0.961, green: 0.651, blue: 0.137) // #F5A623 lasso color
let selectionBlue      = Color.blue                                    // rect selection color
let chatBackground     = Color(red: 0.11, green: 0.11, blue: 0.12)   // #1C1C1E chat panel dark
let chatText           = Color.white
let chatMuted          = Color(white: 0.55)
```

### Typography

Use system fonts throughout. Never specify a custom font.

```swift
.font(.system(size: 15, weight: .regular))   // chat body
.font(.system(size: 13, weight: .regular))   // captions, labels
.font(.system(size: 22, weight: .semibold))  // panel title
.font(.caption)                               // toolbar labels
```

### Spacing & Sizing

```swift
let canvasWidth:  CGFloat = 2048   // canvas content width in points
let canvasHeight: CGFloat = 4096   // canvas content height in points
let ruleSpacing:  CGFloat = 36     // horizontal rule interval
let marginX:      CGFloat = 64     // left margin line x position
let toolbarButtonSize: CGFloat = 44
let toolbarWidth:      CGFloat = 52
let toolbarCornerRadius: CGFloat = 26
let chatPanelHeight: CGFloat = 0.62  // fraction of screen height
let chatCornerRadius: CGFloat = 20
```

### SF Symbols

```swift
// Use exactly these symbol names:
"pencil.tip"          // pen tool
"eraser"              // eraser tool
"lasso"               // lasso select tool
"rectangle.dashed"    // rect select tool
"gear"                // settings
"arrow.up.circle.fill" // send button
"mic.fill"            // voice button (listening)
"mic"                 // voice button (idle)
"xmark"               // close/dismiss
"xmark.circle.fill"   // close chat panel
```

---

## State / CanvasState.swift

```swift
import SwiftUI
import PencilKit
import Observation

enum ActiveTool: Equatable {
    case pen
    case eraser
    case lassoSelect
    case rectSelect

    var isSelection: Bool { self == .lassoSelect || self == .rectSelect }
}

@Observable
final class CanvasState {
    var activeTool: ActiveTool = .pen
    let canvasView = PKCanvasView()
    var scrollOffset: CGPoint = .zero
    var zoomScale: CGFloat = 1.0
    var capturedImage: UIImage? = nil
    var showChat: Bool = false

    // Convert a rect from overlay (screen) coordinates to canvas document coordinates
    func toCanvasRect(_ screenRect: CGRect) -> CGRect {
        CGRect(
            x: (screenRect.minX + scrollOffset.x) / zoomScale,
            y: (screenRect.minY + scrollOffset.y) / zoomScale,
            width: screenRect.width / zoomScale,
            height: screenRect.height / zoomScale
        )
    }

    // Called by SelectionOverlayView after rect drag completes
    func captureRect(_ screenRect: CGRect) {
        guard screenRect.width > 20, screenRect.height > 20 else { return }
        let canvasRect = toCanvasRect(screenRect)
        let image = canvasView.drawing.image(from: canvasRect, scale: 2.0)
        capturedImage = image
        showChat = true
        activeTool = .pen
    }

    // Called by SelectionOverlayView after lasso path completes
    func captureLasso(points: [CGPoint]) {
        guard points.count > 3 else { return }
        let xs = points.map(\.x); let ys = points.map(\.y)
        let rect = CGRect(
            x: xs.min()!, y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
        captureRect(rect)
    }

    func dismissChat() {
        showChat = false
        capturedImage = nil
    }
}
```

---

## State / AIConfig.swift

```swift
import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"
    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-4-6"
        case .openai: return "gpt-4o"
        case .ollama: return "qwen2.5-vl:7b"
        }
    }
}

@Observable
final class AIConfig {
    var provider: AIProvider
    var apiKey: String
    var ollamaURL: String
    var model: String

    // Keys for UserDefaults
    private enum Key: String {
        case provider, apiKey, ollamaURL, model
    }

    init() {
        let d = UserDefaults.standard
        provider = AIProvider(rawValue: d.string(forKey: Key.provider.rawValue) ?? "") ?? .claude
        apiKey   = d.string(forKey: Key.apiKey.rawValue)   ?? ""
        ollamaURL = d.string(forKey: Key.ollamaURL.rawValue) ?? "http://192.168.1.100:11434"
        model    = d.string(forKey: Key.model.rawValue)    ?? AIProvider.claude.defaultModel
    }

    func save() {
        let d = UserDefaults.standard
        d.set(provider.rawValue, forKey: Key.provider.rawValue)
        d.set(apiKey,            forKey: Key.apiKey.rawValue)
        d.set(ollamaURL,         forKey: Key.ollamaURL.rawValue)
        d.set(model,             forKey: Key.model.rawValue)
    }
}
```

---

## Services / AIClient.swift

This file handles streaming API calls for all three providers. Every provider sends a JPEG image (base64-encoded) plus a text prompt.

```swift
import Foundation
import UIKit

enum AIError: LocalizedError {
    case missingConfig
    case badStatus(Int)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .missingConfig:  return "API key or server URL is not configured."
        case .badStatus(let c): return "Server returned HTTP \(c)."
        case .invalidURL:     return "Invalid server URL."
        }
    }
}

struct AIClient {

    /// Returns an AsyncThrowingStream that yields text chunks as they stream in.
    static func send(
        image: UIImage,
        query: String,
        config: AIConfig
    ) async throws -> AsyncThrowingStream<String, Error> {

        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw AIError.missingConfig
        }
        let b64 = jpeg.base64EncodedString()
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Explain what is written or drawn here. If it contains math, solve it and explain every step clearly."
            : query

        let request = try buildRequest(b64: b64, prompt: prompt, config: config)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.badStatus(0)); return
                    }
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: AIError.badStatus(http.statusCode)); return
                    }
                    for try await line in bytes.lines {
                        if let chunk = parseLine(line, provider: config.provider) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request builders

    private static func buildRequest(
        b64: String,
        prompt: String,
        config: AIConfig
    ) throws -> URLRequest {

        let urlString: String
        let headers: [String: String]
        let body: Any

        switch config.provider {

        case .claude:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.anthropic.com/v1/messages"
            headers = [
                "x-api-key": config.apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ]
            body = [
                "model": config.model,
                "max_tokens": 2048,
                "stream": true,
                "messages": [[
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": b64
                            ]
                        ],
                        ["type": "text", "text": prompt]
                    ]
                ]]
            ] as [String: Any]

        case .openai:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.openai.com/v1/chat/completions"
            headers = [
                "Authorization": "Bearer \(config.apiKey)",
                "Content-Type": "application/json"
            ]
            body = [
                "model": config.model,
                "stream": true,
                "messages": [[
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                        ],
                        ["type": "text", "text": prompt]
                    ]
                ]]
            ] as [String: Any]

        case .ollama:
            urlString = "\(config.ollamaURL)/api/chat"
            headers = ["Content-Type": "application/json"]
            body = [
                "model": config.model,
                "stream": true,
                "messages": [[
                    "role": "user",
                    "content": prompt,
                    "images": [b64]
                ]]
            ] as [String: Any]
        }

        guard let url = URL(string: urlString) else { throw AIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    // MARK: - Stream parsers

    private static func parseLine(_ line: String, provider: AIProvider) -> String? {
        switch provider {

        case .claude:
            // Lines look like: data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"chunk"}}
            guard line.hasPrefix("data: "),
                  let data = line.dropFirst(6).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String
            else { return nil }
            return text

        case .openai:
            // Lines look like: data: {"choices":[{"delta":{"content":"chunk"}}]}
            guard line.hasPrefix("data: "),
                  !line.hasPrefix("data: [DONE]"),
                  let data = line.dropFirst(6).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String
            else { return nil }
            return text

        case .ollama:
            // Each line is a JSON object: {"message":{"content":"chunk"},"done":false}
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { return nil }
            return text
        }
    }
}
```

---

## Services / VoiceManager.swift

Uses `SFSpeechRecognizer` + `AVAudioEngine`. Real-time partial results. Hold-to-dictate UX (start on press, stop on release, return transcript).

```swift
import Speech
import AVFoundation
import Observation

@Observable
final class VoiceManager: NSObject {
    var transcript: String = ""
    var isListening: Bool = false
    var error: String? = nil

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func start() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition not authorized. Enable in Settings."; return
        }
        guard !engine.isRunning else { return }
        error = nil
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            let inputNode = engine.inputNode
            let fmt = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                self?.request?.append(buf)
            }

            engine.prepare()
            try engine.start()

            task = recognizer?.recognitionTask(with: req) { [weak self] result, err in
                guard let self else { return }
                if let r = result {
                    self.transcript = r.bestTranscription.formattedString
                }
                if err != nil || (result?.isFinal ?? false) {
                    self.stopEngine()
                }
            }
            isListening = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() -> String {
        let result = transcript
        stopEngine()
        return result
    }

    private func stopEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
```

---

## Views / CanvasHostView.swift

UIViewRepresentable wrapping a UIScrollView containing PKCanvasView. The canvas is `canvasWidth × canvasHeight` points (2048 × 4096). Reports scroll offset and zoom scale back to CanvasState.

```swift
import SwiftUI
import PencilKit

struct CanvasHostView: UIViewRepresentable {
    var state: CanvasState

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.5
        scroll.maximumZoomScale = 3.0
        scroll.zoomScale = 1.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.bouncesZoom = true

        let canvas = state.canvasView
        canvas.frame = CGRect(x: 0, y: 0, width: 2048, height: 4096)
        canvas.backgroundColor = .clear   // background drawn in SwiftUI layer below
        canvas.drawingPolicy = .anyInput  // accepts finger and Pencil
        canvas.tool = PKInkingTool(.pen, color: UIColor(red: 0.09, green: 0.09, blue: 0.16, alpha: 1.0), width: 2)
        canvas.isRulerActive = false

        scroll.contentSize = canvas.frame.size
        scroll.addSubview(canvas)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let canvas = state.canvasView

        // In selection mode: freeze scroll and disable canvas interaction
        // so the SwiftUI overlay gesture can capture all touches cleanly.
        scroll.isScrollEnabled  = !state.activeTool.isSelection
        scroll.isUserInteractionEnabled = !state.activeTool.isSelection

        // Sync tool
        switch state.activeTool {
        case .pen:
            canvas.tool = PKInkingTool(
                .pen,
                color: UIColor(red: 0.09, green: 0.09, blue: 0.16, alpha: 1.0),
                width: 2
            )
        case .eraser:
            canvas.tool = PKEraserTool(.bitmap)
        case .lassoSelect, .rectSelect:
            break   // canvas tool irrelevant during selection; overlay handles input
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let state: CanvasState
        init(state: CanvasState) { self.state = state }

        func scrollViewDidScroll(_ s: UIScrollView) {
            state.scrollOffset = s.contentOffset
        }

        func scrollViewDidZoom(_ s: UIScrollView) {
            state.zoomScale = s.zoomScale
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return state.canvasView
        }
    }
}
```

---

## Views / SelectionOverlayView.swift

A full-screen transparent SwiftUI view. Drawn on top of CanvasHostView only when `state.activeTool.isSelection`. Handles both lasso and rect gestures depending on `state.activeTool`.

**Lasso mode:** tracks all touch points into `[CGPoint]` using `DragGesture`, draws the path with gold stroke, closes and captures bounding rect on release.

**Rect mode:** tracks start and current drag location, draws a dashed blue rectangle, captures on release.

Both paths show a semi-transparent fill overlay while drawing.

```swift
import SwiftUI

struct SelectionOverlayView: View {
    var state: CanvasState

    // Lasso state
    @State private var lassoPoints: [CGPoint] = []

    // Rect state
    @State private var rectStart: CGPoint?  = nil
    @State private var rectEnd:   CGPoint?  = nil

    var body: some View {
        ZStack {
            // Semi-transparent scrim so user knows they're in selection mode
            Color.black.opacity(0.04)

            Canvas { ctx, _ in
                switch state.activeTool {
                case .lassoSelect:
                    drawLasso(ctx: ctx)
                case .rectSelect:
                    drawRect(ctx: ctx)
                default:
                    break
                }
            }
        }
        .contentShape(Rectangle())   // makes entire area tappable / draggable
        .gesture(activeGesture)
        .ignoresSafeArea()
    }

    // MARK: - Drawing

    private func drawLasso(ctx: GraphicsContext) {
        guard lassoPoints.count > 1 else { return }
        var path = Path()
        path.move(to: lassoPoints[0])
        for pt in lassoPoints.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()

        ctx.fill(path, with: .color(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.12)))
        ctx.stroke(path, with: .color(Color(red: 0.961, green: 0.651, blue: 0.137)),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func drawRect(ctx: GraphicsContext) {
        guard let s = rectStart, let e = rectEnd else { return }
        let rect = CGRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )
        let path = Path(rect)
        ctx.fill(path, with: .color(Color.blue.opacity(0.08)))
        ctx.stroke(path, with: .color(Color.blue),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }

    // MARK: - Gestures

    @ViewBuilder
    private var activeGesture: some Gesture {
        switch state.activeTool {
        case .lassoSelect: AnyGesture(lassoGesture.map { _ in () })
        case .rectSelect:  AnyGesture(rectGesture.map  { _ in () })
        default:           AnyGesture(DragGesture().map { _ in () })
        }
    }

    // Tracks every point along the drag to build a freehand path
    private var lassoGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if lassoPoints.isEmpty { lassoPoints.append(v.startLocation) }
                lassoPoints.append(v.location)
            }
            .onEnded { _ in
                state.captureLasso(points: lassoPoints)
                lassoPoints = []
            }
    }

    // Tracks start + end corner for rectangle
    private var rectGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                if rectStart == nil { rectStart = v.startLocation }
                rectEnd = v.location
            }
            .onEnded { v in
                if let s = rectStart, let e = rectEnd {
                    let rect = CGRect(
                        x: min(s.x, e.x), y: min(s.y, e.y),
                        width: abs(e.x - s.x), height: abs(e.y - s.y)
                    )
                    state.captureRect(rect)
                }
                rectStart = nil
                rectEnd   = nil
            }
    }
}
```

---

## Views / ToolbarView.swift

Vertical pill on the right edge. Contains exactly 5 buttons: pen, eraser, lasso, rect, settings. Each button is 44pt circle. Active tool highlighted in accentGold. Background is `.ultraThinMaterial` with a subtle border. Width 52pt, corner radius 26pt.

Do not add any more buttons. Do not add labels. Icons only.

```swift
import SwiftUI

struct ToolbarView: View {
    var state: CanvasState
    @Binding var showSettings: Bool

    private let tools: [(ActiveTool, String)] = [
        (.pen,        "pencil.tip"),
        (.eraser,     "eraser"),
        (.lassoSelect,"lasso"),
        (.rectSelect, "rectangle.dashed"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tools, id: \.1) { tool, icon in
                toolButton(tool: tool, icon: icon)
            }

            Divider()
                .frame(width: 28)
                .padding(.vertical, 2)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 52)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(Color(white: 0.0, opacity: 0.08), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func toolButton(tool: ActiveTool, icon: String) -> some View {
        let isActive = state.activeTool == tool
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.activeTool = (state.activeTool == tool && !tool.isSelection) ? tool : tool
            }
        } label: {
            ZStack {
                if isActive {
                    Circle()
                        .fill(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.18))
                        .frame(width: 38, height: 38)
                }
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(
                        isActive
                            ? Color(red: 0.961, green: 0.651, blue: 0.137)
                            : Color(white: 0.35)
                    )
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}
```

---

## Views / ChatPanelView.swift

Slides up from bottom. Height = 62% of screen height. Dark background (#1C1C1E). Contains:

1. **Top bar:** small drag handle + "Ask AI" label + close button (xmark.circle.fill)
2. **Image thumbnail:** the captured region, max height 140pt, rounded corners 8pt, shown at top of panel
3. **Response area:** ScrollView, streaming text renders here character by character
4. **Input row at bottom:** text field ("Ask about this...") + voice mic button + send button

Voice button behavior:
- Tap to start → `voiceManager.start()` → mic.fill icon, pulsing red
- Tap again to stop → `voiceManager.stop()` → returns transcript, fills query field
- After stopping, do NOT auto-send. User reviews and taps send.

Send button behavior:
- Tap → clear `response` → call `AIClient.send()` → stream chunks into `response`
- Disable send button while streaming (show a spinner inside the button instead)
- On error: show error text in response area in red

Auto-scroll: as response grows, scroll to bottom automatically using `scrollViewProxy.scrollTo("bottom")` with animation.

```swift
import SwiftUI

struct ChatPanelView: View {
    var state: CanvasState
    var config: AIConfig
    var voiceManager: VoiceManager

    @State private var query: String = ""
    @State private var response: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamError: String? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(white: 1.0, opacity: 0.3))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    // Header
                    HStack {
                        Text("Ask AI")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { state.dismissChat() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(white: 1, opacity: 0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    // Captured image thumbnail
                    if let img = state.capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(white: 1, opacity: 0.15), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }

                    // Response scroll area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if let err = streamError {
                                    Text(err)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.red.opacity(0.85))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                } else if !response.isEmpty {
                                    Text(response)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .textSelection(.enabled)
                                } else if !isStreaming {
                                    Text("Your answer will appear here.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(white: 0.45))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: response) { _, _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                        .onAppear { scrollProxy = proxy }
                    }

                    Divider().background(Color(white: 1, opacity: 0.1))

                    // Input row
                    HStack(spacing: 10) {
                        TextField("Ask about this...", text: $query)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(white: 1, opacity: 0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onChange(of: voiceManager.transcript) { _, t in
                                if !t.isEmpty { query = t }
                            }

                        // Voice button
                        Button {
                            if voiceManager.isListening {
                                query = voiceManager.stop()
                            } else {
                                voiceManager.start()
                            }
                        } label: {
                            Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    voiceManager.isListening
                                        ? Color.red
                                        : Color(white: 0.55)
                                )
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)

                        // Send button
                        Button { sendQuery() } label: {
                            if isStreaming {
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 38, height: 38)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(
                                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color(white: 0.35)
                                            : Color(red: 0.961, green: 0.651, blue: 0.137)
                                    )
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isStreaming)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 12)
                }
                .frame(height: geo.size.height * 0.62)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { voiceManager.requestPermission() }
    }

    private func sendQuery() {
        guard let image = state.capturedImage else { return }
        guard !isStreaming else { return }
        response = ""
        streamError = nil
        isStreaming = true

        Task {
            do {
                let stream = try await AIClient.send(image: image, query: query, config: config)
                for try await chunk in stream {
                    await MainActor.run { response += chunk }
                }
            } catch {
                await MainActor.run { streamError = error.localizedDescription }
            }
            await MainActor.run { isStreaming = false }
        }
    }
}
```

---

## Views / SettingsView.swift

Sheet presentation. Allows user to switch AI provider, enter API key, enter Ollama URL, and enter model name. Shows which model is being used. Saves on dismiss.

```swift
import SwiftUI

struct SettingsView: View {
    var config: AIConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Provider") {
                    Picker("Provider", selection: Bindable(config).provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: config.provider) { _, p in
                        config.model = p.defaultModel
                    }
                }

                switch config.provider {
                case .claude, .openai:
                    Section("API Key") {
                        SecureField("Paste your API key", text: Bindable(config).apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                case .ollama:
                    Section("Ollama Server") {
                        TextField("http://192.168.1.100:11434", text: Bindable(config).ollamaURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                }

                Section("Model") {
                    TextField("Model name", text: Bindable(config).model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text(modelHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    // empty — just for spacing
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
        case .claude: return "e.g. claude-opus-4-6, claude-sonnet-4-6"
        case .openai: return "e.g. gpt-4o, gpt-4o-mini"
        case .ollama: return "e.g. qwen2.5-vl:7b, llava:13b"
        }
    }
}
```

---

## Views / ContentView.swift

Root view. Composes everything together. The ZStack layer order from bottom to top is:
1. Canvas background color
2. Lined paper Canvas drawing
3. CanvasHostView (PKCanvasView)
4. SelectionOverlayView (conditional — only when isSelection)
5. ToolbarView (pinned bottom-right)
6. ChatPanelView (conditional — slides up from bottom)

```swift
import SwiftUI

struct ContentView: View {
    @State private var canvasState   = CanvasState()
    @State private var aiConfig      = AIConfig()
    @State private var voiceManager  = VoiceManager()
    @State private var showSettings  = false

    var body: some View {
        ZStack {
            // 1. Background paper color
            Color(red: 0.969, green: 0.965, blue: 0.957)
                .ignoresSafeArea()

            // 2. Lined paper texture
            GeometryReader { geo in
                Canvas { ctx, size in
                    // Horizontal rules every 36pt
                    var y: CGFloat = 36
                    while y < size.height {
                        var rule = Path()
                        rule.move(to:    CGPoint(x: 20,          y: y))
                        rule.addLine(to: CGPoint(x: size.width - 20, y: y))
                        ctx.stroke(
                            rule,
                            with: .color(Color(red: 0, green: 0, blue: 0.47, opacity: 0.055)),
                            lineWidth: 0.5
                        )
                        y += 36
                    }
                    // Left margin line
                    var margin = Path()
                    margin.move(to:    CGPoint(x: 64, y: 0))
                    margin.addLine(to: CGPoint(x: 64, y: size.height))
                    ctx.stroke(
                        margin,
                        with: .color(Color(red: 0.86, green: 0, blue: 0, opacity: 0.10)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
            }

            // 3. PencilKit canvas
            CanvasHostView(state: canvasState)
                .ignoresSafeArea()

            // 4. Selection overlay (only in selection mode)
            if canvasState.activeTool.isSelection {
                SelectionOverlayView(state: canvasState)
            }

            // 5. Toolbar pinned to bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ToolbarView(state: canvasState, showSettings: $showSettings)
                        .padding(.trailing, 20)
                        .padding(.bottom, 36)
                }
            }

            // 6. Chat panel slides in from bottom
            if canvasState.showChat {
                ChatPanelView(
                    state: canvasState,
                    config: aiConfig,
                    voiceManager: voiceManager
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: canvasState.showChat)
        .animation(.easeInOut(duration: 0.15), value: canvasState.activeTool)
        .sheet(isPresented: $showSettings) {
            SettingsView(config: aiConfig)
        }
    }
}
```

---

## Data Flow Summary

```
User writes with Pencil
    → PKCanvasView captures ink strokes
    → stored in canvasView.drawing

User taps lasso / rect button in toolbar
    → state.activeTool = .lassoSelect / .rectSelect
    → CanvasHostView disables scroll + interaction on scrollView
    → SelectionOverlayView appears (allowsHitTesting = true)
    → overlay Canvas draws live lasso path / dashed rect during drag

User lifts finger / Pencil
    → SelectionOverlayView.gesture.onEnded fires
    → Calls state.captureLasso(points:) or state.captureRect(_:)
    → CanvasState converts screen coords → canvas coords
    → canvasView.drawing.image(from: canvasRect, scale: 2.0) → UIImage
    → state.capturedImage = image, state.showChat = true
    → state.activeTool resets to .pen

ChatPanelView animates up
    → Shows thumbnail of captured image
    → User types query OR holds mic button to dictate
    → Taps send → AIClient.send(image:query:config:)
    → AsyncThrowingStream yields text chunks
    → response string grows character by character
    → ScrollView auto-scrolls to bottom
```

---

## Edge Cases to Handle

1. **Selection too small:** In `captureRect`, guard `width > 20 && height > 20`. Show nothing and reset tool silently.
2. **Empty canvas selection:** `PKDrawing.image(from:scale:)` on an empty rect returns a white image — that is fine, send it, the AI will say "nothing visible."
3. **API key missing:** `AIClient.send` throws `AIError.missingConfig`. ChatPanelView catches it and displays the error string in red in the response area.
4. **Ollama unreachable:** URLSession will throw a connection error. Caught and displayed in response area.
5. **Voice not authorized:** VoiceManager sets `error` string. ChatPanelView does not display this error automatically — just leave the query field empty and let user type.
6. **Chat panel + keyboard:** The text field in ChatPanelView will push the keyboard up. Wrap the panel in an appropriate padding or use `.ignoresSafeArea(.keyboard, edges: .bottom)` only if the panel layout breaks.
7. **Dismiss mid-stream:** If user taps close (xmark) while streaming, `state.dismissChat()` is called. The Task is not cancelled — this is acceptable for v1.
8. **Rotation:** The app is iPad landscape/portrait. PencilKit handles both natively. The canvas is always 2048×4096 and the scroll view recenters on rotation automatically.

---

## What NOT to build (out of scope for v1)

- Multiple notebooks or file management
- Export to PDF
- Undo/redo toolbar buttons (PencilKit provides two-finger undo natively — do not add buttons)
- Typed text insertion
- Image import
- Collaboration or sync
- Tool picker (PKToolPicker) — toolbar is custom and sufficient
- Color picker
- Pen width slider
- Dark mode for the canvas (canvas is always light paper)
- Local on-device models

---

## Build & Run Checklist

1. Create Xcode project with the settings above
2. Create the folder groups: State/, Views/, Services/
3. Create all Swift files with the exact code above
4. Add Info.plist keys for speech and microphone
5. Connect iPad, select it as run destination
6. Build (⌘B) — must compile with zero errors and zero warnings
7. Run (⌘R) — open Settings, paste Claude API key, model = claude-opus-4-6
8. Write something with Pencil, tap lasso icon, draw around it, check panel opens
9. Type a question, tap send, verify streaming response

The app is complete when: writing feels smooth, both selection modes work, panel opens, and AI responds in streaming text.