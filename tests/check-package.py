from pathlib import Path
import json, re, sqlite3, tempfile, xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1] / 'package'
meta = json.loads((root / 'metadata.json').read_text())
assert meta['KPackageStructure'] == 'Plasma/Applet'
assert meta['X-Plasma-API-Minimum-Version'] == '6.0'
assert meta['KPlugin']['Id'] == 'com.nydgenga.youtubeuploads'
ET.parse(root / 'contents/config/main.xml')
qml_files = list(root.rglob('*.qml'))
main_qml = (root / "contents/ui/main.qml").read_text()
# Regression: QtQuick.Controls is imported as Controls. The attached type
# name needs the same prefix or QML reports "Non-existent attached object".
assert main_qml.count("Controls.ScrollBar.vertical: Controls.ScrollBar") == 2
assert 'Controls.ScrollBar.vertical: Controls.ScrollBar { id: uploadScrollBar }' in main_qml
assert 'videoList.width - uploadScrollBar.width - Kirigami.Units.smallSpacing * 3' in main_qml
assert 'width: videoList.width - 8' not in main_qml
assert not re.search(r"(?<![\w.])ScrollBar\.vertical\s*:", main_qml)
assert len(qml_files) >= 4
# Plasma 6 migration: on a PlasmoidItem root, the visual representation
# and tooltip properties belong directly to the item, not Plasmoid.*.
# See KDE's Plasma 6 porting guide.
assert re.search(r'\bPlasmoidItem\s*\{', main_qml)
for key in ('compactRepresentation', 'fullRepresentation', 'toolTipMainText', 'toolTipSubText'):
    assert len(re.findall(r'(?m)^\s*' + key + r'\s*:', main_qml)) == 1, key
    assert not re.search(r'Plasmoid\.' + key + r'\s*:', main_qml), key
assert 'Plasmoid.icon:' in main_qml  # applet metadata still is an attached property
# Unix timestamps in milliseconds exceed signed 32-bit QML integers.
engine = (root / 'contents/ui/UploadEngine.qml').read_text()
assert 'property double resolverDeadline: 0' in engine
assert 'function verifyAfterMismatch(channel, feedId)' in engine
atom_parser = (root / 'contents/ui/AtomParser.js').read_text()
assert 'function normalizeChannelId(raw)' in atom_parser
assert 'function declaredNamespace(node, prefix)' in atom_parser
assert 'function safeThumbnailUrl(rawUrl)' in atom_parser
assert 'child(mediaGroup, "thumbnail", NS_MEDIA)' in atom_parser
assert 'var channelId = normalizeChannelId(rawFeedId)' in atom_parser
assert 'entryId !== channelId' in atom_parser
assert 'Feed did not provide a verifiable channel ID.' in atom_parser
assert 'Resolver.idFromHtml(xhr.responseText)' in engine
assert 'store.rekeyChannel(oldId, candidate,' in engine
assert '&& !recovering[channels[j].id]' in engine
assert 'function rekeyChannel(oldId, newId, displayTitle)' in (root / 'contents/ui/UploadStore.qml').read_text()
assert 'Resolver.displayLabel(c.source_url, c.id)' in main_qml
# Per-video seen control must be separate from the browser-opening delegate.
# In the normal feed, update the ListModel role in place to preserve scrolling.
assert re.search(r'function setVideoSeenState\(videoId, isSeen\)', main_qml)
assert 'dataStore.setSeenState(videoId, isSeen)' in main_qml
assert 'videoItems.setProperty(i, "wasSeen", isSeen)' in main_qml
assert 'unseen = dataStore.unreadCount()' in main_qml
assert re.search(r'delegate:\s*Item\s*\{[\s\S]{0,250}?width:\s*Math\.max\(0, videoList\.width - uploadScrollBar\.width', main_qml)
assert re.search(r'Controls\.ItemDelegate\s*\{[^}]*onClicked:\s*root\.openVideo\(model\.videoId, model\.videoUrl\)', main_qml)
assert re.search(r'Controls\.CheckBox\s*\{[^}]*text:\s*i18n\("Seen"\)[^}]*onToggled:\s*root\.setVideoSeenState\(model\.videoId, checked\)', main_qml, re.S)
assert 'function setSeenState(videoId, isSeen)' in (root / 'contents/ui/UploadStore.qml').read_text()
assert 'UPDATE videos SET seen=? WHERE video_id=?' in (root / 'contents/ui/UploadStore.qml').read_text()



# Plasma 6 settings pages must use a KCM root component.
settings_qml = (root / "contents/ui/configGeneral.qml").read_text()
assert 'import org.kde.kcmutils as KCM' in settings_qml
assert re.search(r'\bKCM\.SimpleKCM\s*\{', settings_qml)

