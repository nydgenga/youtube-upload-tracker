import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const dir = new URL('../package/contents/ui/', import.meta.url);
const load = name => {
    let code = fs.readFileSync(new URL(name, dir), 'utf8').replace(/^\.pragma library\s*/m, '');
    const sandbox = {};
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox, { filename: name });
    return sandbox;
};
const resolver = load('ChannelResolver.js');
const parser = load('AtomParser.js');
const example = 'UC_x5XG1OV2P6uZZ5FSM9Ttw';
assert.equal(resolver.directId(example), example);
assert.equal(resolver.directId('https://www.youtube.com/channel/' + example), example);
assert.equal(resolver.directId('https://www.youtube.com/feeds/videos.xml?channel_id=' + example), example);
assert.equal(resolver.resolveHandleUrl('https://www.youtube.com/@MyVideos/videos'), 'https://www.youtube.com/@MyVideos');
assert.equal(resolver.resolveHandleUrl('@MyVideos'), 'https://www.youtube.com/@MyVideos');
assert.equal(resolver.resolveHandleUrl('https://evil.example/@MyVideos'), '');
assert.equal(resolver.idFromHtml('<meta itemprop="channelId" content="' + example + '">'), example);
assert.equal(resolver.idFromHtml('{"externalId":"' + example + '"}'), example);
const unrelated = 'UC0YpCsvynhbjTzrS9AIRjQ';
const intended = 'UCaaaaaaaaaaaaaaaaaaaaaa';
assert.equal(intended.length, 24);
// A YouTube channel page may mention other channels before the page owner's
// metadata. Never use an arbitrary "channelId" key or first channel URL.
const simulatedPage = '<script>{"channelId":"' + unrelated + '","shelf":{"url":"https://www.youtube.com/channel/' + unrelated + '"}}</script>' +
    '<meta property="og:site_name" content="YouTube">' +
    '<link href="https://www.youtube.com/channel/' + intended + '" rel="canonical">' +
    '<link type="application/rss+xml" href="https://www.youtube.com/feeds/videos.xml?channel_id=' + intended + '" rel="alternate">';
assert.equal(resolver.idFromHtml(simulatedPage), intended);
assert.equal(resolver.idFromHtml('<script>{"channelId":"' + unrelated + '"}</script>'), '');
assert.equal(resolver.idFromHtml('<link rel="alternate" type="application/rss+xml" href="https://www.youtube.com/feeds/videos.xml?channel_id=' + intended + '">'), intended);
assert.equal(resolver.idFromHtml('<meta content="' + intended + '" itemprop="channelId">'), intended);
assert.equal(resolver.displayLabel('https://www.youtube.com/@Qwazarr77', unrelated), '@Qwazarr77');
assert.equal(resolver.displayLabel('https://www.youtube.com/channel/' + unrelated, unrelated), unrelated);

const node = (name, value = null, children = []) => {
    const n = {nodeType: value !== null ? 3 : 1, nodeName: name, nodeValue: value, firstChild: null, nextSibling: null};
    if (children.length) {
        n.firstChild = children[0];
        for (let i = 0; i < children.length - 1; ++i) children[i].nextSibling = children[i + 1];
    }
    return n;
};
const text = (name, s) => node(name, null, [node('#text', s)]);
const videoId = 'abcdefghijk';
const feed = node('feed', null, [
    text('yt:channelId', example),
    node('author', null, [text('name', 'Demo Channel')]),
    node('entry', null, [text('yt:videoId', videoId), text('title', 'A Short & a Stream'),
        text('published', '2026-10-22T10:04:00+00:00'), text('updated', '2026-10-22T10:05:00+00:00')]),
    node('entry', null, [text('yt:videoId', 'invalid-id'), text('title', 'Invalid')])
]);
const parsed = parser.parseAtom({documentElement: feed});
assert.equal(parsed.channelId, example);
assert.equal(parsed.channelName, 'Demo Channel');
assert.equal(parsed.entries.length, 1);
assert.equal(parsed.rawEntryCount, 2);
assert.equal(parsed.entries[0].id, videoId);
assert.equal(parsed.entries[0].title, 'A Short & a Stream');
assert.equal(parsed.entries[0].url, 'https://www.youtube.com/watch?v=' + videoId);
// A real namespace-aware feed can use *different prefixes* for the same
// YouTube/Media RSS URIs. Qt supplies nodeName and attributes, not namespaceURI.
const withAttributes = (n, map) => {
    const list = Object.entries(map).map(([name, value]) => ({name, value, nodeName: name, nodeValue: value}));
    n.attributes = {length: list.length, item: i => list[i], getNamedItem: name => list.find(a => a.name === name) || null};
    return n;
};
const withParents = (n, parent = null) => {
    n.parentNode = parent;
    for (let c = n.firstChild; c; c = c.nextSibling) withParents(c, n);
    return n;
};
const url = 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg';
const namespaced = withAttributes(node('feed', null, [
    text('tube:channelId', example.slice(2)),
    node('author', null, [text('name', 'Renamed Prefix Demo')]),
    node('entry', null, [
        text('tube:channelId', example), text('tube:videoId', videoId),
        text('title', 'With real Media RSS thumbnail'),
        node('mrss:group', null, [withAttributes(node('mrss:thumbnail'), {url})])
    ])
]), {
    'xmlns': 'http://www.w3.org/2005/Atom',
    'xmlns:tube': 'http://www.youtube.com/xml/schemas/2015',
    'xmlns:mrss': 'http://search.yahoo.com/mrss/'
});
const prefixed = parser.parseAtom({documentElement: withParents(namespaced)});
assert.equal(prefixed.channelId, example);
assert.equal(prefixed.channelName, 'Renamed Prefix Demo');
assert.equal(prefixed.entries.length, 1);
assert.equal(prefixed.rawEntryCount, 1);
assert.equal(prefixed.entries[0].thumbnail, url);
assert.equal(parser.safeThumbnailUrl('http://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg'), '');
assert.equal(parser.safeThumbnailUrl('https://untrusted.example/vi/abcdefghijk/hqdefault.jpg'), '');

