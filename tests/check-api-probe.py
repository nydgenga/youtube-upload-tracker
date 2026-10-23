#!/usr/bin/env python3
"""Offline checks for the API preflight, no real key or network required."""
import io
import importlib.util
from contextlib import redirect_stdout
from pathlib import Path

probe_path = Path(__file__).resolve().parents[1] / "tools" / "youtube_api_probe.py"
spec = importlib.util.spec_from_file_location("youtube_api_probe", probe_path)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

captured = []

def fake_get(endpoint, params, api_key):
    assert api_key == "not-a-real-key"
    captured.append((endpoint, params))
    if endpoint == "channels":
        return {"items": [{"id": "UCm22FAXZMW1BaWeFszZxUKw", "snippet": {"title": "Test channel"}, "contentDetails": {"relatedPlaylists": {"uploads": "UUm22FAXZMW1BaWeFszZxUKw"}}}]}
    if endpoint == "playlistItems":
        return {"items": [{"snippet": {"title": "Mock video", "resourceId": {"videoId": "abcdefghijk"}}, "contentDetails": {"videoPublishedAt": "2026-10-22T12:00:00Z", "videoId": "abcdefghijk"}}]}
    raise AssertionError(endpoint)

out = io.StringIO()
with redirect_stdout(out):
    probe.probe(["UCm22FAXZMW1BaWeFszZxUKw"], "not-a-real-key", request=fake_get)
assert "Mock video" in out.getvalue()
assert len(captured) == 2
assert captured[0][0] == "channels"
assert captured[1][0] == "playlistItems"
assert captured[1][1]["maxResults"] == 10

class FakeResponse:
    def __enter__(self): return self
    def __exit__(self, *_): return False
    def read(self): return b'{"items": []}'

def opener(req, timeout):
    assert timeout == 20
    assert "key=" not in req.full_url
    assert req.get_header("X-goog-api-key") == "secret-test"
    return FakeResponse()
assert probe.api_get("channels", {"part": "snippet"}, "secret-test", opener=opener) == {"items": []}
print("PASS read-only API probe, local key header, response parsing, and no-key URLs")
