import QtQuick
import QtQuick.LocalStorage

QtObject {
    id: store
    property var database: null

    function initialize() {
        if (database) return;
        database = LocalStorage.openDatabaseSync("YouTubeUploadTracker", "1.0", "Local YouTube upload history", 1000000);
        database.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS channels (id TEXT PRIMARY KEY, title TEXT NOT NULL, source_url TEXT NOT NULL, added_ms INTEGER NOT NULL, initialized INTEGER NOT NULL DEFAULT 0, last_checked_ms INTEGER NOT NULL DEFAULT 0, next_check_ms INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0, last_error TEXT NOT NULL DEFAULT '')");
            tx.executeSql("CREATE TABLE IF NOT EXISTS videos (video_id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, title TEXT NOT NULL, published_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, thumbnail_url TEXT NOT NULL, url TEXT NOT NULL, first_seen_ms INTEGER NOT NULL, seen INTEGER NOT NULL DEFAULT 0)");
            // Tombstones ensure pruning old seen records never causes a repeat alert.
            tx.executeSql("CREATE TABLE IF NOT EXISTS known_ids (video_id TEXT PRIMARY KEY, channel_id TEXT NOT NULL)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS videos_recent ON videos (published_ms DESC, first_seen_ms DESC)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS videos_channel ON videos (channel_id)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS channels_due ON channels (next_check_ms)");
            // Incremental schema migration. These values are diagnostics about
            // the last SUCCESSFUL feed fetch, not an inferred YouTube upload count.
            var columns = tx.executeSql("PRAGMA table_info(channels)");
            var have = ({});
            for (var col = 0; col < columns.rows.length; ++col)
                have[String(columns.rows.item(col).name)] = true;
            if (!have.last_feed_entries)
                tx.executeSql("ALTER TABLE channels ADD COLUMN last_feed_entries INTEGER NOT NULL DEFAULT -1");
            if (!have.last_feed_raw_entries)
                tx.executeSql("ALTER TABLE channels ADD COLUMN last_feed_raw_entries INTEGER NOT NULL DEFAULT -1");
            if (!have.last_feed_added)
                tx.executeSql("ALTER TABLE channels ADD COLUMN last_feed_added INTEGER NOT NULL DEFAULT 0");
        });
    }

    function allChannels() {
        initialize();
        var out = [];
        database.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT c.*, " +
                "(SELECT COUNT(*) FROM videos AS v WHERE v.channel_id=c.id) AS stored_count, " +
                "(SELECT MAX(v.published_ms) FROM videos AS v WHERE v.channel_id=c.id) AS newest_stored_ms " +
                "FROM channels AS c ORDER BY c.title COLLATE NOCASE");
            for (var i = 0; i < rs.rows.length; ++i) out.push(rs.rows.item(i));
        });
        return out;
    }

    function addChannel(id, sourceUrl, displayTitle) {
        initialize();
        var changed = false;
        database.transaction(function(tx) {
            var r = tx.executeSql("INSERT OR IGNORE INTO channels (id,title,source_url,added_ms) VALUES(?,?,?,?)", [id, displayTitle || id, sourceUrl, Date.now()]);
            changed = r.rowsAffected > 0;
        });
        return changed;
    }

    // Correct a channel ID originally resolved from the wrong page metadata.
    // Preserve the subscribed URL, existing history and seen state.
    function rekeyChannel(oldId, newId, displayTitle) {
        initialize();
        if (oldId === newId) return false;
        var changed = false;
        database.transaction(function(tx) {
            var oldRow = tx.executeSql("SELECT id, title FROM channels WHERE id=?", [oldId]);
            if (oldRow.rows.length === 0) return;
            if (tx.executeSql("SELECT 1 FROM channels WHERE id=?", [newId]).rows.length > 0) return;
            var title = oldRow.rows.item(0).title;
            var titleToSave = title === oldId ? displayTitle : title;
            tx.executeSql("UPDATE channels SET id=?, title=?, last_error='', failures=0, next_check_ms=0 WHERE id=?",
                [newId, titleToSave || newId, oldId]);
            tx.executeSql("UPDATE videos SET channel_id=? WHERE channel_id=?", [newId, oldId]);
            tx.executeSql("UPDATE known_ids SET channel_id=? WHERE channel_id=?", [newId, oldId]);
            changed = true;
        });
        return changed;
    }

    function removeChannel(id) {
        initialize();
        database.transaction(function(tx) {
            tx.executeSql("DELETE FROM known_ids WHERE channel_id=?", [id]);
            tx.executeSql("DELETE FROM videos WHERE channel_id=?", [id]);
            tx.executeSql("DELETE FROM channels WHERE id=?", [id]);
            // Removing a channel clears its tombstones so re-adding it rebuilds a baseline.
        });
    }

    function dueChannels(now, maxCount) {
        initialize();
        var out = [];
        database.readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT * FROM channels WHERE next_check_ms<=? ORDER BY next_check_ms, added_ms LIMIT ?", [now, maxCount]);
            for (var i = 0; i < rs.rows.length; ++i) out.push(rs.rows.item(i));
        });
        return out;
    }

    function setDueNowEligible(now) {
        initialize();
        database.transaction(function(tx) {
            // Manual refresh may accelerate healthy channels, never those
            // still observing a persisted backoff after an HTTP failure.
            tx.executeSql("UPDATE channels SET next_check_ms=0 WHERE failures=0 OR next_check_ms<=?", [now]);
        });
    }

    // All videos are unseen on first discovery, including a channel's initial import.
    // Pre-existing seen states in older databases remain unchanged.
    function ingestFeed(id, parsed, nextCheck) {
        initialize();
        var newCount = 0;
        database.transaction(function(tx) {
            var row = tx.executeSql("SELECT initialized FROM channels WHERE id=?", [id]);
            if (row.rows.length === 0) return; // removed while HTTP request was in flight
            var now = Date.now();
            for (var i = 0; i < parsed.entries.length; ++i) {
                var video = parsed.entries[i];
                var known = tx.executeSql("SELECT 1 FROM known_ids WHERE video_id=?", [video.id]);
                if (known.rows.length === 0) {
                    tx.executeSql("INSERT INTO known_ids (video_id, channel_id) VALUES(?,?)", [video.id, id]);
                    tx.executeSql("INSERT INTO videos (video_id,channel_id,title,published_ms,updated_ms,thumbnail_url,url,first_seen_ms,seen) VALUES(?,?,?,?,?,?,?,?,?)",
                        [video.id, id, video.title, video.publishedMs, video.updatedMs, video.thumbnail, video.url, now, 0]);
                    ++newCount;
                } else {
                    tx.executeSql("UPDATE videos SET title=?, updated_ms=?, thumbnail_url=?, url=? WHERE video_id=?",
                        [video.title, video.updatedMs, video.thumbnail, video.url, video.id]);
                }
            }
            var name = parsed.channelName || id;
            tx.executeSql("UPDATE channels SET title=?, initialized=1, last_checked_ms=?, next_check_ms=?, " +
                "failures=0, last_error='', last_feed_entries=?, last_feed_raw_entries=?, last_feed_added=? WHERE id=?",
                [name, now, nextCheck, parsed.entries.length, parsed.rawEntryCount, newCount, id]);
        });
        return newCount;
    }

    function markFailure(id, message, nextCheck) {
        initialize();
        database.transaction(function(tx) {
            tx.executeSql("UPDATE channels SET failures=failures+1, last_error=?, next_check_ms=? WHERE id=?", [message, nextCheck, id]);
        });
    }

    function videos(limit, unreadOnly, onlyChannelId) {
        initialize();
        var out = [];
        database.readTransaction(function(tx) {
            var filters = [], args = [];
            if (unreadOnly) filters.push("v.seen=0");
            if (onlyChannelId) { filters.push("v.channel_id=?"); args.push(onlyChannelId); }
            var query = "SELECT v.* , c.title AS channel_title FROM videos AS v INNER JOIN channels AS c ON c.id=v.channel_id" +
                (filters.length ? " WHERE " + filters.join(" AND ") : "") +
                " ORDER BY v.published_ms DESC, v.first_seen_ms DESC LIMIT ?";
            args.push(limit);
            var rs = tx.executeSql(query, args);
            for (var i = 0; i < rs.rows.length; ++i) out.push(rs.rows.item(i));
        });
        return out;
    }

    function videoTotal(unreadOnly, onlyChannelId) {
        initialize();
        var count = 0;
        database.readTransaction(function(tx) {
            var filters = [], args = [];
            if (unreadOnly) filters.push("v.seen=0");
            if (onlyChannelId) { filters.push("v.channel_id=?"); args.push(onlyChannelId); }
            var sql = "SELECT count(*) AS n FROM videos AS v INNER JOIN channels AS c ON c.id=v.channel_id" +
                (filters.length ? " WHERE " + filters.join(" AND ") : "");
            count = tx.executeSql(sql, args).rows.item(0).n;
        });
        return count;
    }

    function unreadCount() {
        initialize();
        var count = 0;
        database.readTransaction(function(tx) {
            count = tx.executeSql("SELECT count(*) AS n FROM videos WHERE seen=0").rows.item(0).n;
        });
        return count;
    }

    function setSeenState(videoId, isSeen) {
        initialize();
        database.transaction(function(tx) {
            tx.executeSql("UPDATE videos SET seen=? WHERE video_id=?", [isSeen ? 1 : 0, videoId]);
        });
    }

    function setSeen(videoId) {
        setSeenState(videoId, true);
    }

    // Explicit user action; useful for correcting legacy initial imports that
    // were automatically marked seen by early development builds.
    function markAllUnseen() {
        initialize();
        database.transaction(function(tx) {
            tx.executeSql("UPDATE videos SET seen=0 WHERE seen=1");
        });
    }

    function markAllSeen() {
        initialize();
        database.transaction(function(tx) {
            tx.executeSql("UPDATE videos SET seen=1 WHERE seen=0");
        });
    }

    function pruneSeen(maxAgeDays) {
        initialize();
        var cutoff = Date.now() - maxAgeDays * 86400000;
        database.transaction(function(tx) {
            tx.executeSql("DELETE FROM videos WHERE seen=1 AND first_seen_ms<?", [cutoff]);
        });
    }
}
