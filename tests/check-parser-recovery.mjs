import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const parserPath = new URL('../package/contents/ui/AtomParser.js', import.meta.url);
const script = fs.readFileSync(parserPath,'utf8').replace(/^\.pragma library\s*/m,'');
const ctx = vm.createContext({});
vm.runInContext(script, ctx, {filename:'AtomParser.js'});
const cid = 'UC_x5XG1OV2P6uZZ5FSM9Ttw';
const videoA = 'AbC123def45', videoB='z9y8x7w6v5U';
function element(name, children=[], attrs={}) {
  const nn={nodeName:name,nodeType:1,firstChild:null,nextSibling:null,parentNode:null,
     attributes: {length:Object.keys(attrs).length, item:i=>Object.entries(attrs).map(([name,value])=>({name,value}))[i]}};
  if (children.length) {
    nn.firstChild=children[0];
    for(let i=0;i<children.length;i++) {
      children[i].parentNode=nn;
      if(i) children[i-1].nextSibling=children[i];
    }
  }
  return nn;
}
function txt(name, value){return element(name,[{nodeName:'#text',nodeType:3,nodeValue:value,nextSibling:null,firstChild:null}]);}
const atomAttrs={'xmlns':'http://www.w3.org/2005/Atom',
  'xmlns:yt':'http://www.youtube.com/xml/schemas/2015',
  'xmlns:media':'http://search.yahoo.com/mrss/'};
function feed(entries, other=[]) {return {documentElement:element('feed',
  [txt('yt:channelId',cid),txt('title','Test Channel'),...other,...entries],atomAttrs)};}
// Regression: namespace-aware lookup can fail on some Qt reduced DOMs;
// authentic Atom <id> values still identify videos reliably.
let result = ctx.parseAtom(feed([element('entry',[
  txt('id','yt:video:'+videoA),txt('title','A video'),
  txt('published','2026-10-22T12:00:00Z')]) ]));
assert.equal(result.rawEntryCount,1);
assert.equal(result.entries.length,1);
assert.equal(result.entries[0].id,videoA);
assert.equal(result.diagnostics.atomFallbackIds,1);
assert.equal(result.diagnostics.missingIds,0);
// Earlier builds could silently discard these 15 entries; fallback fixes it.
const many=Array.from({length:15},(_,i)=>element('entry',[
    txt('id','yt:video:'+String(i).padStart(11,'0')),txt('title','Video '+i)]));
result=ctx.parseAtom(feed(many));
assert.equal(result.entries.length,15);
assert.equal(result.diagnostics.atomFallbackIds,15);
// Qt reduced DOM can strip yt: from qualified element names, leaving videoId.
result=ctx.parseAtom(feed([element('entry',[
    txt('videoId',videoB),txt('id','yt:video:'+videoB)])]));
assert.equal(result.entries[0].id,videoB);
assert.equal(result.diagnostics.strippedPrefixFields,1);
// Mixed valid and malformed fields: do not discard valid uploads.
result=ctx.parseAtom(feed([element('entry',[
    txt('yt:videoId','bad'),txt('id','yt:video:'+videoA)])]));
assert.equal(result.entries[0].id,videoA);
// Legitimate alternately-prefixed elements work with their declared namespace.
const altAttrs={...atomAttrs,'xmlns:youtube':'http://www.youtube.com/xml/schemas/2015'};
result=ctx.parseAtom({documentElement:element('feed',[txt('youtube:channelId',cid),
    element('entry',[txt('youtube:videoId',videoA)])],altAttrs)});
assert.equal(result.entries[0].id,videoA);
// Explicit foreign namespace videoId is not trusted without a valid Atom id.
result=ctx.parseAtom({documentElement:element('feed',[txt('yt:channelId',cid),
    element('entry',[txt('other:videoId',videoA)])],{
      ...atomAttrs,'xmlns:other':'https://example.invalid/foreign'})});
assert.equal(result.entries.length,0);
// Still fail-closed on contradictory explicit identity information.
assert.throws(()=>ctx.parseAtom(feed([element('entry',[
  txt('yt:videoId',videoA),txt('id','yt:video:'+videoB)])])), /Conflicting video identifiers/);
assert.throws(()=>ctx.parseAtom(feed([element('entry',[
  txt('yt:channelId','UCaaaaaaaaaaaaaaaaaaaaaa'),txt('id','yt:video:'+videoA)])])), /different channel/);
// Logging: record only metadata about the parse, no video titles or XML payload.
const engine=fs.readFileSync(new URL('../package/contents/ui/UploadEngine.qml',import.meta.url),'utf8');
for(const expected of ['YTUPLOAD_DEV15','PARSE_RESULT','PARSE_EMPTY_SAMPLE','FETCH_OK','FETCH_ERROR','developmentLogging: true'])
  assert.ok(engine.includes(expected),expected);
assert.ok(!engine.includes('console.log(xhr.responseText)'));
console.log('PASS reduced DOM fallbacks, 15-entry regression, identity rejection and debug log markers');
