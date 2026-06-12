# MeetingTaker

**Professional-grade, on-device transcription for macOS.**

Real-time speech-to-text with speaker diarization, powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) and [SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift). 100% local, zero external dependencies, your data never leaves your machine.

## Features

- **Real-time transcription** — Capture from microphone with live results
- **Speaker diarization** — Automatically identify who spoke when
- **Multilingual** — Supports 100+ languages via WhisperKit
- **Multiple export formats** — TXT, JSON, SRT, WebVTT, CSV, RTTM
- **Local API server** — OpenAI-compatible REST API for integration
- **CLI tool** — Full-featured command-line interface
- **SwiftUI interface** — Native macOS app with beautiful design
- **Apple Silicon optimized** — Leverages CoreML and Neural Engine

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1/M2/M3/M4) — Intel supported but slower
- Xcode 16.0+
- ~2GB disk space for models

## Quick Start

### One-Line Setup

```bash
git clone https://github.com/cookkie03/meeting-taker.git
cd meeting-taker
./setup.sh
```

This will:
1. Install dependencies (Homebrew, git-lfs, huggingface-cli)
2. Download the recommended WhisperKit model (~626MB)
3. Download SpeakerKit models for diarization
4. Build the app and CLI
5. Install `mtaker` to `/usr/local/bin`

### Manual Setup

```bash
# Clone
git clone https://github.com/cookkie03/meeting-taker.git
cd meeting-taker

# Download models
make download-model MODEL=large-v3-v20240930_626MB
make download-speakerkit-models

# Build
swift build -c release --product meeting-taker
swift build -c release --product mtaker
```

## Usage

### GUI App

```bash
open MeetingTaker.app
```

Click **Record** to capture from microphone, or **Open File** to transcribe an audio file.

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

The server implements the [OpenAI Audio API](https://platform.openai.com/docs/api-reference/audio) specification, so you can use any OpenAI SDK:

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
| `rttM` | Rich Transcription Time Marked (diarization) |

## Architecture

```
MeetingTaker/
├── Sources/
│   ├── MeetingTakerKit/          # Core library
│   │   ├── Audio/                # Audio recording & file I/O
│   │   ├── Transcription/        # WhisperKit engine
│   │   ├── Diarization/          # SpeakerKit engine
│   │   └── Export/               # Multi-format export
│   ├── MeetingTaker/             # SwiftUI App
│   │   ├── App/                  # App entry point & state
│   │   ├── UI/                   # SwiftUI views
│   │   └── Server/               # Vapor local server
│   └── MeetingTakerCLI/          # CLI tool
├── Models/                       # Downloaded ML models
├── setup.sh                      # One-click setup
└── Package.swift                 # Swift Package Manager
```

## Privacy

- **100% on-device** — No network calls, no cloud, no telemetry
- **No data leaves your machine** — All processing uses CoreML on Apple Silicon
- **No accounts required** — No signup, no API keys, no tracking

## License

MIT License — See [LICENSE](LICENSE) for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax, Inc.
- [SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax, Inc.
- [OpenAI Whisper](https://github.com/openai/whisper)
- [Pyannote](https://github.com/pyannote/pyannote-audio)
