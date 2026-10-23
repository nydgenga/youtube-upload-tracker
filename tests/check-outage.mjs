// Unit tests of the actual QML circuit-breaker functions, using a mocked store
// and network starter. Never requires a live YouTube connection.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const engine=fs.readFileSync(new URL('../package/contents/ui/UploadEngine.qml',import.meta.url),'utf8');
function fn(name){
    const m=new RegExp('\\bfunction\\s+'+name+'\\s*\\(').exec(engine);
    assert.ok(m,`Missing ${name}`);
    const start=engine.indexOf('{',m.index); let depth=0;
    for(let i=start;i<engine.length;i++){
        if(engine[i]==='{') depth++;
        if(engine[i]==='}'&&--depth===0)return engine.slice(m.index,i+1);
    }
    throw new Error('Unbalanced '+name);
}
let rows=['a','b','c','d','e','f'].map((id,i)=>({id,failures:0,next_check_ms:0}));
const logs=[], started=[], completed=[];
const context={
    store:{
        allChannels:()=>rows,
        dueChannels:(now,limit)=>rows.filter(r=>r.next_check_ms<=now).slice(0,limit),
        markFailure:(id,msg,next)=>{const r=rows.find(x=>x.id===id);r.failures++;r.next_check_ms=next;},
        pruneSeen:()=>{}
    },
    recentFeedResults:[],upstreamOutageActive:false,upstreamProbeAfterMs:0,
    upstreamProbeId:'',upstreamProbeFailures:0,upstreamProbeTimerReady:false,
    outageProbeTimer:{interval:0,started:false,stop(){this.started=false;},start(){this.started=true;}},
    manualRefreshActive:false,manualRefreshRemaining:0,manualRefreshDeferred:0,
    manualRefreshErrors:0,pendingManualRefresh:{},
    manualRefreshFinished:(e,d)=>completed.push([e,d]),
    debugLog:(...x)=>logs.push(x),
    problem:()=>{},changed:()=>{},
    active:{},recovering:{},inFlightCount:0,maxConcurrent:4,lastStartMs:0,
    resolverRequest:null,lastMaintenanceMs:Date.now(),
    startFeed:(row,probe)=>{started.push({id:row.id,probe});context.active[row.id]={};context.inFlightCount++;},
};
vm.createContext(context);
vm.runInContext(['observeFeedStatus','scheduleOutageProbe','enterUpstreamOutage',
    'failOutageProbe','completeOutageProbe','finishManualRefreshChannel',
    'failure','tick'].map(fn).join('\n'),context);
// Individual or repeated 404s should not cause a broad outage.
context.observeFeedStatus('a',404);
context.observeFeedStatus('a',404);
assert.equal(context.recentFeedResults.length,1);
context.observeFeedStatus('b',200);
context.observeFeedStatus('c',404);
context.observeFeedStatus('d',404);
assert.equal(context.upstreamOutageActive,false,'3/4 bad is insufficient because need four failures');
// Completing a real HTTP failure is routed to both per-channel backoff and
// global outage evidence, but keeps all other cached channels intact.
context.failure('e','HTTP 404',404);
assert.equal(context.upstreamOutageActive,true);
assert.ok(context.upstreamProbeAfterMs>Date.now());
assert.equal(context.upstreamProbeTimerReady,false);
assert.equal(context.outageProbeTimer.started,true);
assert.equal(rows.find(r=>r.id==='e').failures,1);
assert.ok(logs.some(v=>v[0]==='OUTAGE_ENTER'));

