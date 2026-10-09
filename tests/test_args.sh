#!/usr/bin/env bash
# yt-transcript must accept a video id that starts with "-".
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/bin/yt-transcript" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ytt", sys.argv[1])
spec = importlib.util.spec_from_loader("ytt", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
cases = [
    (["-pHnkusDkmk"], ["https://youtu.be/-pHnkusDkmk"]),
    (["-pHnkusDkmk", "--json"], ["https://youtu.be/-pHnkusDkmk", "--json"]),
    (["dQw4w9WgXcQ", "--timestamps"], ["dQw4w9WgXcQ", "--timestamps"]),
    (["--whisper", "https://youtu.be/abc"], ["--whisper", "https://youtu.be/abc"]),
]
bad = [(i, o, m.normalize_argv(i)) for i, o in cases if m.normalize_argv(i) != o]
assert m.video_id("https://youtu.be/-pHnkusDkmk") == "-pHnkusDkmk"
for b in bad: print("FAIL", b)
print("ok" if not bad else f"{len(bad)} failed"); sys.exit(1 if bad else 0)
PY
