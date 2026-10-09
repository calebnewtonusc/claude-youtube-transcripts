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

**Never hand-roll `yt-dlp --write-auto-subs` for a corpus.** Under a 429 it prints an
error, writes no `.vtt`, and a script that saves whatever text it found records a blank
transcript with no failure anywhere. On 2026-10-09 a creator ingest saved ten empty
transcripts this way before anyone looked. Use `yt-transcript` (or `yt-bulk`), give long
videos a long timeout (300 s killed 22 of 134 mid-transcription), and count empty
transcripts before reporting a number.

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

## Building a corpus

Fetching is the easy half. "Build a corpus of channel X" is almost never a request for a
folder of files; it is a request to **know** what is in that channel. Run the whole arc
without being asked to: size it, fetch it, read it, distill it.

**Size it before committing.** `yt-bulk <url> --list` first, then report video count, total
duration, and estimated word count, and say what that implies. Forty hours is roughly 400k
words and is a genuine read. Three hundred videos is a different project and deserves a
conversation about staged reading before an hour of downloads happens.

**Standard layout**, so every corpus looks the same and tooling written for one works on the
next:

```
<name>-corpus/
  transcripts/YYYY-MM-DD-slug.md    one per video, frontmatter + timestamped paragraphs
  data/videos.json                  every video found on the channel
  data/manifest.json                what was actually fetched: engines, word counts, failures
  scripts/                          the pipeline, resumable
  README.md                         what this is, how to regenerate, accuracy caveat
```

Frontmatter carries what later layers need: `transcript_engine` (so mixed-engine corpora stay
auditable), `upload_date`, `duration_seconds`, `word_count`. Keep engines consistent across a
corpus where you can; whisper and caption text read noticeably differently and that difference
surfaces in anything indexed or trained on top.

**Record failures in the manifest rather than crashing the run.** One bad video should never
cost the other eighty-nine.

**Default to a private repo when the material is someone else's teaching.** A full transcript
archive of a living creator's channel is their copyrighted work. Private is the right default
for personal study, and the README should say plainly that it is not for redistribution. Ask
before making one public, and if the user is working _with_ the creator, note that publishing
is the creator's call and not the user's.

**Then actually read it.** All of it, not the titles and not a sample. Read in batches and
write distilled notes to a scratch file as you go, so a context compaction mid-read costs
nothing. The goal is to know the material well enough to apply it later, not to produce a
summary.

While reading, work out and record, in the source's own vocabulary rather than translated into
something more familiar:

- who the person actually is, established from the corpus rather than assumed
- the recurring framework and what they call it
- the concrete practices, meaning anything they tell people to actually do
- the stories, with enough detail to retell them accurately
- where they sit on the questions that matter most for why the user is reading them
- where they contradict or are in tension with the mainstream of their own tradition

**Distill into durable notes, not a chat reply.** A corpus read that lives only in one
conversation gets lost. If the user keeps a personal context or notes repo, write the
distillation there as a small set of on-demand files, wire it into whatever index and memory
system that repo uses, and commit. Split by concern rather than by video: the framework, the
practices, the stories, and one file on how it applies to this specific user.

**Read the user's own relevant notes before writing that application file**, and hold their
stated positions. Someone reading a teacher on a subject they are personally living has
already decided things about it, and the useful work is naming where the material confirms
them, where it sharpens them, and where it should be left. Flag anything in the teaching that
would be harmful applied to their actual situation. Resonance is not the goal; an accurate map
of a limited teacher beats a flattering map of a great one.

**Carry the accuracy caveat forward.** The distillation inherits it: machine transcripts are
fine for study and retrieval and not fine for quoting to third parties without verification,
because proper nouns and domain jargon are exactly where both engines slip.