context.tick();
assert.equal(started.length,0,'Routine polling must halt during outage');
context.upstreamProbeAfterMs=Date.now()-100;
context.tick();
assert.equal(started.length,0,'Past wall clock deadline alone cannot launch probe');
context.upstreamProbeTimerReady=true; // simulate QML Timer.onTriggered
context.tick();
assert.equal(started.length,1);
assert.equal(started[0].probe,true);
assert.equal(context.upstreamProbeTimerReady,false,'Probe consumes one-shot timer ready signal');
assert.equal(context.upstreamProbeId,started[0].id);
context.lastStartMs=0;
context.tick();
assert.equal(started.length,1,'Only one probe at a time');
const probeId=context.upstreamProbeId;
context.failOutageProbe(probeId);
assert.equal(context.upstreamOutageActive,true);
assert.equal(context.upstreamProbeFailures,1);
assert.ok(context.upstreamProbeAfterMs-Date.now()>19*60000,'Second probe backs off by 20 minutes');
// Clear simulated in-flight probe and mark a due channel.
context.active={};context.inFlightCount=0;
context.upstreamProbeAfterMs=Date.now()-100;
context.tick();
assert.equal(started.length,1,'New delay requires a fresh timer signal');
context.upstreamProbeTimerReady=true;
context.tick();
assert.equal(started.length,2,'Second permitted probe');
context.completeOutageProbe(context.upstreamProbeId);
assert.equal(context.upstreamOutageActive,false);
assert.equal(context.upstreamProbeId,'');
assert.equal(context.upstreamProbeFailures,0);
assert.equal(context.recentFeedResults.length,0);
assert.ok(logs.some(v=>v[0]==='OUTAGE_RECOVERED'));
// Background scheduler resumes when the circuit breaker is cleared.
context.active={};context.inFlightCount=0;context.lastStartMs=0;
context.tick();
assert.equal(started.length,3);
assert.equal(started.at(-1).probe,false);

// At the moment a global outage is detected, queued manual work is deferred;
// already-active work is still permitted to finish and close the progress.
// An early/misfired timer cannot bypass a future wall-clock deadline.
context.upstreamOutageActive=true;
context.upstreamProbeId='';context.upstreamProbeTimerReady=true;
context.upstreamProbeAfterMs=Date.now()+600000;
context.active={};context.inFlightCount=0;context.lastStartMs=0;
context.tick();
assert.equal(started.length,3,'Early timer signal must not launch a feed');
assert.equal(context.upstreamProbeTimerReady,false,'Early timer signal is consumed and rearmed');
assert.equal(context.outageProbeTimer.started,true);
context.upstreamOutageActive=false;
context.upstreamProbeId='';
context.active={c:{}};context.inFlightCount=1;
context.pendingManualRefresh={a:true,b:true,c:true,d:true};
context.manualRefreshRemaining=4;context.manualRefreshActive=true;
context.manualRefreshDeferred=0;context.manualRefreshErrors=0;
context.enterUpstreamOutage(4,4);
assert.equal(context.manualRefreshRemaining,1);
assert.equal(context.manualRefreshDeferred,3);
context.finishManualRefreshChannel('c',false,false);
assert.equal(context.manualRefreshActive,false);
assert.deepEqual(completed.at(-1),[0,3]);

// The source must wire HTTP status, timeout and parsed probe success to the
// circuit breaker, not merely declare unused functions.
assert.ok(engine.includes('failure(id, "HTTP " + xhr.status, xhr.status)'));
assert.ok(engine.includes('if (isProbe) completeOutageProbe(id)'));
assert.ok(engine.includes('startFeed(channels[p], true)'));
assert.ok(engine.includes('startFeed(channels[j], false)'));
assert.ok(engine.includes('!upstreamProbeTimerReady || now < upstreamProbeAfterMs'));
assert.ok(engine.includes('id: outageProbeTimer'));
assert.ok(engine.includes('outageProbeTimer.start()'));
assert.ok(engine.includes('engine.upstreamProbeTimerReady = true'));
assert.ok(engine.includes('instance=" + instanceId')); 
assert.ok(engine.includes('if (upstreamProbeId === id) failOutageProbe(id)'));
console.log('PASS cross-channel outage threshold, bounded probes, recovery, active manual-progress completion');
