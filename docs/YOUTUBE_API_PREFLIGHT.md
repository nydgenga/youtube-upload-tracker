# YouTube Data API: go/no-go preflight

This is a **read-only experiment** for deciding whether the official YouTube Data API can replace the intermittent public Atom feeds. It does **not** switch the widget to the API, modify SQLite, or create a release.

## Get an API key

1. In [Google Cloud Console](https://console.cloud.google.com/projectcreate), create or select a project you control (e.g. `YouTube Upload Tracker Test`).
2. Under [API Library](https://console.cloud.google.com/apis/library/youtube.googleapis.com), enable **YouTube Data API v3** for the selected project.
3. Under [Credentials](https://console.cloud.google.com/apis/credentials), create an **API key**. Do **not** create an OAuth client: this test reads only public channel information.
4. Restrict the key's **API restrictions** to **YouTube Data API v3**. Google also recommends application restrictions. IP-address restrictions are difficult for a desktop that changes networks or VPN endpoints; for this short test, keep the key private, use it only locally, and revoke it if you no longer need it. Do not paste it into a chat, a bug report, a GitHub commit, or command-line arguments.

## Run locally on Bazzite

From the root of the downloaded or cloned repository:

```bash
python3 tools/youtube_api_probe.py
```

The script prompts for the key without echoing it. It tests two channel IDs previously associated with YouTube Atom HTTP 404s. It prints channel names, several recent video titles and publication times, and whether the API returned an error. Only **three API calls** are expected: one `channels.list` covering both channels, followed by one `playlistItems.list` for each channel. Successful requests cost 1 quota unit apiece.

To test a specific channel ID instead:

```bash
python3 tools/youtube_api_probe.py --channel UCm22FAXZMW1BaWeFszZxUKw
```

Use a permanent `UC...` channel ID for the optional `--channel` argument. The key is transmitted over HTTPS using `X-Goog-Api-Key` rather than in a URL query string.

## What counts as success?

- The two channel lookups should return the expected names and a public uploads playlist.
- Each channel's upload playlist should return recent video entries, with titles and dates that match YouTube.
- The same test can be repeated **once later** for a small consistency check; repeated aggressive polling is not useful.
- Note whether an *active livestream* appears; the uploads playlist is **not guaranteed** to list live broadcasts currently in progress, so successful ordinary video retrieval alone does not prove live coverage.

If successful, next steps would be an **opt-in API-source development build** that reuses the current database and Seen state. Key handling and quota limits must be designed before implementation. A key stored on a user's desktop cannot be made completely secret from local users or software; never distribute an API key in a public plasmoid.

## Privacy and limits

The script uses Python's standard library only. It does not save the key, create a log file, write to the database, or change the widget. API requests still count against the Google Cloud project's quota; consult [Google's quota calculator](https://developers.google.com/youtube/v3/determine_quota_cost) and [API key guidance](https://docs.cloud.google.com/docs/authentication/api-keys-best-practices) for current restrictions.
