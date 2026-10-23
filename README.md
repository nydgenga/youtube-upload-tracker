# YouTube Upload Tracker (Plasma 6)

**Status:** v0.1.0-dev15 — *experimental test build*, not a released product.

**dev15 is a reliability-focused test build.** It adds service-outage detection,
conservative single-feed recovery probes, and manual-refresh cooldown handling.
It changes neither the Atom parser nor the SQLite data model from the working
dev14 build. Historical read/unread choices and followed channels remain intact.

**Development diagnostics:** This build intentionally emits warning-level
`YTUPLOAD_DEV15` messages so they can be grepped from the Plasma journal.
These are test diagnostics, not necessarily real warnings; public builds must
reduce them. Messages contain channel IDs, parser counts, and short errors,
not whole XML responses, video titles, or credentials. Example:

```bash
journalctl --user -b --since '10 minutes ago' --no-pager | grep 'YTUPLOAD_DEV15'
```

**Known source limitation:** YouTube's public Atom feed may omit ongoing or
archived livestreams, and its new uploads may appear after a delay. The
parser fix cannot retrieve content YouTube never includes in the feed.

**Bazzite verification:** Through dev14, the user verified real feed imports,
read/unread controls, successful manual refreshes, and journal logging. The
new circuit-breaker behavior in dev15 still needs desktop and actual-outage
recovery testing.

A self-contained KDE Plasma 6 panel/desktop widget tracking selected public
YouTube channels via their Atom feeds. No login, API key, daemon or Flatpak.

## What's implemented

- Add a YouTube channel by `UC...` ID, `/channel/UC...` URL, RSS feed URL,
  `@handle`, or standard channel handle URL. Handle resolution uses page metadata
  and may not work if YouTube blocks automated page requests; permanent channel
  ID is a reliable fallback.
- Check public feeds asynchronously and merge new videos into a chronological
  list with thumbnail URLs, titles, channel names, and publication timestamps.
- Keep read/unread state across Plasma restarts in SQLite; *initial* feed
  import is now unseen by default. Earlier saved read/unread states are preserved
  on upgrade, and users can mark all stored entries unseen explicitly.
- Local unread badge on the panel icon. Video click opens the browser and marks
  that entry as seen. A per-video Seen checkbox allows manual toggling without
  opening the browser; Mark all seen or Mark all unseen using the two adjacent buttons; filter unseen only, page through history.
- Bounded network scheduling: four concurrent requests maximum, staggered
  channel offsets, 15-second request timeout, exponential error backoff.
- 90-day retention of seen video records, indefinite unread entries, and
  permanent ID-only tombstones to prevent the same old upload reappearing
  as new after retention cleanup.
- A configurable 5–120-minute automatic refresh interval, default 15 minutes.

**Limitations:** Feeds only expose a limited recent history; this is **not**
real-time push notification delivery. YouTube does not guarantee inclusion of
all scheduled/current/past livestreams in the public feed. The widget displays
all available Atom entries without filtering Shorts or livestreams. There are
no desktop alerts in this prototype, only an icon badge. Thumbnail rendering
uses Qt's image cache; a strict 50-MB disk cache is not yet implemented.

## Installation on Bazzite or Nobara (Plasma 6)

From the folder containing the `.plasmoid` file:

```sh
kpackagetool6 --type Plasma/Applet --install youtube-upload-tracker-0.1.0-dev15.plasmoid
```

If you've installed an earlier test build, use:

```sh
kpackagetool6 --type Plasma/Applet --upgrade youtube-upload-tracker-0.1.0-dev15.plasmoid
```

Open the **Add Widgets** interface and search for **YouTube Upload Tracker**,
then add it to your panel. Open the popup, select **Channels**, and paste a
channel address. KDE's `plasmoidviewer` (Plasma SDK) can also load the widget:

```sh
plasmoidviewer -a com.nydgenga.youtubeuploads
```

If the widget does not appear after upgrading, Plasma may still hold the old
QML in memory. You can log out and back in, or restart the shell with:

```sh
systemctl --user restart plasma-plasmashell.service
```

Uninstall this **test** widget using:

```sh
kpackagetool6 --type Plasma/Applet --remove com.nydgenga.youtubeuploads
```

Qt Quick LocalStorage and the SQLite Qt SQL driver must be available. They
are confirmed working in the current Bazzite tests; Nobara is still untested.

## Try this first

1. Add one known channel using its permanent ID or `/channel/UC...` URL.
2. Confirm the upload list populates with initial entries marked unseen; the badge should reflect their count. On an upgraded installation, use **Mark all unseen** if previous imports remain seen.
3. Add a second channel using its `@handle` URL to test page resolution.
4. Uncheck Seen on one existing video, confirm the unread badge increments, then
   check Seen again without opening the browser. Scroll and repeat to ensure
   the list does not jump. Click a video and confirm it opens and becomes seen.
5. Restart Plasma and confirm channels, uploads, and seen state survive.
6. Use **Refresh** to test networking; disconnect temporarily and confirm
   cached entries survive and the channel error is visible on **Channels**.

## Design notes

- The applet ID is `com.nydgenga.youtubeuploads`, separate from Glance Weather.
- It stores one SQLite database in Qt's QML offline storage for plasmashell.
  An additional applet instance shares the database, but cross-instance live
  UI synchronization is **not** implemented yet; use one instance for testing.
- Known video IDs are not purged automatically, by design. This keeps database
  growth small while ensuring a pruned upload cannot be flagged as new again.
- The initial version does not yet support filename/size telemetry, background
  notifications, bulk channel import, or transcript/history synchronization.

## Test status

All local Node parser tests, SQLite schema/migration tests and package checks
pass, including a 15-entry feed recovery scenario and strict ownership checks.
The dev12–dev14 parser and interface were verified against live feeds on
Bazzite; dev15's circuit-breaker logic is only locally tested so far. Nobara
is not yet tested for this widget. The ongoing livestream coverage question
remains separate from the parser regression.

The code is distributed under the 0BSD license (see LICENSE).

### dev15 outage safeguard (development)

The scheduler temporarily pauses feed polling if four or more distinct feeds
return HTTP 404, 429, or 5xx within three minutes and at least 75% of recent
results are failures. It retries one due feed after a ten-minute pause, with
exponential backoff up to one hour. Existing cached uploads remain accessible.

Manual Refresh respects cooldowns and cannot force requests during a suspected
outage; skipped channels are reported as deferred. For diagnostic logs:

```bash
journalctl --user -b --since '10 minutes ago' --no-pager | grep YTUPLOAD_DEV15
```

This is a heuristic for service problems, not a guarantee that the issue is
YouTube-wide. An isolated bad channel is still handled with its own backoff.
