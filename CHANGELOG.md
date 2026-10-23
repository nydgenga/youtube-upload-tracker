## v0.1.0-dev16 — 2026-10-22 (unreleased development build)

### Fixes
- Gate service-outage recovery probes with both a QML one-shot timer and the absolute next-probe deadline, preventing the early probe observed in dev15.
- Record an engine-instance identifier in the journal to distinguish separate applet instances and Plasma restarts.

### Maintenance
- Keep a stable `YTUPLOAD` journal prefix and permanent, low-volume error/recovery diagnostics. Routine network and parser traces remain development-only and can be disabled for a stable release.
- Expand scheduler tests to enforce both probe-delay guards and ensure rearming after failures. No database migration or feature changes.

## v0.1.0-dev15 — 2026-10-22 (unreleased development build)

**Bug fixes and reliability:**
- Recognize a probable upstream outage when at least four distinct channel feeds
  return HTTP 404, 429, or 5xx inside a rolling three-minute window, making up
  at least 75% of recent distinct results. This is a heuristic, not proof of a
  YouTube-wide outage.
- Pause ordinary feed polling during that outage, retry just one eligible feed
  after a ten-minute cooldown, then back off subsequent failed probes to a
  maximum of one hour. Resume ordinary staggered polling only after a probe
  returns a successfully parsed and stored feed.
- Preserve independent, persistent channel cooldowns. Manual Refresh no longer
  resets cooldowns after failures, nor forces requests during a suspected outage.
- Ensure pending manual-refresh progress completes when the circuit breaker
  defers queued channels. Show clear feedback for deferred requests and a
  non-alarming temporary-service-issue message.
- Add searchable `YTUPLOAD_DEV15` diagnostic events for outage detection,
  probe scheduling, probes, recovery and deferred manual refreshes.
- No data migration, change in channel identity, seen/unseen status, parsing,
  thumbnails or artwork. Real Plasma and upstream-outage recovery tests remain
  pending; local unit and package tests are not desktop verification.

## v0.1.0-dev14 — 2026-10-22

- Replace the single-item "More seen actions" menu with a directly visible **Mark all unseen** button, next to **Mark all seen**. Keep the existing disable condition and bulk status behavior.
- No changes to feed parsing, networking, SQLite schema, channel subscriptions, unread states, or how manual refresh works.
- Retain the `YTUPLOAD_DEV13` journal marker across this UI-only build so existing live diagnostic commands continue working.
- Test the button placement on Plasma 6; local static checks do not fully validate native control geometry.

## v0.1.0-dev13 — 2026-10-22

- Keep the now-working dev12 Atom parser and database unchanged.
- Fix invisible development diagnostics: emit `YTUPLOAD_DEV13` events with QML `console.warn()` rather than `console.log()`. Qt may disable debug-level QML messages, whereas warning-level events are generally visible in plasmashell's journal.
- Retain sanitized event data only: channel IDs, event type, entry counts, and concise failure reasons; never log full XML, video titles, or credentials.
- This is deliberately temporary **development-only** warning-level logging, not a change intended for public releases. Public release builds must disable these diagnostic events.
- Add a regression test verifying logging remains enabled in development, uses warning-level output, and does not change the parser or SQLite data model.

## v0.1.0-dev12 — 2026-10-22

- Recover from the feed parser regression introduced by dev8 and surfaced by dev11. Keep namespace validation but accept Qt QML reduced-DOM variations in YouTube-specific field names.
- Parse an upload ID from the standard Atom `<id>yt:video:VIDEO_ID</id>` field when `yt:videoId` is not accessible. Reject contradictory video IDs and conflicting channel ownership; never allow foreign namespace field names alone to identify uploads.
- Preserve dev11 per-channel feed diagnostics and zero-entry error reporting. A failed parse never erases existing video history or Seen status.
- Enable development-only structured `YTUPLOAD_DEV12` logs in plasmashell, including fetch starts, success/error, parse counts, number of Atom-ID fallbacks, and first entry's XML node names if an entire response remains unparsable. No raw XML, titles, descriptions, or personal credentials are logged.
- Keep the same SQLite database identity/schema, channel URLs, and seen/unseen values. No resets or re-adding should be needed.
- Add a 15-entry regression fixture (the previously observed failure), reduced-DOM test, foreign-namespace safety checks, and diagnostic marker checks. Bazzite integration still requires verification.

