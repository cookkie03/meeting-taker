# MeetingTaker

**Professional-grade, on-device transcription for macOS.**

Real-time speech-to-text with speaker diarization. Captures **microphone**, **system audio**, or **both**. 100% local, zero external dependencies, your data never leaves your machine.

## Audio Sources

MeetingTaker can capture audio from three sources:

| Source | What it captures | How |
|--------|-----------------|-----|
| **Microphone** | Your voice via built-in or external mic | `AVAudioEngine` input node |
| **System Audio** | Everything your Mac plays — Zoom, Meet, YouTube, Spotify, calls | `ScreenCaptureKit` (no virtual audio drivers needed) |
| **Both** | Microphone + System Audio mixed into one track | Both engines combined |

### System Audio Capture

MeetingTaker uses Apple's **ScreenCaptureKit** (`SCStream`) to capture system audio directly. This means:

- **No BlackHole, no Soundflower, no virtual audio drivers needed**
- **No MIDI setup, no multi-output device configuration**
- Works on macOS 12.3+ with Apple Silicon
- Requires **Screen Recording permission** on first use (macOS will prompt)
- Only audio is captured, never screen content

### Permissions

On first launch, MeetingTaker may ask for:

1. **Microphone** — to capture your voice (required for mic/both modes)
2. **Screen Recording** — to capture system audio (required for system/both modes)

Grant both in **System Settings > Privacy & Security**. After granting Screen Recording, restart the app (macOS requirement).

## Features

- **Real-time transcription** — Watch text appear as people talk
- **Speaker diarization** — Automatically labels who spoke when ("Speaker 0", "Speaker 1", …)
- **Multilingual** — 100+ languages via WhisperKit (EN, IT, ES, FR, DE, PT, JA, ZH, KO, RU, AR, HI, …)
- **Multiple export formats** — TXT, JSON, SRT, WebVTT, CSV, RTTM
- **Local API server** — OpenAI-compatible REST API for scripting/integration
- **CLI tool** — Full-featured command-line interface (`mtaker`)
- **SwiftUI interface** — Native macOS app with live audio level meter
- **Apple Silicon optimized** — Leverages CoreML and Neural Engine

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1/M2/M3/M4) — Intel supported but slower
- Xcode 16.0+ (for building from source)
- ~2GB disk space for models

## Quick Start

```bash
git clone https://github.com/cookkie03/meeting-taker.git
cd meeting-taker
./setup.sh
```

This will:
1. Install dependencies (Homebrew, git-lfs, huggingface-cli)
2. Download WhisperKit model (~626MB, recommended `large-v3-v20240930_626MB`)
3. Download SpeakerKit models for diarization
4. Build the app + CLI
5. Install `mtaker` to `/usr/local/bin`

## Usage

### GUI App

```bash
open MeetingTaker.app
```

1. Choose your audio source: **Microphone**, **System Audio**, or **Both**
2. Select model and language
3. Click **Record**
4. Watch the transcription appear in real-time
5. Export to TXT/JSON/SRT/VTT/CSV/RTTM

### CLI

```bash
# Transcribe a file
mtaker transcribe audio.wav

# With speaker diarization
mtaker transcribe meeting.wav --diarize

# Specify language
mtaker transcribe audio.wav --language it

# Export as SRT subtitles
mtaker transcribe audio.wav -f srt -o subtitles.srt

# Export as JSON
mtaker transcribe audio.wav -f json -o result.json

# Diarize only (who spoke when)
mtaker diarize meeting.wav

# List available models
mtaker models

# Start API server
mtaker serve --port 50060
```

### API Server

```bash
# Start the server
mtaker serve --port 50060

# Transcribe via API
curl -X POST http://localhost:50060/v1/audio/transcriptions \
  -F file=@audio.wav \
  -F model=large-v3-v20240930_626MB

# With speaker diarization
curl -X POST http://localhost:50060/v1/audio/transcriptions \
  -F file=@meeting.wav \
  -F diarize=true
```

Compatible with any OpenAI SDK — just change the base URL:

```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:50060/v1")
result = client.audio.transcriptions.create(
    file=open("audio.wav", "rb"),
    model="large-v3-v20240930_626MB"
)
print(result.text)
```

## Models

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| `tiny` | ~75MB | Fastest | Low | Debugging |
| `base` | ~140MB | Fast | Medium | Quick tests |
| `small` | ~250MB | Medium | Good | Balanced |
| `large-v3-v20240930_626MB` | ~626MB | Slower | **Best** | **Recommended** |

Switch models with `--model` flag or in the app's model picker.

## Export Formats

| Format | Description |
|--------|-------------|
| `txt` | Plain text with timestamps and speaker labels |
| `json` | Full structured data (segments, metadata) |
| `srt` | SubRip subtitles |
| `vtt` | WebVTT subtitles |
| `csv` | Spreadsheet-compatible |
| `rttm` | Rich Transcription Time Marked (diarization) |

## Auto-Detect Calls

MeetingTaker can **automatically detect when you're in a call** and optionally start/stop recording. No manual intervention needed.

### How It Works

The `CallDetectionEngine` uses multiple signals to detect active meetings:

