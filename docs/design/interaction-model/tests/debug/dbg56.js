const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 console.log(await p.evaluate(()=>{
   const e=window.Store.state.events.find(x=>x.rrule&&!x.deletedAt);
   const ms=e.startDt.getTime();
   const a=window.Store.splitEventOccurrence(e.id, ms, {summary:'A'});
   const b2=window.Store.splitEventOccurrence(e.id, ms, {summary:'B'});
   const series=window.Store.eventById(e.id);
   return {
     aId:a.copy.id, bId:b2.copy.id, same:a.copy.id===b2.copy.id, updated:b2.updated,
     copySummary:window.Store.eventById(b2.copy.id).summary,
     exdates:series.exdates.length,
     copies:window.Store.state.events.filter(x=>x.splitFrom===e.id).map(x=>({id:x.id,s:x.summary,anchor:x.splitAnchor})),
     anchorWanted: Math.floor(ms/86400000)*86400000,
   };
 }));
 await b.close();
})();
