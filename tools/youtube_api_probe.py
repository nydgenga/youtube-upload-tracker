#!/usr/bin/env python3
"""One-time, read-only YouTube Data API probe for YouTube Upload Tracker.

The API key is typed into a local hidden prompt, sent as an HTTPS header,
and never written to a file or displayed in output. No extra packages needed.
"""
import argparse
from getpass import getpass
import json
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "https://www.googleapis.com/youtube/v3/"
DEFAULT_CHANNELS = (
    "UCm22FAXZMW1BaWeFszZxUKw",  # Previously successful in widget, then HTTP 404 via Atom
    "UC0YpCsvynhbjTzrS9AIRjiQ",  # Qwazar77, intermittently failed via Atom
)
CHANNEL_ID_RE = re.compile(r"UC[A-Za-z0-9_-]{22}$")


class ProbeError(Exception):
    pass


def api_get(endpoint, params, api_key, *, opener=urlopen):
    """Retrieve a JSON API response without placing the secret in the URL."""
    uri = BASE + endpoint + "?" + urlencode(params)
    req = Request(uri, headers={
        "X-Goog-Api-Key": api_key,
        "Accept": "application/json",
    })
    try:
        with opener(req, timeout=20) as response:
            data = json.load(response)
    except HTTPError as ex:
        reason = ""
        try:
            body = json.load(ex)
            detail = body.get("error", {})
            reason = detail.get("message", "")
            if not reason:
                reason = str(detail.get("errors", [{}])[0].get("reason", ""))
        except (ValueError, AttributeError, IndexError, OSError):
            pass
        raise ProbeError(f"HTTP {ex.code} from {endpoint}: {reason[:300]}") from None
    except (URLError, TimeoutError, OSError) as ex:
        raise ProbeError(f"Connection error from {endpoint}: {type(ex).__name__}: {ex}") from None
    except (ValueError, TypeError):
        raise ProbeError(f"Invalid JSON from {endpoint}") from None
    if not isinstance(data, dict) or "error" in data:
        raise ProbeError(f"Unexpected API response from {endpoint}")
    return data


def probe(channels, api_key, *, request=api_get):
    results = request("channels", {
        "part": "snippet,contentDetails",
        "id": ",".join(channels),
        "fields": "items(id,snippet(title),contentDetails(relatedPlaylists(uploads)))",
        "maxResults": len(channels),
    }, api_key)
    found = {item["id"]: item for item in results.get("items", []) if isinstance(item, dict) and "id" in item}
    print(f"Channel lookup: {len(found)}/{len(channels)} found")
    for channel_id in channels:
        info = found.get(channel_id)
        if info is None:
            print(f"\n{channel_id}: NOT FOUND (check channel ID or public availability)")
            continue
        title = info.get("snippet", {}).get("title", "(untitled channel)")
        uploads = info.get("contentDetails", {}).get("relatedPlaylists", {}).get("uploads")
        print(f"\n{title} [{channel_id}]")
        if not uploads:
            print("  No uploads playlist reported")
            continue
        response = request("playlistItems", {
            "part": "snippet,contentDetails",
            "playlistId": uploads,
            "maxResults": 10,
            "fields": "items(snippet(title,resourceId(videoId)),contentDetails(videoId,videoPublishedAt)),nextPageToken",
        }, api_key)
        items = response.get("items", [])
        print(f"  Upload playlist: {len(items)} recent entries returned")
        for item in items[:5]:
            snippet = item.get("snippet", {})
            details = item.get("contentDetails", {})
            video_id = details.get("videoId") or snippet.get("resourceId", {}).get("videoId", "")
            when = details.get("videoPublishedAt", "unknown date")
            name = " ".join(snippet.get("title", "(untitled video)").split())
            print(f"  - {when}  {name[:100]}  https://youtu.be/{video_id}")
    return found


def main(argv=None):
    p = argparse.ArgumentParser(description="Check YouTube Data API channel uploads without changing the KDE widget.")
    p.add_argument("--channel", action="append", dest="channels", metavar="UC_ID",
                   help="Channel ID to probe (repeat option for multiple channels)")
    args = p.parse_args(argv)
    channels = list(dict.fromkeys(args.channels or DEFAULT_CHANNELS))
    for ch in channels:
        if not CHANNEL_ID_RE.fullmatch(ch):
            p.error(f"Invalid channel ID: {ch!r}")
    print("API key input stays on this computer. Never send it to ChatGPT or GitHub.")
    try:
        api_key = getpass("Paste your YouTube Data API key (input hidden): ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\nCancelled", file=sys.stderr)
        return 2
    if not api_key:
        print("No API key entered.", file=sys.stderr)
        return 2
    try:
        probe(channels, api_key)
    except ProbeError as e:
        print(f"API test failed: {e}", file=sys.stderr)
        return 1
    finally:
        api_key = ""
    print("\nThe test made read-only requests. No widget settings or database files were touched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
