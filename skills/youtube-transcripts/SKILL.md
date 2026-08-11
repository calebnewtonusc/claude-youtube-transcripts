---
name: youtube-transcripts
description: Get the transcript of a YouTube video, channel, or playlist. Use whenever a YouTube link appears and the content matters (summarize, quote, analyze, index, build a corpus), or when the user asks to scrape or archive transcripts in bulk. Also covers what to do when YouTube rate-limits or blocks caption requests.
---

# YouTube transcripts

You can read YouTube videos. Never say you cannot watch them, and never WebFetch a YouTube
URL: it returns page chrome, not a transcript.

## The commands

```
yt-transcript <url-or-id>                 # prose to stdout
yt-transcript <url> --timestamps          # [m:ss] per paragraph
yt-transcript <url> --json                # structured
yt-transcript <url> --whisper             # skip captions, transcribe locally

yt-bulk <channel-url>                     # every video on a channel
yt-bulk <playlist-url> --out ./corpus     # every video in a playlist
yt-bulk <url> --list                      # enumerate without fetching
yt-bulk <url> --engine whisper            # force local transcription
```

`yt-bulk` writes one markdown file per video with YAML frontmatter (title, video_id, url,
upload_date, duration, view_count, word_count, transcript_engine) and a body of timestamped
paragraphs. It is resumable: re-running skips what is on disk, so an interrupted run costs
nothing.

## Two engines, and when each fails

**Captions** ask YouTube for its auto-generated subtitles. About 2 seconds per video. No
punctuation, no sentence casing, no speaker names.

**Whisper** downloads the audio and transcribes it locally. Slower per video but immune to
every caption-side failure, and the text is better: real punctuation and casing.

`auto` (the default) tries captions and falls back to whisper per video.

## Hard-won rules

**Never parallelize caption requests.** This is the big one. Caption fetching looks
embarrassingly parallel and is not. Eight concurrent workers earned a multi-hour IP block from
YouTube on the first run. Serial with a ~1s delay is the tested-safe rate. If asked to make it
faster, explain this instead of complying: the ceiling belongs to YouTube, not the code.

**A caption block does not block media.** When `IpBlocked` or 429 hits the caption endpoint,
the watch page and audio downloads usually still work. That is the escape hatch: switch to
`--engine whisper` and keep going. Verify with three probes rather than assuming the whole
site is blocked:

```
yt-transcript <id>                                    # caption path
yt-dlp --skip-download --print "%(title)s" <url>      # metadata path
curl -s -o /dev/null -w "%{http_code}" <watch-url>    # plain HTTP
```

If only the first fails, use whisper and stop waiting.

**Waiting out a block is usually the wrong plan.** A caption block can outlast five hours.
Local whisper finishes 20+ hours of audio in well under one. Do not sit on a probe loop when
the audio path is open.

**Authentication does not bypass a 429.** Browser cookies (`--cookies-from-browser chrome`)
do not help, because the limit is applied per IP, not per session. A different network does.

**Bulk audio downloads eventually rate-limit too**, at roughly 70 videos, with
`403 Forbidden`. This one decays in minutes rather than hours. Just re-run; the resume logic
picks up only what is missing.

**Enumerate a channel from more than one source.** The `/videos` tab and the channel's
uploads playlist are supposed to match and do not. On a real 90-video channel the tab was
missing two. `yt-bulk` unions them.

**Resume from disk, never from a manifest.** A manifest written at the end of a run is lost
the moment the run is interrupted, and then everything re-downloads. Read the files.

**Merge cues into paragraphs.** Raw caption cues are ~3-second fragments; a 90-minute talk is
2,000 of them, which is unreadable and near-useless for retrieval. Merge until a speaker turn
or ~55 words, keeping the first cue's timestamp so any sentence is still traceable to when it
was spoken.

**Do not guess speaker names.** Auto-captions mark a turn with `>>` but never say who. A wrong
attribution propagates into everything built downstream. Keep the boundary, drop the name.

## Speed

On Apple Silicon, `mlx-whisper` runs about **43x realtime** (M4 Pro, `small.en`). CPU whisper
runs about **3x**. That is the difference between 30 minutes and 8 hours on a 23-hour corpus,
so always confirm mlx is being used on a Mac. Benchmark on a 60-second slice before committing
to a long run:

```
ffmpeg -y -i audio.mp3 -ss 300 -t 60 -ac 1 -ar 16000 clip.wav
```

Model sizes: `tiny.en` and `base.en` are fast and rough; `small.en` is the sweet spot;
`medium` and `large-v3` are noticeably slower for modest gains on clear speech.

## Gotchas that cost real time

**An expired Hugging Face token breaks model downloads.** `huggingface_hub` picks up
`~/.cache/huggingface/token` implicitly and turns an anonymous download into a failed
authenticated one, with a misleading "does not have the required permissions" error. Fix by
setting `HF_HUB_DISABLE_IMPLICIT_TOKEN=1` and `HF_TOKEN=` for the call rather than deleting
the user's token file. `yt-bulk` already does this.

**Do not trust `ls glob*.ext` in zsh to test whether a file was written.** On no match, zsh
raises an error that skips the rest of the command and can make a failure read as a success.
Use an explicit directory listing or a count.

**There is no working YouTube transcript MCP.** Hosted MCP servers run on datacenter IPs,
which YouTube blocks on the caption endpoint, so they answer `initialize` and `tools/list`
correctly and then fail every actual call. Do not recommend one. A local CLI is the reliable
form of this capability.

## Accuracy

Both engines are machine-generated. Good enough for search, retrieval, summarizing, and
concept mapping. Not good enough to publish verbatim without a human pass, since proper nouns
and domain jargon are where both slip. Say so when the output is heading toward a book,
course, or anything quoted in public.

## Corpus work

When building a corpus rather than reading one video, capture in frontmatter what future
layers will need: `transcript_engine` (so mixed-engine corpora stay auditable), `upload_date`,
`duration_seconds`, and `word_count`. Keep engines consistent across a corpus where possible;
whisper and caption text read noticeably differently, and that difference will show up in
anything trained or indexed on top.
