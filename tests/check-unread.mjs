import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const dir = new URL('../package/contents/ui/', import.meta.url);
const source = fs.readFileSync(new URL('UploadStore.qml', dir), 'utf8');
const main = fs.readFileSync(new URL('main.qml', dir), 'utf8');

// Exercise the same ingestFeed function used by the QML storage singleton.
// Implement only the SQL result surface needed to test its actual decisions.
function method(name) {
    const start = source.indexOf('    function ' + name + '(');
    assert.ok(start >= 0);
    const begin = source.indexOf('{', start);
    let level = 0, i = begin;
    for (; i < source.length; ++i) {
        const c = source[i];
        if (c === '{') level++;
        else if (c === '}' && --level === 0) return source.slice(start, i + 1);
    }
    throw new Error('unclosed method ' + name);
}
let channel = {initialized: 0, title: 'Example Channel'};
const known = new Set(), videos = new Map();
const tx = {
    executeSql(sql, params = []) {
        if (sql.startsWith('SELECT initialized FROM channels')) {
            return {rows: {length: 1, item: () => ({initialized: channel.initialized})}};
        }
        if (sql.startsWith('SELECT 1 FROM known_ids')) {
            return {rows: {length: known.has(params[0]) ? 1 : 0}};
        }
        if (sql.startsWith('INSERT INTO known_ids')) { known.add(params[0]); return {}; }
        if (sql.startsWith('INSERT INTO videos')) {
            const [id, cid, title, pub, updated, thumbnail, url, firstSeen, seen] = params;
            videos.set(id, {title, pub, updated, thumbnail, url, firstSeen, seen});
            return {};
        }
        if (sql.startsWith('UPDATE videos SET title=')) {
            const [title, updated, thumbnail, url, id] = params;
            const v = videos.get(id);
            if (v) Object.assign(v, {title, updated, thumbnail, url});
            return {};
        }
        if (sql.startsWith('UPDATE channels SET title=')) {
            channel.initialized = 1;
            channel.title = params[0];
            return {};
        }
        if (sql.startsWith('UPDATE videos SET seen=0 WHERE seen=1')) {
            for (const v of videos.values()) if (v.seen === 1) v.seen = 0;
            return {};
        }
        throw new Error('unexpected SQL: ' + sql);
    }
};
const sandbox = {initialize() {}, database: {transaction(fn) {fn(tx)}}, Date};
vm.createContext(sandbox);
vm.runInContext([method('ingestFeed'),method('markAllUnseen')].join('\n'), sandbox);
const v = (id, title) => ({id, title, publishedMs: 50, updatedMs: 51, thumbnail:'https://example.org/img.jpg', url: 'https://www.youtube.com/watch?v='+id});
const feed = entries => ({entries, channelName:'Example Channel'});
assert.equal(sandbox.ingestFeed('UC123',feed([v('first', 'old upload')]),100),1);
assert.equal(videos.get('first').seen,0,'Initial import MUST be unseen');
assert.equal(channel.initialized,1);
videos.get('first').seen = 1; // user's explicit click/checkbox
assert.equal(sandbox.ingestFeed('UC123',feed([v('first', 'updated title'),v('second','brand new')]),200),1);
assert.equal(videos.get('first').seen,1,'Refetch must preserve existing seen state');
assert.equal(videos.get('first').title,'updated title');
assert.equal(videos.get('second').seen,0,'New upload MUST be unseen');
assert.equal(sandbox.ingestFeed('UC123',feed([v('first','updated title'),v('second','brand new')]),300),0);
assert.equal(videos.size,2,'Refetch must not create duplicates');
sandbox.markAllUnseen();
assert.equal(videos.get('first').seen,0,'Bulk reset must mark prior entries unseen');
assert.equal(videos.get('second').seen,0);
assert.ok(main.includes('anchors.centerIn: parent'), 'Empty state must have centered anchor');
assert.ok(main.includes('root.unreadOnly ? i18n("Nothing unseen.")'), 'Unseen empty text missing');
assert.ok(main.includes('dataStore.markAllUnseen()'), 'Bulk reset action missing');
console.log('PASS initial imports unseen, future uploads unseen, seen-state preservation, bulk reset, centered empty state');
