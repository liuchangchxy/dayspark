const path=require('path');
const {chromium}=require('playwright-core');
const CHROME='/Users/chang/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const URL='file://'+path.resolve(__dirname,'..','..','index.html');
(async()=>{
 const b=await chromium.launch({executablePath:CHROME});
 const p=await b.newPage({viewport:{width:1440,height:900}});
 p.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await p.goto(URL); await p.waitForFunction(()=>window.__READY__===true);
 await p.evaluate(()=>window.App.go('todos'));
 await p.waitForTimeout(200);
 console.log('helpers?', await p.evaluate(()=>!!window.__todoHelpers));
 await p.evaluate(()=>window.__todoHelpers.setView({ kind:'day', day: window.U.addDays(window.U.startOfDay(window.U.now()), 40) }));
 await p.waitForTimeout(250);
 console.log(await p.evaluate(()=>({
   empty: document.querySelectorAll('.empty').length,
   view: JSON.stringify(window.Store.state.todosView),
   body: document.querySelector('#view').textContent.slice(0,200),
 })));
 await b.close();
})();
