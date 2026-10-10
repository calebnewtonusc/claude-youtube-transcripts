"""A cached local transcription is returned without downloading or transcribing,
and a miss writes the cache."""
import importlib.util
import json
import os
import tempfile
from importlib.machinery import SourceFileLoader

here = os.path.dirname(os.path.abspath(__file__))
cache = tempfile.mkdtemp()
os.environ["YT_TRANSCRIPT_CACHE"] = cache
loader = SourceFileLoader("ytbulk", os.path.join(here, "..", "bin", "yt-bulk"))
spec = importlib.util.spec_from_loader("ytbulk", loader)
yb = importlib.util.module_from_spec(spec)
loader.exec_module(yb)


def refuse(*a, **k):
    raise AssertionError("ran a subprocess on a cache hit")


yb.run = refuse

with open(os.path.join(cache, "abcdefghijk.whisper-small.en.json"), "w") as f:
    json.dump([[0.0, "hello"], [4.5, "world"]], f)
assert yb.via_whisper("abcdefghijk", "small.en") == [(0.0, "hello"), (4.5, "world")]

yb._whisper_uncached = lambda vid, model: [(1.0, "fresh")]
assert yb.via_whisper("zzzzzzzzzzz", "small.en") == [(1.0, "fresh")]
assert os.path.exists(os.path.join(cache, "zzzzzzzzzzz.whisper-small.en.json"))
print("ok")