// Verify the fallback when Media RSS thumbnail metadata is missing/unsafe.
const badThumb = withAttributes(node('mrss:thumbnail'), {url: 'https://untrusted.example/test.png'});
const fallbackFeed = withAttributes(node('feed', null, [
    text('tube:channelId', example.slice(2)),
    node('entry', null, [text('tube:videoId', videoId), node('mrss:group', null, [badThumb])])
]), {'xmlns': parser.NS_ATOM, 'xmlns:tube': parser.NS_YOUTUBE, 'xmlns:mrss': parser.NS_MEDIA});
assert.equal(parser.parseAtom({documentElement: withParents(fallbackFeed)}).entries[0].thumbnail,
    'https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg');
// A similarly named element from a different namespace is NOT a yt:videoId.
const hostileFeed = withAttributes(node('feed', null, [
    text('id', 'yt:channel:' + example),
    node('entry', null, [text('other:videoId', videoId)])
]), {'xmlns': parser.NS_ATOM, 'xmlns:other': 'https://example.org/wrong'});
assert.equal(parser.parseAtom({documentElement: withParents(hostileFeed)}).entries.length, 0);
assert.throws(() => parser.parseAtom({documentElement: withParents(withAttributes(
    node('feed', null, [text('yt:channelId', example)]), {'xmlns': 'https://example.org/not-atom', 'xmlns:yt': parser.NS_YOUTUBE}
))}), /invalid Atom/);

// Regression: a real channel Atom feed can omit "UC" at feed level.
const qwazarr = 'UC0YpCsvynhbjTzrS9AIRjiQ';
assert.equal(qwazarr.length, 24);
assert.equal(parser.normalizeChannelId(qwazarr.slice(2)), qwazarr);
assert.equal(parser.normalizeChannelId(qwazarr), qwazarr);
assert.equal(parser.normalizeChannelId('invalid'), '');
const truncatedFeed = node('feed', null, [
    text('id', 'yt:channel:' + qwazarr),
    text('yt:channelId', qwazarr.slice(2)),
    text('title', 'Qwazar77'),
    node('entry', null, [text('yt:channelId', qwazarr), text('yt:videoId', '0123456789A'),
        text('title', 'Test upload'), text('published', '2026-10-22T12:00:00+00:00')])
]);
const corrected = parser.parseAtom({documentElement: truncatedFeed});
assert.equal(corrected.channelId, qwazarr);
assert.equal(corrected.channelName, 'Qwazar77');
assert.equal(corrected.entries.length, 1);
assert.equal(parser.parseAtom({documentElement: node('feed', null, [text('id', 'yt:channel:' + qwazarr)])}).channelId, qwazarr);
assert.equal(parser.parseAtom({documentElement: node('feed', null, [text('yt:channelId', qwazarr)])}).channelId, qwazarr);
// These must continue to be rejected as genuinely inconsistent feeds.
assert.throws(() => parser.parseAtom({documentElement: node('feed', null, [
    text('yt:channelId', qwazarr.slice(2)),
    node('entry', null, [text('yt:channelId', intended), text('yt:videoId', 'abcdefghijk')])
])}), /different channel/);
assert.throws(() => parser.parseAtom({documentElement: node('feed', null, [
    text('id', 'yt:channel:' + intended), text('yt:channelId', qwazarr.slice(2))
])}), /Conflicting feed/);
assert.throws(() => parser.parseAtom({documentElement: node('feed', null, [text('title', 'Unknown')])}), /verifiable channel ID/);
assert.throws(() => parser.parseAtom(null));
for (const name of ['ChannelResolver.js', 'AtomParser.js']) console.log('PASS', name);
console.log('PASS Qt reduced-DOM Atom parsing and channel normalization');
