# Speech Architecture

## Recommended Production Path

SmolPad should use a layered speech stack:

1. `WhisperKit` as the primary on-device ASR runtime.
2. `Apple Speech` as the fallback runtime when WhisperKit is unavailable.
3. `sherpa-onnx` as a later production enhancement for VAD, endpointing, punctuation, and robustness tooling.

## Runtime Choice

For general dictation on iPad:

- Primary model family: Whisper large-v3 / large-v3-turbo through WhisperKit
- Backend selection policy: `Automatic`
- `Automatic` behavior:
  - prefer WhisperKit when linked and available
  - fall back to Apple Speech otherwise

## Why This Split

- WhisperKit gives us an Apple-friendly open-source on-device ASR path.
- Apple Speech remains useful as an operational fallback.
- sherpa-onnx is best treated as a complementary speech pipeline layer rather than the main transcription engine for this app.

## Current Repo State

- `VoiceManager` is now a provider orchestrator.
- `AppleSpeechRecognitionProvider` is the active working backend.
- `WhisperKitSpeechRecognitionProvider` is wired for file-based recording plus WhisperKit transcription.
- WhisperKit now uses a VAD gate before transcription, with a named swap-in seam for sherpa-onnx.
- The Xcode project now references the WhisperKit package.

## Next Integration Step

Harden the WhisperKit path further with:

- model download / readiness UX
- richer progress / processing state in the chat composer
- stronger sherpa-onnx-backed VAD once that runtime is linked into the build
- graceful automatic fallback to Apple Speech on runtime failure

After that, add sherpa-onnx-based VAD and endpointing ahead of transcription if the product needs stronger noisy-environment behavior.
