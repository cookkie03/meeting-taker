#!/bin/bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  MeetingTaker Setup Script                                  ║
# ║  Professional-grade, on-device transcription for macOS      ║
# ╚══════════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$REPO_DIR/Models"
WHISPER_MODEL_REPO="argmaxinc/whisperkit-coreml"
SPEAKER_MODEL_REPO="argmaxinc/speakerkit-coreml"

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BOLD}━━━ $1 ━━━${NC}\n"; }

# ─── Check Prerequisites ───────────────────────────────────────

log_step "Checking prerequisites"

if [[ "$(uname)" != "Darwin" ]]; then
    log_error "MeetingTaker requires macOS"
    exit 1
fi
log_ok "macOS: $(sw_vers -productVersion)"

if [[ "$(uname -m)" != "arm64" ]]; then
    log_warn "Intel Mac detected. Apple Silicon recommended for best performance."
else
    log_ok "Apple Silicon detected"
fi

if ! command -v xcodebuild &>/dev/null; then
    log_error "Xcode required. Install from App Store, then run:"
    echo "  xcode-select --install"
    echo "  sudo xcodebuild -license accept"
    exit 1
fi
log_ok "Xcode: $(xcodebuild -version | head -1)"

if ! command -v swift &>/dev/null; then
    log_error "Swift required. Run: xcode-select --install"
    exit 1
fi
log_ok "Swift: $(swift --version | head -1)"

if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
log_ok "Homebrew installed"

if ! command -v git-lfs &>/dev/null; then
    log_info "Installing git-lfs..."
    brew install git-lfs
fi
git lfs install 2>/dev/null || true
log_ok "git-lfs installed"

if ! command -v huggingface-cli &>/dev/null; then
    log_info "Installing huggingface-cli..."
    brew install huggingface-cli
fi
log_ok "huggingface-cli installed"

# ─── Parse Arguments ────────────────────────────────────────────

MODEL="large-v3-v20240930_626MB"
SKIP_MODELS=false
BUILD_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)       MODEL="$2"; shift 2 ;;
        --skip-models) SKIP_MODELS=true; shift ;;
        --build-only)  BUILD_ONLY=true; shift ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --model MODEL       Model (default: large-v3-v20240930_626MB)"
            echo "  --skip-models       Skip model download"
            echo "  --build-only        Build only, skip everything else"
            echo "  --help              Show this help"
            echo ""
            echo "Models: tiny, base, small, large-v3-v20240930_626MB"
            exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Download Models ────────────────────────────────────────────

if [[ "$SKIP_MODELS" == false && "$BUILD_ONLY" == false ]]; then
    log_step "Downloading models"

    mkdir -p "$MODELS_DIR"

    # WhisperKit model repo
    log_info "Setting up WhisperKit model repository..."
    WHISPER_DIR="$MODELS_DIR/whisperkit-coreml"
    if [[ -d "$WHISPER_DIR/.git" ]]; then
        log_info "Updating existing repository..."
        cd "$WHISPER_DIR"
        GIT_LFS_SKIP_SMUDGE=1 git fetch --all 2>/dev/null
        git reset --hard origin/main 2>/dev/null
    else
        log_info "Cloning from HuggingFace (this may take a while)..."
        GIT_LFS_SKIP_SMUDGE=1 git clone "https://huggingface.co/$WHISPER_MODEL_REPO" "$WHISPER_DIR"
    fi

    log_info "Downloading model: $MODEL (~626MB)..."
    cd "$WHISPER_DIR"
    git lfs fetch --include="openai_whisper-$MODEL/*" 2>/dev/null
    git lfs checkout 2>/dev/null
    log_ok "WhisperKit model ready: $MODEL"

    # SpeakerKit model repo
    log_info "Setting up SpeakerKit model repository..."
    SPEAKER_DIR="$MODELS_DIR/speakerkit-coreml"
    if [[ -d "$SPEAKER_DIR/.git" ]]; then
        log_info "Updating existing repository..."
        cd "$SPEAKER_DIR"
        GIT_LFS_SKIP_SMUDGE=1 git fetch --all 2>/dev/null
        git reset --hard origin/main 2>/dev/null
    else
        log_info "Cloning from HuggingFace..."
        GIT_LFS_SKIP_SMUDGE=1 git clone "https://huggingface.co/$SPEAKER_MODEL_REPO" "$SPEAKER_DIR"
    fi

    log_info "Downloading SpeakerKit models..."
    cd "$SPEAKER_DIR"
    git lfs fetch --include="speaker_segmenter/**" 2>/dev/null
    git lfs fetch --include="speaker_embedder/**" 2>/dev/null
    git lfs fetch --include="speaker_clusterer/pyannote-v4/**" 2>/dev/null
    git lfs checkout 2>/dev/null
    log_ok "SpeakerKit models ready"

    # Verify
    MODEL_PATH="$WHISPER_DIR/openai_whisper-$MODEL"
    if [[ -d "$MODEL_PATH" ]]; then
        log_ok "Model verified: $MODEL_PATH"
    else
        log_error "Model not found at: $MODEL_PATH"
        log_error "Try running: cd $WHISPER_DIR && git lfs pull --include='openai_whisper-$MODEL/*'"
        exit 1
    fi
else
    log_info "Skipping model download"
fi

# ─── Build ──────────────────────────────────────────────────────

log_step "Building MeetingTaker"

cd "$REPO_DIR"

log_info "Resolving Swift Package dependencies..."
swift package resolve 2>/dev/null

log_info "Building MeetingTaker app (release)..."
swift build -c release --product meeting-taker 2>/dev/null

log_info "Building mtaker CLI (release)..."
swift build -c release --product mtaker 2>/dev/null

log_ok "Build complete"

# ─── Install ────────────────────────────────────────────────────

log_step "Installing"

APP_DIR="$REPO_DIR/MeetingTaker.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$REPO_DIR/.build/release/meeting-taker" "$MACOS_DIR/MeetingTaker"
chmod +x "$MACOS_DIR/MeetingTaker"

cp "$REPO_DIR/.build/release/mtaker" "$MACOS_DIR/mtaker"
chmod +x "$MACOS_DIR/mtaker"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MeetingTaker</string>
    <key>CFBundleDisplayName</key>
    <string>MeetingTaker</string>
    <key>CFBundleIdentifier</key>
    <string>com.meetingtaker.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>MeetingTaker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetingTaker needs microphone access to transcribe your voice in real-time.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTaker uses ScreenCaptureKit to capture system audio (Zoom, Meet, etc.). Only audio is captured, never screen content.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

log_info "Installing mtaker CLI to /usr/local/bin..."
sudo cp "$REPO_DIR/.build/release/mtaker" /usr/local/bin/mtaker 2>/dev/null
sudo chmod +x /usr/local/bin/mtaker 2>/dev/null

log_ok "Installation complete"

# ─── Summary ────────────────────────────────────────────────────

log_step "Setup Complete 🎉"

echo -e "${BOLD}MeetingTaker is ready!${NC}"
echo ""
echo "  📱 App:     open $APP_DIR"
echo "  🖥  CLI:     mtaker --help"
echo "  📁 Models:  $MODELS_DIR"
echo ""
echo "Quick start:"
echo "  mtaker transcribe audio.wav                    # Transcribe a file"
echo "  mtaker transcribe audio.wav --diarize          # With speaker ID"
echo "  mtaker transcribe audio.wav -f srt -o subs.srt # Export SRT"
echo "  mtaker watch --source both                     # Auto-detect calls"
echo "  mtaker serve --port 50060                      # API server"
echo ""
echo -e "${GREEN}100% local. Zero external dependencies.${NC}"
