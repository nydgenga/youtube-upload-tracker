// Execute the actual QML functions in a mocked context; test manual refresh,
// cooldown eligibility, duplicate prevention, removal and channel rekeying.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const engine = fs.readFileSync(new URL('../package/contents/ui/UploadEngine.qml', import.meta.url), 'utf8');
const main = fs.readFileSync(new URL('../package/contents/ui/main.qml', import.meta.url), 'utf8');
function extract(name) {
    const m = new RegExp('\\bfunction\\s+' + name + '\\s*\\(').exec(engine);
    assert.ok(m, `Missing ${name}`);
    const start = engine.indexOf('{', m.index);
    let depth = 0;
    for (let i = start; i < engine.length; i++) {
        if (engine[i] === '{') depth++;
        if (engine[i] === '}' && --depth === 0) return engine.slice(m.index, i + 1);
    }
    throw new Error('Unbalanced ' + name);
}
const now = Date.now();
let rows = ['a','b','c'].map(id => ({id, failures:0, next_check_ms:now+900000}));
let dueNowCalls=0, ticks=0;
const removed=[], finished=[], logs=[];
const context={
    store: {
        allChannels: () => rows,
        setDueNowEligible: () => { dueNowCalls++; },
        removeChannel: id => { removed.push(id); rows=rows.filter(r=>r.id!==id); }
    },
    tick: () => { ticks++; }, changed: () => {},
    debugLog: (...args) => logs.push(args),
    manualRefreshActive:false, manualRefreshRemaining:0, manualRefreshErrors:0,
    manualRefreshDeferred:0, pendingManualRefresh:{},
    active:{}, recovering:{}, upstreamOutageActive:false,
    manualRefreshFinished: (errorCount,deferredCount) => finished.push([errorCount,deferredCount]),
    problem: message=>{throw new Error(message);}
};
vm.createContext(context);
vm.runInContext(['refreshAll','finishManualRefreshChannel','rekeyManualRefreshChannel','forgetChannel'].map(extract).join('\n'),context);

context.refreshAll();
assert.equal(context.manualRefreshActive,true);
assert.equal(context.manualRefreshRemaining,3);
assert.equal(dueNowCalls,1);
assert.equal(ticks,1);
context.refreshAll();
assert.equal(dueNowCalls,1,'Ignore double clicks');
context.finishManualRefreshChannel('a',false,false);
context.finishManualRefreshChannel('a',true,false);
context.finishManualRefreshChannel('b',true,false);
context.finishManualRefreshChannel('c',false,false);
assert.equal(context.manualRefreshActive,false);
assert.deepEqual(finished,[[1,0]]);

rows=[{id:'a',failures:0,next_check_ms:now+900000},
      {id:'b',failures:2,next_check_ms:now+600000},
      {id:'c',failures:0,next_check_ms:now+900000}];
context.refreshAll();
assert.equal(context.manualRefreshRemaining,2,'Failed channel on cooldown must be skipped');
assert.equal(context.manualRefreshDeferred,1);
assert.equal(context.pendingManualRefresh.b,undefined);
context.rekeyManualRefreshChannel('a','x');
context.finishManualRefreshChannel('a',true,false);
assert.equal(context.manualRefreshRemaining,2,'Old ID no longer pending');
context.finishManualRefreshChannel('x',false,false);
context.forgetChannel('c');
assert.equal(context.manualRefreshRemaining,0);
assert.deepEqual(finished,[[1,0],[0,1]]);

rows=[{id:'c',failures:3,next_check_ms:now+1200000}];
context.refreshAll();
assert.equal(context.manualRefreshActive,false);
assert.deepEqual(finished,[[1,0],[0,1],[0,1]]);
assert.equal(dueNowCalls,2,'No DB changes when all channels are cooling down');
context.upstreamOutageActive=true;
context.refreshAll();
assert.deepEqual(finished.at(-1),[0,1]);
assert.equal(dueNowCalls,2,'Manual refresh may not bypass upstream outage');

assert.ok(!main.includes('root.infoMessage = i18n("Checking all followed channels…")'));
assert.ok(main.includes('enabled: !feedEngine.manualRefreshActive'));
assert.ok(main.includes('onManualRefreshFinished: function(errorCount, deferredCount)'));
assert.ok(engine.includes('store.setDueNowEligible(now)'));
assert.ok(engine.includes('finishManualRefreshChannel(id, true, false)'));
assert.ok(engine.includes('rekeyManualRefreshChannel(oldId, candidate)'));
console.log('PASS manual refresh respects cooldowns and outage; no overlap, stuck spinner or lost rekey');
