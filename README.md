# claude-youtube-transcripts

Give Claude the permanent ability to read YouTube: one video, a playlist, or an entire
channel. No MCP, no API key, no per-session setup.

```
yt-transcript https://youtu.be/VIDEO_ID --timestamps
yt-bulk https://www.youtube.com/@somechannel --out ./corpus
```

After install, Claude reads any YouTube link you paste without being asked. A hook detects
the link and hands Claude the command; a skill teaches it the rate-limit rules so it does not
get your IP blocked.

## Install

```
git clone https://github.com/calebnewtonusc/claude-youtube-transcripts
cd claude-youtube-transcripts && ./install.sh
```

Then restart Claude Code. The installer is idempotent, so re-running it is safe.

It installs `yt-dlp` and `ffmpeg` (via Homebrew if needed), two isolated Python venvs, the
`yt-transcript` and `yt-bulk` CLIs into `~/.local/bin`, the `youtube-transcripts` skill into
`~/.claude/skills/`, and a `UserPromptSubmit` hook into `~/.claude/settings.json` (backed up
first).

## Why not an MCP

There are hosted YouTube-transcript MCP servers. They do not work. They run on datacenter IPs,
which YouTube blocks on the caption endpoint, so they answer `initialize` and `tools/list`
correctly and then fail every real call. I tested one: valid MCP handshake, `get_transcript`
returned "Service temporarily busy" every time. A local CLI is the reliable form of this.

## Two engines

|                                  | Captions              | Whisper                               |
| -------------------------------- | --------------------- | ------------------------------------- |
| Speed                            | ~2s per video         | ~43x realtime on Apple Silicon        |
| Source                           | YouTube auto-captions | Downloaded audio, transcribed locally |
| Punctuation                      | None                  | Yes                                   |
| Survives a caption block         | No                    | **Yes**                               |
| Works when captions are disabled | No                    | **Yes**                               |

Default is `auto`: try captions, fall back to whisper per video. Force either with
`--engine captions` or `--engine whisper`.

## What this knows that you would otherwise learn the hard way

**Never parallelize caption requests.** Eight concurrent workers earned a multi-hour IP block
from YouTube. Serial with a 1s delay is the tested-safe rate. The ceiling belongs to YouTube;
no amount of concurrency beats it, and trying costs you hours.

**A caption block does not block media.** When captions return `IpBlocked` or 429, the watch
page and audio downloads usually still work. Switch to `--engine whisper` and keep going
instead of waiting. In the run this was built from, the caption block outlasted five hours
while local whisper finished 22.5 hours of audio in 52 minutes.

**Cookies do not bypass a 429.** The limit is per IP, not per session. A different network
works; `--cookies-from-browser` does not.

**Channel enumeration needs more than one source.** The `/videos` tab and the uploads playlist
are supposed to match and do not. On a real 90-video channel, the tab was missing two.
`yt-bulk` unions them.

**Resume from disk, not a manifest.** A manifest written at the end of a run is lost the
moment the run is interrupted, and then everything re-downloads.

**Merge cues into paragraphs.** Raw caption cues are ~3-second fragments; a 90-minute talk is
2,000 of them. Unreadable, and near-useless for retrieval. `yt-bulk` merges to ~55 words or a
speaker turn, keeping the first cue's timestamp so every sentence stays traceable.

**Do not guess speaker names.** Auto-captions mark turns with `>>` but never say who. A wrong
attribution poisons everything built downstream.

## Output

One markdown file per video:

```markdown
---
title: "..."
video_id: "..."
upload_date: "2026-07-27"
duration: "16:39"
word_count: 3200
transcript_engine: "mlx-whisper-small.en"
---

## Transcript

**[0:00]** First paragraph of speech...

**[0:47]** Next paragraph...
```

`transcript_engine` matters: whisper and caption text read differently, and a mixed corpus
should stay auditable.

## Building a corpus

"Build a corpus of this channel" is almost never a request for a folder of files. It is a
request to **know** what is in the channel. The skill teaches Claude to run the whole arc
without being told: size it first and report back, fetch it, read all of it, then distill it
into durable notes rather than a chat reply that disappears.

That means the working prompt is short:

```
Build a corpus of https://www.youtube.com/@somechannel, read all of it,
and distill it into my notes. I care about X.
```

The conventions it follows so you do not have to specify them: standard repo layout
(`transcripts/`, `data/`, `scripts/`), private repo by default when the material is a living
creator's teaching, failures recorded in the manifest instead of crashing the run, notes
written incrementally so a long read survives a context compaction, and the distillation split
by concern (framework, practices, stories, how it applies to you) rather than by video.

It also reads whatever standing notes you keep about yourself before writing the "how this
applies to you" part, and flags anything in the teaching that would be harmful applied to your
actual situation. An accurate map of a limited teacher beats a flattering map of a great one.

## Options

```
yt-bulk <url> [--out DIR] [--engine auto|captions|whisper]
              [--model small.en] [--lang en] [--limit N] [--list]

yt-transcript <url-or-id> [--timestamps] [--json] [--whisper] [--model small.en]
```

Whisper models: `tiny.en`, `base.en`, `small.en` (default, the sweet spot), `medium`,
`large-v3`.

## Requirements

macOS with Apple Silicon gets the fast local path (`mlx-whisper`). Elsewhere the captions
engine works fine; for local transcription, install `faster-whisper` and point `MLX_PY` in
`bin/yt-bulk` at it.

Needs Python 3.9+, `yt-dlp`, `ffmpeg`, and `jq` (for the hook only).

## Accuracy

Both engines are machine-generated. Good for search, retrieval, summarizing, and indexing.
Not good enough to publish verbatim without a human pass: proper nouns and domain jargon are
where both slip. Respect the rights of whoever made the video.

---

All glory to God! ✝️❤️