## v0.1.0-dev11 — 2026-10-22

- Add persistent per-channel feed diagnostics in Channels: entries accepted / XML entries found, newly imported entries on last check, and total locally stored entries. This distinguishes YouTube not returning an upload from a parser or display issue.
- Refuse to silently mark a feed successful if it contains Atom entries but the parser rejects every one. Retain existing cached videos and report an error instead.
- Add per-channel **Show uploads** action and a **Show all channels** return control. This allows inspection of a single channel independently of the combined feed's initial 50-item page limit; reset the Unseen-only filter when viewing a channel for diagnosis.
- Add an idempotent SQLite schema migration for the three feed-diagnostic counters; existing channel subscriptions, videos, tombstones, and seen/unseen choices are preserved. Diagnostics become populated on the next successful check.
- Tests cover the new parser entry count, migration of existing v0.1.0-dev10 data, repeat migrations, and per-channel SQL filtering.
- Do not claim full livestream coverage from YouTube Atom: live sessions may be absent from a channel's public upload feed even when the channel has an active broadcast.

## v0.1.0-dev10 — 2026-10-22

- Change the first successful feed import to mark all newly discovered uploads
  unseen, rather than automatically marking them seen. Subsequent refreshes
  preserve each existing video's explicitly chosen seen/unseen state.
- Preserve all existing database contents during upgrade. Because earlier
  versions did not distinguish auto-seen from manually seen, do not rewrite
  older records without user permission.
- Add **Mark all unseen** to an additional-actions menu next to **Mark all seen**,
  so users can explicitly reset previously imported uploads without deleting
  and re-adding channels.
- Center the empty-state message vertically and horizontally within the
  available upload-list region, rather than leaving it near the footer.
- Add an executable regression test for the actual ingest decisions, replay
  deduplication, preservation of seen statuses, and bulk reset.
- No SQLite schema migration or changes to channel identities. Plasma runtime
  verification of these changes is still pending.

## v0.1.0-dev9 — 2026-10-22

- Fix an indefinitely displayed "Checking all followed channels…" footer after
  pressing Refresh. The earlier implementation set a static status message
  without any completion handler, even when all feeds finished successfully.
- Track manual refreshes across the entire requested set of channels, including
  checks still queued by the staggered scheduler. Show the number remaining.
- Complete each requested channel on feed success, error, request timeout, or
  channel removal. Preserve the pending state when a channel ID is corrected
  during recovery; background refreshes remain independent.
- Automatically clear the refresh indicator on success. On partial failure,
  show a concise error summary and leave per-channel errors visible in Channels.
- Disable duplicate manual refresh clicks while a refresh is running.
- Keep the same SQLite schema, channel subscriptions, and seen/unseen history.

## v0.1.0-dev8 — 2026-10-22

- Fix the right-edge collision between the video list's vertical scrollbar and
  the per-video Seen checkbox. Reserve the attached scrollbar's actual width
  plus three KDE small-spacing units in each upload delegate. Keep the scrollbar
  interactive and within its existing scroll area.
- Read XML namespace declarations from Qt's reduced DOM where available.
  Recognize alternate prefix spellings for the standard Atom, YouTube and Media
  RSS namespace URIs, while rejecting elements from unrelated namespaces.
  Retain standard-prefix compatibility for Qt variants that do not surface
  XML namespace declarations in their limited DOM API.
- Prefer the feed-supplied Media RSS thumbnail URL when it is on a known
  YouTube image host over HTTPS. Continue generating the prior `mqdefault.jpg`
  URL when thumbnail metadata is unavailable or unsuitable.
- Expand regression tests for scrollbar spacing, alternate XML namespace
  prefixes, wrong-namespace elements, Media RSS thumbnails, and fallback
  behavior. No database migration or data reset.
- dev7 seen controls and multi-channel display are confirmed functioning on
  Bazzite; full live-feed and Plasma runtime testing of dev8 remains pending.

## v0.1.0-dev7 — 2026-10-22

