import QtQuick
import "AtomParser.js" as AtomParser
import "ChannelResolver.js" as Resolver

Item {
    id: engine
    visible: false
    width: 0
    height: 0

    property var store: null
    // Development builds only. Turn off for release: no request/parse logs.
    // Use warning-level logging temporarily in development builds: some Plasma
    // setups disable Qt QML debug-level console.log messages by default.
    // Diagnostic events should appear in plasmashell's journal as YTUPLOAD_DEV15.
    property bool developmentLogging: true

    function debugLog(eventName, channelId, details) {
        if (!developmentLogging) return;
        var suffix = String(details || "").replace(/[^A-Za-z0-9_= .,:\/+-]/g, "_").slice(0, 220);
        console.warn("YTUPLOAD_DEV15 event=" + eventName +
                    " channel=" + String(channelId || "none") +
                    (suffix ? " " + suffix : ""));
    }
    property int refreshMinutes: 15
    property int maxConcurrent: 4
    property int inFlightCount: 0
    property bool resolvingChannel: false
    property var active: ({})
    property var recovering: ({})
    property var resolverRequest: null
    property double resolverDeadline: 0
    property double lastStartMs: 0
    property double lastMaintenanceMs: 0

    // Manual refresh is tracked separately from normal background polling.
    // Every requested channel must finish (success, failure, timeout or
    // removal) before the manual progress indicator disappears.
    property bool manualRefreshActive: false
    property int manualRefreshRemaining: 0
    property int manualRefreshErrors: 0
    property var pendingManualRefresh: ({})
    property int manualRefreshDeferred: 0

    // A conservative service-wide circuit breaker. Use distinct channels,
    // rather than repeated failures of the same feed, as outage evidence.
    // These session-only fields do not change the persisted channel schema.
    property bool upstreamOutageActive: false
    property double upstreamProbeAfterMs: 0
    property string upstreamProbeId: ""
    property int upstreamProbeFailures: 0
    property var recentFeedResults: []

    signal changed()
    signal problem(string text)
    signal channelAdded(string title)
    signal inputError(string message)
    signal manualRefreshFinished(int errorCount, int deferredCount)

    function stableSlot(id, interval) {
        var h = 2166136261;
        for (var i = 0; i < id.length; ++i) {
            h ^= id.charCodeAt(i);
            h = Math.imul(h, 16777619) >>> 0;
        }
        return h % interval;
    }

    function nextCheck(id) {
        var interval = Math.max(5, refreshMinutes) * 60000;
        var now = Date.now();
        var base = Math.floor(now / interval) * interval;
        var due = base + stableSlot(id, interval);
        // Avoid checking the same channel again immediately after a successful fetch.
        while (due < now + 120000) due += interval;
        return due;
    }

    function add(raw) {
        var text = String(raw || "").trim();
        if (!text) {
            inputError("Paste a YouTube channel URL or channel ID.");
            return;
        }
        var id = Resolver.directId(text);
        if (id) {
            saveChannel(id, text);
            return;
        }
        var url = Resolver.resolveHandleUrl(text);
        if (!url) {
            inputError("Use a YouTube @handle URL, /channel/UC… URL, or UC… channel ID.");
            return;
        }
        if (resolvingChannel) {
            inputError("A channel address is already being resolved.");
            return;
        }
        resolvingChannel = true;
        inputError("");
        var xhr = new XMLHttpRequest();
        resolverRequest = xhr;
        resolverDeadline = Date.now() + 15000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || resolverRequest !== xhr) return;
            resolverRequest = null;
            resolvingChannel = false;
            if (xhr.status !== 200) {
                inputError("Could not read this channel page (HTTP " + xhr.status + "). Try its /channel/UC… link.");
                return;
            }
            var resolved = Resolver.idFromHtml(xhr.responseText);
            if (!resolved) {
                inputError("Could not identify this channel. Try its /channel/UC… URL instead.");
                return;
            }
            saveChannel(resolved, url);
        };
        try {
            xhr.open("GET", url, true);
            xhr.send();
        } catch(e) {
            resolverRequest = null;
            resolvingChannel = false;
            inputError("Channel lookup failed: " + e);
        }
    }

    function saveChannel(id, sourceUrl) {
        try {
            if (!store.addChannel(id, sourceUrl, Resolver.displayLabel(sourceUrl, id))) {
                inputError("This channel is already being followed.");
                return;
            }
            inputError("");
            channelAdded(Resolver.displayLabel(sourceUrl, id));
            changed();
            // Due immediately: the scheduler fetches the channel's baseline entries.
            tick();
        } catch(e) {
            inputError("Could not save channel: " + e);
        }
    }

    function finishManualRefreshChannel(id, failed, deferred) {
        if (!manualRefreshActive || !pendingManualRefresh[id]) return;
        delete pendingManualRefresh[id];
        if (failed) manualRefreshErrors++;
        if (deferred) manualRefreshDeferred++;
        manualRefreshRemaining--;
        if (manualRefreshRemaining <= 0) {
            manualRefreshRemaining = 0;
            manualRefreshActive = false;
            manualRefreshFinished(manualRefreshErrors, manualRefreshDeferred);
        }
    }

    function rekeyManualRefreshChannel(oldId, newId) {
        if (!manualRefreshActive || !pendingManualRefresh[oldId]) return;
        delete pendingManualRefresh[oldId];
        pendingManualRefresh[newId] = true;
    }

    function forgetChannel(id) {
        // An in-flight request will complete harmlessly after deletion.
        store.removeChannel(id);
        finishManualRefreshChannel(id, false, false);
        changed();
    }

    // Never turn a manual refresh into an override of an existing failure
    // cooldown. The one allowed exception is a channel already being fetched.
    function refreshAll() {
        if (manualRefreshActive) return;
        var channels = store.allChannels();
        if (upstreamOutageActive) {
            debugLog("MANUAL_DEFER", "none", "outage=1 deferred=" + channels.length);
            manualRefreshFinished(0, channels.length);
            return;
        }
        var now = Date.now();
        pendingManualRefresh = ({});
        manualRefreshErrors = 0;
        manualRefreshDeferred = 0;
        for (var i = 0; i < channels.length; ++i) {
            var c = channels[i];
            if ((Number(c.failures) > 0 && Number(c.next_check_ms) > now) &&
                    !active[c.id] && !recovering[c.id]) {
                manualRefreshDeferred++;
            } else {
                pendingManualRefresh[c.id] = true;
            }
        }
        manualRefreshRemaining = Object.keys(pendingManualRefresh).length;
        manualRefreshActive = manualRefreshRemaining > 0;
        if (!manualRefreshActive) {
            debugLog("MANUAL_DEFER", "none", "cooldown_deferred=" + manualRefreshDeferred);
            manualRefreshFinished(0, manualRefreshDeferred);
            return;
        }
        try {
            store.setDueNowEligible(now);
            debugLog("MANUAL_START", "none", "queued=" + manualRefreshRemaining +
                     " cooldown_deferred=" + manualRefreshDeferred);
            tick();
        } catch (e) {
            manualRefreshActive = false;
            manualRefreshRemaining = 0;
            pendingManualRefresh = ({});
            problem("Could not start refresh: " + String(e));
        }
    }

    // Detect probable widespread feed-service failures, not single missing
    // channels. Only count actual HTTP statuses, within a rolling 3 minutes.
    // Dedupe by channel so retries cannot manufacture outage evidence.
    function observeFeedStatus(id, status) {
        if (upstreamOutageActive || status <= 0) return;
        var now = Date.now();
        var recent = recentFeedResults.filter(function(r) { return now - r.when <= 180000 && r.id !== id; });
        recent.push({ id: id, when: now, bad: status === 404 || status === 429 || status >= 500 });
        recentFeedResults = recent;
        var failures = recent.filter(function(r) { return r.bad; }).length;
        if (recent.length >= 4 && failures >= 4 && failures / recent.length >= 0.75)
            enterUpstreamOutage(recent.length, failures);
    }

    function scheduleOutageProbe() {
        var delay = Math.min(3600000, 600000 * Math.pow(2, Math.min(3, upstreamProbeFailures)));
        upstreamProbeAfterMs = Date.now() + delay;
        debugLog("OUTAGE_PROBE_SCHEDULE", "none", "delay_ms=" + delay);
    }

    function enterUpstreamOutage(sampleCount, failedCount) {
        if (upstreamOutageActive) return;
        upstreamOutageActive = true;
        upstreamProbeId = "";
        upstreamProbeFailures = 0;
        scheduleOutageProbe();
        debugLog("OUTAGE_ENTER", "none", "channels=" + sampleCount + " failed=" + failedCount);
        // Any queued manual channels that have not started must be completed
        // as deferred, otherwise Refresh could stay busy forever.
        var pending = Object.keys(pendingManualRefresh);
        for (var i = 0; i < pending.length; ++i) {
            var id = pending[i];
            if (!active[id] && !recovering[id])
                finishManualRefreshChannel(id, false, true);
        }
    }

    function failOutageProbe(id) {
        if (!upstreamOutageActive || upstreamProbeId !== id) return;
        upstreamProbeId = "";
        upstreamProbeFailures++;
        scheduleOutageProbe();
        debugLog("OUTAGE_PROBE_FAILED", id, "consecutive=" + upstreamProbeFailures);
    }

    function completeOutageProbe(id) {
        if (!upstreamOutageActive || upstreamProbeId !== id) return;
        upstreamOutageActive = false;
        upstreamProbeId = "";
        upstreamProbeAfterMs = 0;
        upstreamProbeFailures = 0;
        recentFeedResults = [];
        debugLog("OUTAGE_RECOVERED", id, "feed_parse=ok");
    }

    function failure(id, detail, httpStatus) {
        var current = store.allChannels();
        var failures = 0;
        for (var i = 0; i < current.length; ++i) {
            if (current[i].id === id) { failures = Number(current[i].failures); break; }
        }
        var delay = Math.min(3600000, 300000 * Math.pow(2, Math.min(4, failures)));
        debugLog("FETCH_ERROR", id, "reason=" + String(detail) + " backoff_ms=" + delay);
        store.markFailure(id, detail, Date.now() + delay);
        problem("Could not update a channel: " + detail);
        changed();
        finishManualRefreshChannel(id, true, false);
        if (upstreamProbeId === id) failOutageProbe(id);
        else if (httpStatus !== undefined) observeFeedStatus(id, httpStatus);
    }

    // If the feed rejects the ID we extracted from a handle page, read that
    // exact page again and use only page-owner metadata. Never import a feed
    // whose identity differs from the requested channel: that could show a
    // completely different creator's videos.
    function verifyAfterMismatch(channel, feedId) {
        var oldId = channel.id;
        var source = Resolver.resolveHandleUrl(channel.source_url);
        var mismatch = "Saved " + oldId + ", feed " + feedId + ".";
        if (!source) {
            failure(oldId, "Channel identity mismatch (" + mismatch + ") Re-add using the correct channel URL.");
            return;
        }
        if (recovering[oldId]) return;
        var xhr = new XMLHttpRequest();
        recovering[oldId] = { request: xhr, deadline: Date.now() + 15000 };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !recovering[oldId] || recovering[oldId].request !== xhr) return;
            delete recovering[oldId];
            if (xhr.status !== 200) {
                failure(oldId, "Channel identity mismatch; address recheck returned HTTP " + xhr.status);
                tick();
                return;
            }
            try {
                var candidate = Resolver.idFromHtml(xhr.responseText);
                if (candidate && candidate !== oldId && store.rekeyChannel(oldId, candidate, Resolver.displayLabel(source, candidate))) {
                    debugLog("CHANNEL_RECOVERED", candidate, "previous=" + oldId);
                    rekeyManualRefreshChannel(oldId, candidate);
                    changed();
                    tick(); // now fetch the corrected feed, without clearing user data
                    return;
                }
                failure(oldId, "Channel identity mismatch (" + mismatch + ") Could not verify a replacement ID from the channel page.");
            } catch (e) {
                failure(oldId, "Channel address recheck failed: " + String(e));
            }
            tick();
        };
        try {
            xhr.open("GET", source, true);
            xhr.send();
        } catch (e) {
            delete recovering[oldId];
            failure(oldId, "Channel address recheck failed: " + String(e));
        }
    }

    function startFeed(channel, isProbe) {
        var id = channel.id;
        if (active[id]) return;
        var xhr = new XMLHttpRequest();
        active[id] = { request: xhr, deadline: Date.now() + 15000, probe: !!isProbe };
        inFlightCount++;
        lastStartMs = Date.now();
        debugLog("FETCH_START", id, isProbe ? "probe=1" : "");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !active[id] || active[id].request !== xhr) return;
            delete active[id];
            inFlightCount--;
            try {
                if (xhr.status !== 200) {
                    failure(id, "HTTP " + xhr.status, xhr.status);
                } else {
                    var xml = xhr.responseXML;
                    if (!xml) throw new Error("Response was not valid XML");
                    var parsed = AtomParser.parseAtom(xml);
                    var d = parsed.diagnostics || {};
                    debugLog("PARSE_RESULT", id, "raw=" + parsed.rawEntryCount +
                             " accepted=" + parsed.entries.length +
                             " yt_video_ids=" + (d.videoTagIds || 0) +
                             " atom_fallback_ids=" + (d.atomFallbackIds || 0) +
                             " stripped_prefix=" + (d.strippedPrefixFields || 0) +
                             " missing_ids=" + (d.missingIds || 0) +
                             " invalid_ids=" + (d.invalidIds || 0));
                    if (parsed.rawEntryCount > 0 && parsed.entries.length === 0)
                        debugLog("PARSE_EMPTY_SAMPLE", id, "fields=" + (d.firstEntryFields || "none"));
                    // A valid XML response can still contain video entries we
                    // failed to parse. Do not silently report it as a success.
                    if (parsed.rawEntryCount > 0 && parsed.entries.length === 0)
                        throw new Error("Feed contains " + parsed.rawEntryCount + " entries, but none could be parsed.");
                    if (parsed.channelId && parsed.channelId !== id) {
                        debugLog("CHANNEL_MISMATCH", id, "feed_channel=" + parsed.channelId);
                        if (isProbe) failOutageProbe(id);
                        verifyAfterMismatch(channel, parsed.channelId);
                    } else {
                        var added = store.ingestFeed(id, parsed, nextCheck(id));
                        debugLog("FETCH_OK", id, "raw=" + parsed.rawEntryCount +
                                 " accepted=" + parsed.entries.length + " added=" + added);
                        changed();
                        finishManualRefreshChannel(id, false, false);
                        if (isProbe) completeOutageProbe(id);
                        else observeFeedStatus(id, 200);
                    }
                }
            } catch(e) {
                failure(id, String(e));
            }
            tick();
        };
        try {
            xhr.open("GET", "https://www.youtube.com/feeds/videos.xml?channel_id=" + id, true);
            xhr.responseType = "document";
            xhr.send();
        } catch(e) {
            delete active[id];
            inFlightCount--;
            failure(id, String(e));
        }
    }

    function tick() {
        if (!store) return;
        var now = Date.now();
        if (resolverRequest && now > resolverDeadline) {
            var old = resolverRequest;
            resolverRequest = null;
            resolvingChannel = false;
            old.abort();
            inputError("Channel lookup timed out. Try its /channel/UC… URL.");
        }
        var ids = Object.keys(active);
        for (var i = 0; i < ids.length; ++i) {
            var obj = active[ids[i]];
            if (obj && now > obj.deadline) {
                delete active[ids[i]];
                inFlightCount--;
                obj.request.abort();
                failure(ids[i], "Request timed out");
            }
        }
        var recoveringIds = Object.keys(recovering);
        for (var r = 0; r < recoveringIds.length; ++r) {
            var item = recovering[recoveringIds[r]];
            if (item && now > item.deadline) {
                delete recovering[recoveringIds[r]];
                item.request.abort();
                failure(recoveringIds[r], "Channel address recheck timed out");
            }
        }
        if (now - lastMaintenanceMs > 86400000) {
            store.pruneSeen(90);
            lastMaintenanceMs = now;
        }
        if (inFlightCount >= maxConcurrent || now - lastStartMs < 450) return;
        var channels = store.dueChannels(now, 64);
        if (upstreamOutageActive) {
            // One live-feed probe at a time. Honor BOTH the outage delay and
            // each channel's persisted backoff; do not force a cooled-down ID.
            if (upstreamProbeId || now < upstreamProbeAfterMs) return;
            for (var p = 0; p < channels.length; ++p) {
                if (!active[channels[p].id] && !recovering[channels[p].id]) {
                    upstreamProbeId = channels[p].id;
                    debugLog("OUTAGE_PROBE_START", upstreamProbeId, "");
                    startFeed(channels[p], true);
                    break;
                }
            }
            return;
        }
        for (var j = 0; j < channels.length; ++j) {
            if (!active[channels[j].id] && !recovering[channels[j].id]) {
                startFeed(channels[j], false);
                break; // one new request per scheduler tick: natural spreading
            }
        }
    }

    Timer { interval: 500; running: true; repeat: true; onTriggered: engine.tick() }
}
