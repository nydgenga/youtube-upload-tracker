import fs from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const ui = fileURLToPath(new URL('../package/contents/ui/', import.meta.url));
const engine = fs.readFileSync(ui + 'UploadEngine.qml', 'utf8');
assert.match(engine, /property bool developmentLogging: true/);
assert.match(engine, /console\.warn\("YTUPLOAD_DEV15 event="/);
assert.doesNotMatch(engine, /console\.log\("YTUPLOAD_DEV15 event="/);
for (const tag of ['FETCH_START', 'PARSE_RESULT', 'FETCH_OK', 'FETCH_ERROR'])
  assert.ok(engine.includes('debugLog("' + tag + '"'),tag);
assert.ok(!engine.includes('console.warn(xhr.responseText)'));
const meta = JSON.parse(fs.readFileSync(fileURLToPath(new URL('../package/metadata.json', import.meta.url)), 'utf8'));
assert.equal(meta.KPlugin.Version, '0.1.0-dev15');
console.log('PASS dev15 preserved warning-level diagnostic logging and metadata');