- Add an explicit per-upload **Seen** checkbox. Check to mark an upload as seen without opening it; uncheck to flag an older upload as unseen. The existing initial-import-as-seen policy is unchanged.
- Keep video-opening and seen-checkbox hit targets separate, so toggling status does not accidentally open a browser page.
- Add a bidirectional SQLite `setSeenState` method, retaining the same schema and database identity as earlier builds.
- Update the badge and upload appearance immediately; avoid resetting the scroll position for normal seen/unseen changes.
- Extend database and packaging regression tests to cover the per-video toggle and unread counter transitions. Full Plasma interaction still requires desktop verification.

## v0.1.0-dev6 — 2026-10-22

- Fix the real Qwazarr77 feed identity mismatch. YouTube's feed-level `<yt:channelId>` can omit `UC`, while saved channel IDs and video-entry IDs include the prefix. Normalize both representations to a canonical 24-character ID before comparing.
- Cross-check the top-level, Atom `<id>`, and per-video channel IDs when present. Still reject genuinely foreign or malformed feeds rather than importing another creator's videos.
- Add regression tests for the truncated ID and conflicting video-owner IDs. No database schema change, and saved channels can be retried without re-adding them.
- Local tests passed; full Plasma and live YouTube behavior still require desktop verification.

## v0.1.0-dev5 — 2026-10-22

- Fix unreliable `@handle` identity resolution: prefer page-owner canonical `/channel/UC...` and RSS feed metadata, then page-specific metadata. Stop using unrelated generic `"channelId"` values found in YouTube page content.
- If a saved handle resolves to a feed with a different owner ID, re-read the original channel URL; when the authoritative channel ID has changed, migrate the stored channel ID and preserve historical uploads and seen/unseen state. If it cannot be verified, show a diagnostic instead of ingesting a possibly unrelated feed.
- Use a readable handle (for example `@Qwazarr77`) while a channel's actual display name is still being loaded; replace it with the feed-provided channel name on success.
- Add regression tests for HTML pages with unrelated channel IDs, Atom parsing, and SQLite ID migration. No schema or database reset required.
- Still awaiting an end-to-end Plasma/YouTube network test; the fix addresses the identified resolver problem but cannot yet be confirmed on the user's desktop.

## v0.1.0-dev4 — 2026-10-22

- Fixed observed `TypeError: Property 'openDatabaseSync' of object Unknown Type is not a function` when adding a channel. Import `QtQuick.LocalStorage` without alias and invoke the documented `LocalStorage.openDatabaseSync(...)` singleton method.
- Channel input now clears **only after** a channel is successfully stored; unsuccessful asynchronous handle lookups preserve the URL so it can be corrected or retried.
- Added regression checks for the LocalStorage import and channel-input behavior.
- No schema changes, no data reset, no new feature scope. Plasma runtime / real feeds still require validation on Bazzite.

# Changelog

## v0.1.0-dev3 — 2026-10-22

- Corrected Plasma 6 `PlasmoidItem` declarations: `fullRepresentation`, `compactRepresentation`, `toolTipMainText`, and `toolTipSubText` are root-item properties, not `Plasmoid.*` attached properties. Resolves the observed `Cannot assign to non-existent property "fullRepresentation"` startup error in dev2.
- Updated the General configuration page to use a Plasma 6 `KCM.SimpleKCM` root, per KDE migration guidance.
- Changed `resolverDeadline` from a 32-bit `int` to `double` to safely hold epoch timestamps in milliseconds during handle resolution.
- Expanded static package regression checks for Plasma 6 property placement and timestamp types.
- No database schema changes; upgrade retains data.

## v0.1.0-dev2 — 2026-10-22

- Fixed two unqualified `ScrollBar.vertical` attached properties inside the alias-imported Qt Quick Controls module (`main.qml` lines 234 and 351 in dev1), which caused the widget to fail QML component creation.
- No database changes or new features. This build upgrades in place from dev1.


## 0.1.0-dev1 — 2026-10-22 (unreleased)

First test build: Qt 6/Plasma 6 UI, manually curated channel list,
Atom parsing, handle resolution, SQLite storage, seen/unseen logic,
thumbnails, bounded polling scheduler, retries and retention.

Known unverified integration points: live Atom XML parsing by Qt, YouTube
channel-handle page resolution, and Bazzite/Nobara runtime behavior.
