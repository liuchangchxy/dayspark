const path=require('path');const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto('file://'+path.resolve(__dirname,'..','..','index.html'));
 await p.waitForFunction(()=>window.__READY__===true);
 console.log(await p.evaluate(()=>{
   const proj=window.Store.actionProjection(window.Store.state.actionDate);
   return {
     allocTodos: proj.allocations.map(x=>x.todo.summary),
     dueTodos: proj.dueTodayTodos.map(t=>t.summary),
     overlap: proj.dueTodayTodos.filter(t=>proj.allocations.some(a=>a.todo.id===t.id)).map(t=>t.summary),
   };
 }));
 await b.close();
})();