| Signal | What it checks | Confidence |
|--------|---------------|------------|
| **Process Detection** | Known meeting apps running (`CptHost` for Zoom, `FaceTime`, `Tuple`, `Webex`, etc.) | High |
| **CoreAudio Per-Process Mic Check** | Which specific PIDs are capturing audio input (macOS 14+) | High |
| **Browser Tab Detection** | Chrome/Safari tabs with meeting URLs (`meet.google.com`, `teams.microsoft.com`, `zoom.us/j/`, etc.) | Medium |
| **Mic Activity** | Any process using the microphone (catches unknown apps) | Low |

### Supported Apps

**Native apps:**
- Zoom (`CptHost` process)
- FaceTime
- Microsoft Teams
- Slack Huddle
- Webex
- Discord
- Around
- Tuple
- Loom

**Browser-based:**
- Google Meet (Chrome/Safari)
- Microsoft Teams Web (Chrome/Safari)
- Zoom Web (Chrome/Safari)
- Slack Huddle Web (Chrome/Safari)

### Auto-Record

Enable **Auto-Record** in the app or CLI to automatically:

1. **Detect** when a call starts (5s warmup to avoid false positives)
2. **Start recording** automatically
3. **Detect** when the call ends (5s grace period)
4. **Stop recording** and transcribe

```
State machine:
  idle ──(mic active 5s)──► warming ──(confirmed)──► recording
                                                              │
  idle ◄──(mic idle 5s)─── cooling ◄──(mic stopped)─────────┘
```

### CLI Usage

```bash
# Watch for calls and auto-transcribe
mtaker watch

# Watch with specific source
mtaker watch --source system-audio

# Watch with diarization
mtaker watch --diarize
```

### Privacy

Call detection is **100% local**:
- No network calls to detect apps
- No screen content captured (audio only)
- No data about your calls leaves the Mac
- Process names checked locally via `NSRunningApplication`
- Browser tabs checked via local AppleScript (no browser extensions)

```
MeetingTaker/
├── Sources/
│   ├── MeetingTakerKit/          # Core library
│   │   ├── Audio/                # AudioCaptureManager (mic + system via ScreenCaptureKit)
│   │   ├── Transcription/        # WhisperKit engine wrapper
│   │   ├── Diarization/          # SpeakerKit engine wrapper
│   │   └── Export/               # Multi-format export engine
│   ├── MeetingTaker/             # SwiftUI App
│   │   ├── App/                  # Entry point & global state
│   │   ├── UI/                   # Views (Transcription, History, Settings)
│   │   └── Server/               # Vapor local server (OpenAI API)
│   └── MeetingTakerCLI/          # CLI tool (mtaker)
├── Models/                       # Downloaded ML models (git-lfs)
├── setup.sh                      # One-click setup
└── Package.swift                 # Swift Package Manager
```

## How System Audio Capture Works

```
┌─────────────────────────────────────────────────────┐
│                    macOS                             │
│                                                      │
│  Zoom/Meet/YouTube ──► System Audio Output           │
│                              │                       │
│                    ┌─────────▼──────────┐            │
│                    │ ScreenCaptureKit   │            │
│                    │ SCStream           │            │
│                    │ (audio only)       │            │
│                    └─────────┬──────────┘            │
│                              │                       │
│                    ┌─────────▼──────────┐            │
│                    │ 16kHz mono float32 │            │
│                    │ PCM buffer         │            │
│                    └─────────┬──────────┘            │
│                              │                       │
│  Microphone ──── AVAudioEngine input tap             │
│                              │                       │
│                    ┌─────────▼──────────┐            │
│                    │ WhisperKit         │            │
│                    │ CoreML / ANE       │            │
│                    └─────────┬──────────┘            │
│                              │                       │
│                    ┌─────────▼──────────┐            │
│                    │ TranscriptionResult│            │
│                    │ + SpeakerKit       │            │
│                    └────────────────────┘            │
└─────────────────────────────────────────────────────┘

Everything stays on-device. Zero network calls.
```

## Privacy

- **100% on-device** — No network calls, no cloud, no telemetry
- **No audio leaves your Mac** — All processing uses CoreML on Apple Silicon
- **No accounts** — No signup, no API keys, no tracking
- **No virtual audio drivers** — Uses native ScreenCaptureKit, not BlackHole/Soundflower
- **Open source** — Audit everything

## Tech Stack

| Component | Technology |
|-----------|------------|
| Speech-to-Text | [WhisperKit](https://github.com/argmaxinc/WhisperKit) — on-device Whisper via CoreML |
| Speaker Diarization | [SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift) — Pyannote on-device |
| System Audio | `ScreenCaptureKit` — native macOS 12.3+ |
| Microphone | `AVAudioEngine` — native macOS |
| UI | `SwiftUI` — native macOS |
| API Server | `Vapor` — OpenAI-compatible |
| Storage | `SwiftData` + SQLite |
| Models | CoreML, Apple Neural Engine |

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax, Inc.
- [SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax, Inc.
- [OpenAI Whisper](https://github.com/openai/whisper)
- [Pyannote](https://github.com/pyannote/pyannote-audio)
- [Parrot](https://github.com/turantekin/Parrot) — inspiration for ScreenCaptureKit audio capture
- [trnscrb](https://github.com/ajayrmk/trnscrb) — inspiration for local-first transcription

## License

MIT License — See [LICENSE](LICENSE) for details.