# Validate SQLite DDL against sqlite3, and basic index functionality.
store = (root / 'contents/ui/UploadStore.qml').read_text()
statements = re.findall(r'tx\.executeSql\("(CREATE [^"\n]+)"\);', store)
assert len(statements) == 6, len(statements)
with tempfile.TemporaryDirectory() as d:
    db = sqlite3.connect(Path(d)/'test.db')
    for sql in statements:
        db.execute(sql)
    db.execute("INSERT INTO channels (id,title,source_url,added_ms) VALUES(?,?,?,?)",
               ['UC_x5XG1OV2P6uZZ5FSM9Ttw','Demo','https://www.youtube.com',100])
    db.execute("INSERT INTO known_ids (video_id,channel_id) VALUES(?,?)",
               ['abcdefghijk','UC_x5XG1OV2P6uZZ5FSM9Ttw'])
    db.execute("INSERT INTO videos VALUES(?,?,?,?,?,?,?,?,?)",
               ['abcdefghijk','UC_x5XG1OV2P6uZZ5FSM9Ttw','A video',100,100,'https://a','https://b',100,0])
    assert db.execute('SELECT count(*) FROM videos WHERE seen=0').fetchone()[0] == 1
    # Simulate interactive checkbox toggling, including an imported seen
    # video becoming unseen and then returning to seen.
    db.execute('UPDATE videos SET seen=? WHERE video_id=?', [1, 'abcdefghijk'])
    assert db.execute('SELECT count(*) FROM videos WHERE seen=0').fetchone()[0] == 0
    db.execute('UPDATE videos SET seen=? WHERE video_id=?', [0, 'abcdefghijk'])
    assert db.execute('SELECT count(*) FROM videos WHERE seen=0').fetchone()[0] == 1
    db.execute('UPDATE videos SET seen=1')
    db.execute('DELETE FROM videos WHERE seen=1 AND first_seen_ms<1000')
    assert db.execute('SELECT count(*) FROM videos').fetchone()[0] == 0
    assert db.execute('SELECT count(*) FROM known_ids').fetchone()[0] == 1
    # Simulate migration of the mistaken handle mapping, without losing
    # locally stored uploads or the durable deduplication tombstones.
    old_id = 'UC_x5XG1OV2P6uZZ5FSM9Ttw'
    new_id = 'UCaaaaaaaaaaaaaaaaaaaaaa'
    db.execute('UPDATE channels SET id=?, title=? WHERE id=?', [new_id, '@Qwazarr77', old_id])
    db.execute('UPDATE videos SET channel_id=? WHERE channel_id=?', [new_id, old_id])
    db.execute('UPDATE known_ids SET channel_id=? WHERE channel_id=?', [new_id, old_id])
    assert db.execute('SELECT title FROM channels WHERE id=?', [new_id]).fetchone()[0] == '@Qwazarr77'
    assert db.execute('SELECT channel_id FROM known_ids WHERE video_id=?', ['abcdefghijk']).fetchone()[0] == new_id
    assert db.execute('SELECT count(*) FROM channels WHERE id=?', [old_id]).fetchone()[0] == 0
    db.close()
print('PASS metadata JSON, KConfig XML, SQLite table/index SQL, tombstone behavior')

# Regression: in Qt 6, the imported singleton is named LocalStorage, not
# the bare QML import namespace. A bare SQL.openDatabaseSync() fails at runtime.
assert re.search(r"(?m)^import QtQuick\.LocalStorage\s*$", store)
assert re.search(r"\bLocalStorage\.openDatabaseSync\s*\(", store)
assert not re.search(r"\bSQL\.openDatabaseSync\s*\(", store)
assert not re.search(r"(?m)^import QtQuick\.LocalStorage\s+as\s+", store)
# Preserve input until addChannel really succeeds (including async handle lookup).
assert "onChannelAdded: function(title)" in main_qml
assert re.search(r"onChannelAdded: function\(title\)\s*\{[^}]*channelInput\.clear\(\)", main_qml)
assert main_qml.count("channelInput.clear()") == 1
print('PASS Qt 6 LocalStorage singleton import and asynchronous channel-input retention')

# Regression: a manual refresh must be driven by real scheduler completion,
# not by a static footer message that remains forever after requests finish.
assert 'root.infoMessage = i18n("Checking all followed channels…")' not in main_qml
assert 'onManualRefreshFinished: function(errorCount, deferredCount)' in main_qml
assert 'visible: feedEngine.manualRefreshActive || root.infoMessage.length > 0' in main_qml
assert 'enabled: !feedEngine.manualRefreshActive' in main_qml
assert 'signal manualRefreshFinished(int errorCount, int deferredCount)' in engine
assert 'finishManualRefreshChannel(id, false, false)' in engine
assert 'finishManualRefreshChannel(id, true, false)' in engine
print('PASS manual refresh progress and completion wiring')
