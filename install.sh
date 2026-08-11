#!/bin/bash
# One-command install. Idempotent: safe to re-run.
#
#   git clone https://github.com/calebnewtonusc/claude-youtube-transcripts
#   cd claude-youtube-transcripts && ./install.sh
#
# Installs the CLIs, the Claude skill, and (optionally) the auto-detect hook.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARE="$HOME/.local/share/yt-transcripts"
BIN="$HOME/.local/bin"
SKILLS="$HOME/.claude/skills"

say()  { printf "\033[1m%s\033[0m\n" "$*"; }
warn() { printf "  ! %s\n" "$*"; }
ok()   { printf "  ✓ %s\n" "$*"; }

say "Installing claude-youtube-transcripts"

# --- 1. system dependencies -------------------------------------------------
if ! command -v yt-dlp >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing yt-dlp via Homebrew..."
    brew install yt-dlp >/dev/null 2>&1 && ok "yt-dlp" || warn "yt-dlp install failed"
  else
    warn "yt-dlp missing and Homebrew not found. Install it: pipx install yt-dlp"
  fi
else
  ok "yt-dlp $(yt-dlp --version 2>/dev/null)"
fi

command -v ffmpeg >/dev/null 2>&1 && ok "ffmpeg" || {
  command -v brew >/dev/null 2>&1 && brew install ffmpeg >/dev/null 2>&1 \
    && ok "ffmpeg" || warn "ffmpeg missing (needed for local whisper)"
}

command -v jq >/dev/null 2>&1 && ok "jq" || warn "jq missing (only needed for the hook)"

# --- 2. python environments -------------------------------------------------
mkdir -p "$SHARE" "$BIN"

say "Setting up the captions engine..."
python3 -m venv "$SHARE/captions" 2>/dev/null
"$SHARE/captions/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1
if "$SHARE/captions/bin/pip" install --quiet youtube-transcript-api >/dev/null 2>&1; then
  ok "youtube-transcript-api"
else
  warn "youtube-transcript-api install failed"
fi

say "Setting up the local whisper engine..."
if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
  python3 -m venv "$SHARE/mlx" 2>/dev/null
  "$SHARE/mlx/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1
  if "$SHARE/mlx/bin/pip" install --quiet mlx-whisper >/dev/null 2>&1; then
    ok "mlx-whisper (Apple Silicon GPU, ~40x realtime)"
  else
    warn "mlx-whisper install failed; captions will still work"
  fi
else
  warn "Not Apple Silicon: skipping mlx-whisper."
  warn "For local transcription install faster-whisper and edit MLX_PY in bin/yt-bulk."
fi

# --- 3. the CLIs ------------------------------------------------------------
install -m 0755 "$HERE/bin/yt-bulk" "$BIN/yt-bulk"
install -m 0755 "$HERE/bin/yt-transcript" "$BIN/yt-transcript"
ok "yt-transcript and yt-bulk -> $BIN"

case ":$PATH:" in
  *":$BIN:"*) ok "$BIN is on PATH" ;;
  *) warn "$BIN is NOT on PATH. Add: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- 4. the Claude skill ----------------------------------------------------
mkdir -p "$SKILLS/youtube-transcripts"
cp "$HERE/skills/youtube-transcripts/SKILL.md" "$SKILLS/youtube-transcripts/"
ok "skill -> $SKILLS/youtube-transcripts"

# --- 5. the auto-detect hook (optional) -------------------------------------
mkdir -p "$HOME/.claude/hooks"
install -m 0755 "$HERE/hooks/youtube-transcript-ready.sh" \
  "$HOME/.claude/hooks/youtube-transcript-ready.sh"

SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" <<'PY'
import json, sys, collections, shutil
p = sys.argv[1]
try:
    d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
except Exception as e:
    print("  ! could not parse settings.json (%s); skipping hook registration" % e)
    sys.exit(0)

cmd = 'bash "$HOME/.claude/hooks/youtube-transcript-ready.sh"'.replace(
    "$HOME", __import__("os").path.expanduser("~"))
hooks = d.setdefault("hooks", collections.OrderedDict())
ups = hooks.setdefault("UserPromptSubmit", [])

if any("youtube-transcript-ready" in h.get("command", "")
       for e in ups for h in e.get("hooks", [])):
    print("  ✓ hook already registered")
    sys.exit(0)

shutil.copy(p, p + ".backup-yt-transcripts")
ups.append(collections.OrderedDict([("hooks", [collections.OrderedDict([
    ("type", "command"), ("command", cmd), ("timeout", 10),
    ("statusMessage", "YouTube link detected, loading transcript tool..."),
])])]))
json.dump(d, open(p, "w"), indent=2)
print("  ✓ hook registered (backup at settings.json.backup-yt-transcripts)")
PY
else
  warn "No ~/.claude/settings.json; skipping hook. The skill still works."
fi

say ""
say "Done. Try:"
echo "  yt-transcript 'https://youtu.be/jNQXAC9IVRw' --timestamps"
echo "  yt-bulk 'https://www.youtube.com/@some-channel' --list"
say ""
say "Restart Claude Code so it picks up the new skill and hook."
