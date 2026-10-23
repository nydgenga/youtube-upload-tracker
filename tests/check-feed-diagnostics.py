from pathlib import Path
import sqlite3, tempfile, re
root=Path(__file__).resolve().parents[1]
store=(root/'package/contents/ui/UploadStore.qml').read_text()
engine=(root/'package/contents/ui/UploadEngine.qml').read_text()
parser=(root/'package/contents/ui/AtomParser.js').read_text()
ui=(root/'package/contents/ui/main.qml').read_text()
# Database must be opened without modifying the filename or schema version.
assert 'LocalStorage.openDatabaseSync("YouTubeUploadTracker", "1.0"' in store
columns=('last_feed_entries','last_feed_raw_entries','last_feed_added')
for column in columns:
    assert 'if (!have.'+column+')' in store
    assert 'ADD COLUMN '+column+' INTEGER NOT NULL DEFAULT' in store
    assert column+'=?' in store
assert 'PRAGMA table_info(channels)' in store
assert 'rawEntryCount++' in parser
assert 'parsed.rawEntryCount > 0 && parsed.entries.length === 0' in engine
assert 'selectedChannelId' in ui and 'Show all channels' in ui
assert 'Feed: %1/%2 entries' in ui
assert 'stored_count' in store
assert 'function videos(limit, unreadOnly, onlyChannelId)' in store
assert 'function videoTotal(unreadOnly, onlyChannelId)' in store
# Model an existing dev10 DB upgraded twice, and ensure data/seen states are untouched.
with tempfile.TemporaryDirectory() as d:
    db=sqlite3.connect(str(Path(d)/'test.db'))
    db.executescript('''
    CREATE TABLE channels (id TEXT PRIMARY KEY, title TEXT NOT NULL, source_url TEXT NOT NULL, added_ms INTEGER NOT NULL, initialized INTEGER NOT NULL DEFAULT 0, last_checked_ms INTEGER NOT NULL DEFAULT 0, next_check_ms INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0, last_error TEXT NOT NULL DEFAULT '');
    CREATE TABLE videos (video_id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, title TEXT NOT NULL, published_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, thumbnail_url TEXT NOT NULL, url TEXT NOT NULL, first_seen_ms INTEGER NOT NULL, seen INTEGER NOT NULL DEFAULT 0);
    ''')
    db.execute("INSERT INTO channels (id,title,source_url,added_ms) VALUES('UC1','Kitboga','https://example.com',10)")
    db.execute("INSERT INTO channels (id,title,source_url,added_ms) VALUES('UC2','Type2Productions','https://example.com',10)")
    db.execute("INSERT INTO videos VALUES ('abcdefghijk','UC1','Example',100,100,'https://a','https://b',10,1)")
    db.execute("INSERT INTO videos VALUES ('123456789ab','UC2','Example2',50,50,'https://a','https://b',10,0)")
    for _ in range(2):
        present={row[1] for row in db.execute('PRAGMA table_info(channels)')}
        for col in columns:
            if col not in present:
                default='-1' if col != 'last_feed_added' else '0'
                db.execute(f'ALTER TABLE channels ADD COLUMN {col} INTEGER NOT NULL DEFAULT {default}')
        db.commit()
    assert {row[1] for row in db.execute('PRAGMA table_info(channels)')} >= set(columns)
    assert list(db.execute('SELECT seen FROM videos ORDER BY video_id')) == [(0,),(1,)]
    db.execute('UPDATE channels SET last_feed_entries=?, last_feed_raw_entries=?, last_feed_added=? WHERE id=?',(15,15,15,'UC1'))
    assert db.execute('SELECT last_feed_entries,last_feed_added FROM channels WHERE id=?',('UC1',)).fetchone() == (15,15)
    query='''SELECT c.*, (SELECT COUNT(*) FROM videos v WHERE v.channel_id=c.id) stored_count FROM channels c ORDER BY c.title'''
    assert len(db.execute(query).fetchall())==2
    for channel, expected in [('UC1','abcdefghijk'),('UC2','123456789ab')]:
        rows=db.execute('SELECT video_id FROM videos WHERE channel_id=? ORDER BY published_ms DESC LIMIT 50',(channel,)).fetchall()
        assert rows==[(expected,)]
    db.close()
print('PASS feed diagnostics, old SQLite database migration, repeat migration, seen statuses, channel filter')
